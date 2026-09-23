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

/// "My lists" view of the Tasks tab: the user's own to-do lists with their
/// progress, timeline and what is due next. It does not scroll by itself; the
/// tab's page scrolls it.
class TodoListsView extends ConsumerWidget {
  const TodoListsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView(
      ref.watch(todoListsProvider),
      data: (lists) {
        if (lists.isEmpty) {
          return const EmptyState(
            icon: Icons.checklist,
            message:
                'No lists yet.\nCreate one to keep track of what you and '
                'your agents should work on.',
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ResponsiveGrid(
            children: [for (final list in lists) _TodoListCard(list)],
          ),
        );
      },
    );
  }
}

class _TodoListCard extends StatelessWidget {
  const _TodoListCard(this.list);

  final TodoList list;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final now = DateTime.now();
    final total = list.items.length;
    final done = list.doneCount;
    final overdue = list.items.where((i) => i.isOverdue(now)).length;
    final range = dateRange(list.timelineStart, list.timelineEnd);
    final next =
        (list.items.where((i) => !i.done && i.dueDate != null).toList()
              ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!)))
            .firstOrNull;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card(
      child: InkWell(
        onTap: () => context.push(AppRoutes.todoList(list.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.checklist, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      list.title,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$done/$total', style: theme.textTheme.labelLarge),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  minHeight: 6,
                  color: colors.completed,
                ),
              ),
              if (next != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Next: ${next.title} · ${dueLabel(next.dueDate!)}',
                  style: muted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (range != null || overdue > 0) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (range != null) InfoChip(range, icon: Icons.date_range),
                    if (overdue > 0)
                      InfoChip(
                        '$overdue overdue',
                        icon: Icons.event_busy,
                        color: colors.failed,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
