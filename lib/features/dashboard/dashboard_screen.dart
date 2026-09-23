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
import '../../widgets/layout.dart';
import '../../widgets/page.dart';
import '../../widgets/project_card.dart';
import '../../widgets/prompt_bar.dart';
import '../../widgets/sheets/new_task_sheet.dart';
import '../../widgets/status/status_visuals.dart';

final _pingProvider = FutureProvider.autoDispose<Duration>(
  (ref) => ref.watch(backendProvider).ping(),
);

/// Home tab: connection status, headline stats, weekly throughput and what
/// agents are doing right now, with a floating bar to prompt any agent.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = <AsyncValue<Object?>>[
      ref.watch(agentsProvider),
      ref.watch(projectsProvider),
      ref.watch(tasksProvider),
    ].where((v) => v.value == null).firstOrNull;

    return AppPage(
      title: 'Dashboard',
      icon: Icons.home_outlined,
      actions: [
        HeaderAction(
          icon: Icons.add,
          tooltip: 'New task',
          onPressed: () => showNewTaskSheet(context),
        ),
      ],
      onRefresh: () => ref.refresh(_pingProvider.future),
      bottomBar: const _PromptBar(),
      slivers: [
        if (pending != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: AsyncValueView(
              pending,
              data: (_) => const SizedBox.shrink(),
            ),
          )
        else
          SliverList.list(
            children: const [
              _Padded(_ConnectionPill()),
              SizedBox(height: 12),
              _Padded(_StatsGrid()),
              _ChartAndActivity(),
              _ActiveAgents(),
              _RecentProjects(),
            ],
          ),
      ],
    );
  }
}

class _Padded extends StatelessWidget {
  const _Padded(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: child,
  );
}

/// Pastel pill showing the PC link and its latest ping; tapping re-pings.
class _ConnectionPill extends ConsumerWidget {
  const _ConnectionPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final ping = ref.watch(_pingProvider);

    final (pingLabel, color) = switch (ping) {
      AsyncValue(hasError: true) => ('Ping failed', colors.failed),
      AsyncValue(value: final latency?) => (
        '${latency.inMilliseconds} ms',
        latency.inMilliseconds < 100 ? colors.completed : colors.waiting,
      ),
      _ => ('Pinging…', colors.idle),
    };
    const shape = StadiumBorder();

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Semantics(
          button: true,
          label: 'Main PC, connected (mock). $pingLabel. Tap to ping again.',
          excludeSemantics: true,
          onTap: () => ref.invalidate(_pingProvider),
          child: Material(
            color: AppSurfaces.of(context).tint(color, theme.brightness),
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: shape,
              onTap: ping.isLoading
                  ? null
                  : () => ref.invalidate(_pingProvider),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.desktop_windows, size: 18, color: color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Main PC · Connected (mock)',
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        pingLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox.square(
                        dimension: 18,
                        child: ping.isLoading
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : Icon(
                                Icons.refresh,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsGrid extends ConsumerWidget {
  const _StatsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final colors = StatusColors.of(context);
    final rate = stats.testPassRate;

    return ResponsiveGrid(
      minItemWidth: 150,
      maxColumns: 4,
      children: [
        StatTile(
          icon: Icons.smart_toy,
          label: 'Active agents',
          value: '${stats.activeAgents} of ${stats.totalAgents}',
          caption: 'running now',
          color: colors.running,
          onTap: () => context.go(AppRoutes.agents),
        ),
        StatTile(
          icon: Icons.bolt,
          label: 'Running tasks',
          value: '${stats.runningTasks}',
          caption: '+${stats.queuedTasks} queued',
          color: colors.waiting,
          onTap: () => context.go(AppRoutes.tasks),
        ),
        StatTile(
          icon: Icons.science,
          label: 'Test pass rate',
          value: rate == null ? '–' : '${(rate * 100).round()}%',
          caption: 'latest runs',
          color: switch (rate) {
            null => colors.idle,
            >= 0.95 => colors.completed,
            >= 0.8 => colors.waiting,
            _ => colors.failed,
          },
          onTap: () => context.go(AppRoutes.projects),
        ),
        StatTile(
          icon: Icons.task_alt,
          label: 'Done in 24h',
          value: '${stats.completedLast24h}',
          caption: 'tasks completed',
          color: colors.completed,
          onTap: () => context.go(AppRoutes.tasks),
        ),
      ],
    );
  }
}

/// Weekly chart and recent activity: stacked on phones, side by side (top
/// aligned, no intrinsic sizing) once two 420dp columns fit.
class _ChartAndActivity extends StatelessWidget {
  const _ChartAndActivity();

  static const _minColumnWidth = 420.0;
  static const _gap = 12.0;
  static const _headerPadding = EdgeInsets.fromLTRB(0, 24, 0, 8);

  @override
  Widget build(BuildContext context) {
    return _Padded(
      LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _minColumnWidth * 2 + _gap;
          if (!wide) {
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WeeklyChart(headerPadding: _headerPadding),
                _RecentActivity(headerPadding: _headerPadding),
              ],
            );
          }
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _WeeklyChart(
                  headerPadding: _headerPadding,
                  barAreaHeight: 180,
                ),
              ),
              SizedBox(width: _gap),
              Expanded(child: _RecentActivity(headerPadding: _headerPadding)),
            ],
          );
        },
      ),
    );
  }
}

class _WeeklyChart extends ConsumerWidget {
  const _WeeklyChart({required this.headerPadding, this.barAreaHeight = 96});

