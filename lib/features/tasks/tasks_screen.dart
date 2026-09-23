import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../../utils/time_format.dart';
import '../../widgets/common.dart';
import '../../widgets/sheets/assign_agent_sheet.dart';
import '../../widgets/sheets/new_task_sheet.dart';
import '../../widgets/status/status_badge.dart';
import '../../widgets/status/status_visuals.dart';
import '../../widgets/task_card.dart';

/// Tasks tab: the queue grouped by state, with finished work tucked away in a
/// collapsible "Done" section.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  static const _openSections = [
    ('Active', TaskState.active, 'Nothing running right now.'),
    ('Waiting', TaskState.waiting, 'No tasks queued for an agent.'),
    ('Backlog', TaskState.backlog, 'The backlog is empty.'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final byState = ref.watch(tasksByStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showNewTaskSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
      body: AsyncValueView(
        ref.watch(tasksProvider),
        data: (_) {
          final done =
              [...?byState[TaskState.completed], ...?byState[TaskState.failed]]
                ..sort(
                  (a, b) => (b.completedAt ?? b.updatedAt).compareTo(
                    a.completedAt ?? a.updatedAt,
                  ),
                );

          return CustomScrollView(
            slivers: [
              for (final (title, state, emptyText) in _openSections) ...[
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title,
                    count: byState[state]?.length ?? 0,
                  ),
                ),
                _TaskListSliver(
                  tasks: byState[state] ?? const [],
                  emptyText: emptyText,
                ),
              ],
              SliverPadding(
                padding: const EdgeInsets.only(top: 12),
                sliver: SliverToBoxAdapter(
                  child: ExpansionTile(
                    key: const PageStorageKey('tasks-done'),
                    shape: const Border(),
                    collapsedShape: const Border(),
                    tilePadding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                    childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: SectionHeader(
                      'Done',
                      count: done.length,
                      padding: EdgeInsets.zero,
                    ),
                    children: [
                      if (done.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Completed and failed tasks show up here.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      for (final task in done)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TaskCard(
                            task,
                            onTap: () => _showTaskDetails(context, task.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Keeps the last card clear of the extended FAB.
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          );
        },
      ),
    );
  }
}

class _TaskListSliver extends StatelessWidget {
  const _TaskListSliver({required this.tasks, required this.emptyText});

  final List<AgentTask> tasks;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (tasks.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: Text(
            emptyText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.separated(
        itemCount: tasks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) => TaskCard(
          tasks[i],
          onTap: () => _showTaskDetails(context, tasks[i].id),
        ),
      ),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      minHeight: 8,
                      color: visual.color,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(task.progress * 100).round()}%',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            if (task.steps.isNotEmpty) ...[
              SectionHeader(
                'Steps · $doneSteps/${task.steps.length}',
                padding: const EdgeInsets.only(top: 20, bottom: 4),
              ),
              for (final step in task.steps)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
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
