import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../../utils/time_format.dart';
import '../../widgets/agent_card.dart';
import '../../widgets/common.dart';
import '../../widgets/sheets/assign_agent_sheet.dart';
import '../../widgets/sheets/run_command_sheet.dart';
import '../../widgets/status/status_badge.dart';
import '../../widgets/status/status_visuals.dart';
import '../../widgets/task_card.dart';

const _listPadding = EdgeInsets.fromLTRB(16, 0, 16, 96);
const _headerPadding = EdgeInsets.fromLTRB(0, 20, 0, 8);

/// Full-screen view of one project: its agents and tasks, test runs and
/// history.
class ProjectDashboardScreen extends ConsumerWidget {
  const ProjectDashboardScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);
    final project = ref.watch(projectProvider(projectId));

    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Project')),
        body: projectsAsync.value == null
            ? AsyncValueView(
                projectsAsync,
                data: (_) => const SizedBox.shrink(),
              )
            : const EmptyState(
                icon: Icons.folder_off_outlined,
                message: 'This project no longer exists on your PC.',
              ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(project.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Assign agent',
              onPressed: () =>
                  showAssignAgentSheet(context, projectId: projectId),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showRunCommandSheet(context, projectId),
          icon: const Icon(Icons.terminal),
          label: const Text('Run command'),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProjectHeader(project),
              TabBar(
                tabs: [
                  const Tab(text: 'Overview'),
                  Tab(text: 'Tests (${project.testRuns.length})'),
                  const Tab(text: 'History'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _OverviewTab(projectId),
                    _TestsTab(project),
                    _HistoryTab(project),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader(this.project);

  final Project project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.path,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              InfoChip(project.branch, icon: Icons.call_split),
              InfoChip(
                'Active ${timeAgo(project.lastActivity)}',
                icon: Icons.schedule,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab(this.projectId);

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(agentsForProjectProvider(projectId));
    final tasks = ref.watch(tasksForProjectProvider(projectId));
    final current = [
      ...tasks.where((t) => t.state == TaskState.active),
      ...tasks.where((t) => t.state == TaskState.waiting),
    ];

    return ListView(
      padding: _listPadding,
      children: [
        SectionHeader('Agents', count: agents.length, padding: _headerPadding),
        if (agents.isEmpty)
          const EmptyState(
            icon: Icons.smart_toy_outlined,
            message: 'No agents here yet. Use "Assign agent" to add one.',
          )
        else
          for (final agent in agents)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AgentCard(agent),
            ),
        SectionHeader(
          'Current tasks',
          count: current.length,
          padding: _headerPadding,
        ),
        if (current.isEmpty)
          const EmptyState(
            icon: Icons.checklist,
            message: 'No active or waiting tasks.',
          )
        else
          for (final task in current)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CurrentTaskCard(task),
            ),
      ],
    );
  }
}

class _CurrentTaskCard extends ConsumerWidget {
  const _CurrentTaskCard(this.task);

  final AgentTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final visual = task.state.visual(context);
    final agent = task.agentId == null
        ? null
        : ref.watch(agentProvider(task.agentId!));
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      child: InkWell(
        onTap: agent == null
            ? null
            : () => context.push(AppRoutes.agent(agent.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(task.title, style: theme.textTheme.titleSmall),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge(visual, dense: true),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                agent == null
                    ? 'Unassigned'
                    : '(${agent.type.shortLabel}) ${agent.name}',
                style: muted,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: task.progress,
                        minHeight: 6,
                        color: visual.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(task.progress * 100).round()}%',
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
              if (task.steps.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final step in task.steps)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          step.done
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 18,
                          color: step.done
                              ? colors.completed
                              : theme.colorScheme.outline,
                          semanticLabel: step.done ? 'Done' : 'Not done',
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            step.title,
                            style: step.done
                                ? muted
                                : theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TestsTab extends StatelessWidget {
  const _TestsTab(this.project);

  final Project project;

  @override
  Widget build(BuildContext context) {
    if (project.testRuns.isEmpty) {
      return const EmptyState(
        icon: Icons.science_outlined,
        message: 'No test runs yet.',
      );
    }
    return ListView.separated(
      padding: _listPadding.copyWith(top: 12),
      itemCount: project.testRuns.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _TestRunCard(project.testRuns[i]),
    );
  }
}

class _TestRunCard extends StatelessWidget {
  const _TestRunCard(this.run);

  final TestRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final visual = run.status.visual(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: run.status == TestStatus.running
            ? SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: visual.color,
                ),
              )
            : Icon(
                visual.icon,
                color: visual.color,
                semanticLabel: visual.label,
              ),
        title: Text(run.suite, style: theme.textTheme.titleSmall),
        subtitle: Text.rich(
          TextSpan(
            style: muted,
            children: [
              TextSpan(
                text: '${run.passed} passed',
                style: TextStyle(color: colors.completed),
              ),
              const TextSpan(text: ' · '),
              TextSpan(
                text: '${run.failed} failed',
                style: run.failed > 0 ? TextStyle(color: colors.failed) : null,
              ),
              TextSpan(
                text: ' · ${formatDuration(run.duration)} · ${timeAgo(run.at)}',
              ),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          if (run.failingTests.isEmpty)
            ListTile(
              dense: true,
              leading: Icon(
                run.status == TestStatus.running
                    ? Icons.hourglass_top
                    : Icons.check,
                size: 18,
                color: visual.color,
              ),
              title: Text(
                run.status == TestStatus.running
                    ? 'Still running…'
                    : 'No failing tests.',
              ),
            )
          else
            for (final name in run.failingTests)
              ListTile(
                dense: true,
                leading: Icon(Icons.close, size: 18, color: colors.failed),
                title: Text(
                  name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab(this.project);

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finished =
        ref
            .watch(tasksForProjectProvider(project.id))
            .where((t) => t.isDone)
            .toList()
          ..sort(
            (a, b) => (b.completedAt ?? b.updatedAt).compareTo(
              a.completedAt ?? a.updatedAt,
            ),
          );

    return ListView(
      padding: _listPadding,
      children: [
        SectionHeader(
          'Finished tasks',
          count: finished.length,
          padding: _headerPadding,
        ),
        if (finished.isEmpty)
          const EmptyState(
            icon: Icons.task_alt,
            message: 'No finished tasks yet.',
          )
        else
          for (final task in finished)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TaskCard(task, showProject: false),
            ),
        SectionHeader(
          'Activity log',
          count: project.log.length,
          padding: _headerPadding,
        ),
        if (project.log.isEmpty)
          const EmptyState(icon: Icons.history, message: 'No activity yet.')
        else
          Card(
            child: Column(
              children: [
                for (final (i, entry) in project.log.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  _LogRow(entry),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _LogRow extends ConsumerWidget {
  const _LogRow(this.entry);

  final LogEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final visual = entry.level.visual(context);
    final agent = entry.agentId == null
        ? null
        : ref.watch(agentProvider(entry.agentId!));

    return ListTile(
      dense: true,
      leading: Icon(
        visual.icon,
        color: visual.color,
        size: entry.level == LogLevel.info ? 12 : 20,
        semanticLabel: visual.label,
      ),
      minLeadingWidth: 24,
      title: Text(entry.message),
      subtitle: Text([?agent?.name, timeAgo(entry.at)].join(' · ')),
      trailing: Text(
        clockTime(entry.at),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