  final EdgeInsetsGeometry headerPadding;
  final double barAreaHeight;

  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perDay = ref.watch(dashboardStatsProvider).completedPerDay;
    final now = DateTime.now();
    final days = [
      for (var i = 0; i < perDay.length; i++)
        DateTime(now.year, now.month, now.day - (perDay.length - 1 - i)),
    ];
    final maxCount = perDay.fold(0, (a, b) => a > b ? a : b);
    final total = perDay.fold(0, (a, b) => a + b);
    final letters = [for (final d in days) _dayLetters[d.weekday - 1]];
    final summary = [
      for (var i = 0; i < days.length; i++) '${letters[i]} ${perDay[i]}',
    ].join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Completed this week',
          count: total,
          padding: headerPadding,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
            child: Semantics(
              label: 'Tasks completed per day: $summary',
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < perDay.length; i++)
                      Expanded(
                        child: _Bar(
                          count: perDay[i],
                          // Empty days still get a stub so the baseline reads.
                          height: maxCount == 0
                              ? 6
                              : (perDay[i] / maxCount * barAreaHeight).clamp(
                                  6,
                                  barAreaHeight,
                                ),
                          day: letters[i],
                          highlighted: i == perDay.length - 1,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.count,
    required this.height,
    required this.day,
    required this.highlighted,
  });

  final int count;
  final double height;
  final String day;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: theme.textTheme.labelSmall?.copyWith(
            color: highlighted
                ? scheme.primary
                : count == 0
                ? scheme.outline
                : scheme.onSurfaceVariant,
            fontWeight: highlighted ? FontWeight.w700 : null,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 24,
          height: height,
          decoration: BoxDecoration(
            color: highlighted
                ? scheme.primary
                : scheme.primary.withValues(alpha: count == 0 ? 0.12 : 0.28),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: highlighted
              ? BoxDecoration(
                  color: scheme.inverseSurface,
                  shape: BoxShape.circle,
                )
              : null,
          child: Text(
            day,
            style: theme.textTheme.labelMedium?.copyWith(
              color: highlighted
                  ? scheme.onInverseSurface
                  : scheme.onSurfaceVariant,
              fontWeight: highlighted ? FontWeight.w700 : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActiveAgents extends ConsumerWidget {
  const _ActiveAgents();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(agentsProvider).value ?? const [];
    final busy = [
      ...agents.where((a) => a.status == AgentStatus.running),
      ...agents.where((a) => a.status == AgentStatus.waiting),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Active agents',
          count: busy.length,
          actionLabel: 'See all',
          onAction: () => context.go(AppRoutes.agents),
        ),
        if (busy.isEmpty)
          const EmptyState(
            icon: Icons.bedtime_outlined,
            message: 'No agents are running right now.',
          )
        else if (Breakpoints.isWide(context))
          _Padded(
            ResponsiveGrid(children: [for (final a in busy) AgentCard(a)]),
          )
        else
          // A Row rather than a fixed-height ListView so cards never clip at
          // large text scales; there are only ever a handful of agents.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, agent) in busy.indexed) ...[
                    if (i > 0) const SizedBox(width: 12),
                    AgentCard(agent, compact: true),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RecentProjects extends ConsumerWidget {
  const _RecentProjects();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = [...?ref.watch(projectsProvider).value]
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    final recent = projects.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Recent projects',
          actionLabel: 'See all',
          onAction: () => context.go(AppRoutes.projects),
        ),
        if (recent.isEmpty)
          const EmptyState(
            icon: Icons.folder_off_outlined,
            message: 'No projects yet.',
          )
        else
          _Padded(
            ResponsiveGrid(children: [for (final p in recent) ProjectCard(p)]),
          ),
      ],
    );
  }
}

class _RecentActivity extends ConsumerWidget {
  const _RecentActivity({required this.headerPadding});

  final EdgeInsetsGeometry headerPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(recentActivityProvider).take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Recent activity', padding: headerPadding),
        if (activity.isEmpty)
          const EmptyState(
            icon: Icons.history,
            message: 'Nothing has happened yet.',
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  for (final (i, item) in activity.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 56),
                    _ActivityRow(project: item.project, entry: item.entry),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.project, required this.entry});

  final Project project;
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = entry.level.visual(context);
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ListTile(
      dense: true,
      onTap: () => context.push(AppRoutes.project(project.id)),
      leading: Icon(
        visual.icon,
        color: visual.color,
        size: entry.level == LogLevel.info ? 12 : 20,
        semanticLabel: visual.label,
      ),
      minLeadingWidth: 24,
      title: Text(entry.message, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(project.name, overflow: TextOverflow.ellipsis),
      trailing: Text(timeAgo(entry.at), style: muted),
    );
  }
}

/// Floating "Ask an agent…" bar that opens a full chat with
/// [defaultChatAgentProvider]'s agent.
class _PromptBar extends ConsumerWidget {
  const _PromptBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    void open() {
      final agent = ref.read(defaultChatAgentProvider);
      if (agent == null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('No agents are running on your PC.')),
          );
        return;
      }
      context.push(AppRoutes.agent(agent.id));
    }

    return Semantics(
      button: true,
      label: 'Ask an agent',
      excludeSemantics: true,
      onTap: open,
      child: PromptBarFrame(
        onTap: open,
        child: Row(
          children: [
            const AiOrb(size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Ask an agent…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Ask an agent',
              onPressed: open,
              icon: const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    );
  }
}
