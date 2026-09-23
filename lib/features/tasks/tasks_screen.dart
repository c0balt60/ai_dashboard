import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../../utils/time_format.dart';
import '../../widgets/common.dart';
import '../../widgets/layout.dart';
import '../../widgets/page.dart';
import '../../widgets/sheets/assign_agent_sheet.dart';
import '../../widgets/status/status_badge.dart';
import '../../widgets/status/status_visuals.dart';
import '../../widgets/task_card.dart';

/// Tasks tab: the queue grouped by state, with finished work tucked away in a
/// collapsible "Done" section. Phones stack the groups; wide screens show
/// Active, Waiting and Backlog as kanban columns.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  /// Content width from which the open groups become side-by-side columns.
  static const _kanbanWidth = 900.0;

  static const _openSections = [
    ('Active', TaskState.active, 'Nothing running right now.'),
    ('Waiting', TaskState.waiting, 'No tasks queued for an agent.'),
    ('Backlog', TaskState.backlog, 'The backlog is empty.'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byState = ref.watch(tasksByStateProvider);

    return AppPage(
      title: 'Tasks',
      icon: Icons.checklist,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.newTask()),
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: AsyncValueView(
            ref.watch(tasksProvider),
            data: (_) {
              final done =
                  [
                    ...?byState[TaskState.completed],
                    ...?byState[TaskState.failed],
                  ]..sort(
                    (a, b) => (b.completedAt ?? b.updatedAt).compareTo(
                      a.completedAt ?? a.updatedAt,
                    ),
                  );

              return LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= _kanbanWidth;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CountPills(byState: byState, doneCount: done.length),
                      if (wide)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final (i, (title, state, emptyText))
                                  in _openSections.indexed) ...[
                                if (i > 0) const SizedBox(width: 12),
                                Expanded(
                                  child: _KanbanColumn(
                                    title: title,
                                    state: state,
                                    tasks: byState[state] ?? const [],
                                    emptyText: emptyText,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      else
                        for (final (title, state, emptyText)
                            in _openSections) ...[
                          SectionHeader(
                            title,
                            count: byState[state]?.length ?? 0,
                          ),
                          _TaskList(
                            tasks: byState[state] ?? const [],
                            emptyText: emptyText,
                          ),
                        ],
                      const SizedBox(height: 12),
                      _DoneSection(done: done),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Horizontally scrolling pastel pills with the task count per group.
class _CountPills extends StatelessWidget {
  const _CountPills({required this.byState, required this.doneCount});

  final Map<TaskState, List<AgentTask>> byState;
  final int doneCount;

  @override
  Widget build(BuildContext context) {
    final pills = [
      for (final state in [
        TaskState.active,
        TaskState.waiting,
        TaskState.backlog,
      ])
        (state.visual(context), byState[state]?.length ?? 0),
      (TaskState.completed.visual(context), doneCount),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final (i, (visual, count)) in pills.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            _CountPill(
              visual: visual,
              label: i == pills.length - 1 ? 'Done' : visual.label,
              count: count,
            ),
          ],
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.visual,
    required this.label,
    required this.count,
  });

  final StatusVisual visual;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppSurfaces.of(context).tint(visual.color, theme.brightness),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 16, color: visual.color),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded pastel column of one task group for the wide kanban layout.
class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.title,
    required this.state,
    required this.tasks,
    required this.emptyText,
  });

  final String title;
  final TaskState state;
  final List<AgentTask> tasks;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = state.visual(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppSurfaces.of(context).tint(visual.color, theme.brightness),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Row(
                children: [
                  Icon(visual.icon, size: 20, color: visual.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppSurfaces.of(context).card,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${tasks.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  emptyText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final (i, task) in tasks.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              TaskCard(task, onTap: () => _showTaskDetails(context, task.id)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Stacked task cards for one group on phones, or its empty text.
class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks, required this.emptyText});

  final List<AgentTask> tasks;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: tasks.isEmpty
          ? Text(
              emptyText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, task) in tasks.indexed) ...[
                  if (i > 0) const SizedBox(height: 8),
                  TaskCard(
                    task,
                    onTap: () => _showTaskDetails(context, task.id),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Collapsible list of completed and failed tasks, a grid on wide screens.
class _DoneSection extends StatelessWidget {
  const _DoneSection({required this.done});

  final List<AgentTask> done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      key: const PageStorageKey('tasks-done'),
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      title: SectionHeader(
        'Done',
        count: done.length,
        padding: EdgeInsets.zero,
      ),
      children: [
        if (done.isEmpty)
          Text(
            'Completed and failed tasks show up here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ResponsiveGrid(
            spacing: 8,
            children: [
              for (final task in done)
                TaskCard(task, onTap: () => _showTaskDetails(context, task.id)),
            ],
          ),
      ],
    );
  }
}

Future<void> _showTaskDetails(BuildContext context, String taskId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (context) => _TaskDetailsSheet(taskId),
  );
}

class _TaskDetailsSheet extends ConsumerWidget {
  const _TaskDetailsSheet(this.taskId);

  final String taskId;

  Future<void> _moveTo(
    BuildContext context,
    WidgetRef ref,
    AgentTask task,
    TaskState state,
    String message,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await ref.read(backendProvider).updateTaskState(task.id, state);
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final task = ref.watch(taskProvider(taskId));

    if (task == null) {
      return const SafeArea(
        child: EmptyState(
          icon: Icons.task_alt,
          message: 'This task no longer exists.',
        ),
      );
    }

    final visual = task.state.visual(context);
    final project = ref.watch(projectProvider(task.projectId));
    final agent = task.agentId == null
        ? null
        : ref.watch(agentProvider(task.agentId!));
    final doneColor = StatusColors.of(context).completed;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final doneSteps = task.steps.where((s) => s.done).length;

    final canAssign =
        task.state == TaskState.backlog || task.state == TaskState.waiting;
    final canBacklog = task.state != TaskState.backlog;
    final isOpen = !task.isDone;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(task.title, style: theme.textTheme.titleLarge),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: StatusBadge(visual),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.folder_outlined,
              text: project?.name ?? 'Unknown project',
            ),
            _DetailRow(
              icon: agent?.type.icon ?? Icons.person_off_outlined,
              text: agent == null
                  ? 'No agent assigned'
                  : '${agent.name} (${agent.type.label})',
            ),
            _DetailRow(
              icon: Icons.schedule,
              text: task.completedAt != null
                  ? 'Finished ${timeAgo(task.completedAt!)}'
                  : 'Created ${timeAgo(task.createdAt)} · updated '
                        '${timeAgo(task.updatedAt)}',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      minHeight: 10,
                      color: visual.color,
                      backgroundColor: visual.color.withValues(alpha: 0.16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(task.progress * 100).round()}%',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (task.steps.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 8),
                child: Text(
                  'Steps · $doneSteps/${task.steps.length}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    for (final step in task.steps)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              step.done
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 20,
                              color: step.done ? doneColor : scheme.outline,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                step.title,
                                style: step.done
                                    ? muted?.copyWith(
                                        decoration: TextDecoration.lineThrough,
                                      )
                                    : theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canAssign)
                  FilledButton.icon(
                    onPressed: () => showAssignAgentSheet(
                      context,
                      taskId: task.id,
                      projectId: task.projectId,
                    ),
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(agent == null ? 'Assign agent' : 'Reassign'),
                  ),
                if (agent != null)
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final router = GoRouter.of(context);
                      Navigator.pop(context);
                      router.push(AppRoutes.agent(agent.id));
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Open agent chat'),
                  ),
                if (canBacklog)
                  OutlinedButton.icon(
                    onPressed: () => _moveTo(
                      context,
                      ref,
                      task,
                      TaskState.backlog,
                      'Moved to backlog',
                    ),
                    icon: const Icon(Icons.inbox_outlined),
                    label: const Text('Move to backlog'),
                  ),
                if (isOpen)
                  OutlinedButton.icon(
                    onPressed: () => _moveTo(
                      context,
                      ref,
                      task,
                      TaskState.completed,
                      'Marked as completed',
                    ),
                    icon: const Icon(Icons.check),
                    label: const Text('Mark completed'),
                  ),
                if (isOpen)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    onPressed: () => _moveTo(
                      context,
                      ref,
                      task,
                      TaskState.failed,
                      'Task cancelled',
                    ),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
