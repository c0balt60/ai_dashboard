import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../../utils/time_format.dart';
import '../../widgets/common.dart';
import '../../widgets/glow.dart';
import '../../widgets/layout.dart';
import '../../widgets/sheets/todo_item_sheet.dart';
import '../../widgets/sheets/todo_list_sheet.dart';
import '../../widgets/status/status_visuals.dart';

/// Full-screen view of one of the user's to-do lists: open items soonest due
/// first, with finished ones in a collapsible "Done" section.
class TodoListScreen extends ConsumerWidget {
  const TodoListScreen({super.key, required this.listId});

  final String listId;

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _ListAction action,
    TodoList list,
  ) async {
    final backend = ref.read(backendProvider);
    switch (action) {
      case _ListAction.rename:
        await showTodoListSheet(context, listId: list.id);
      case _ListAction.clearDone:
        for (final item in list.items.where((i) => i.done)) {
          await backend.deleteTodoItem(list.id, item.id);
        }
      case _ListAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete "${list.title}"?'),
            content: Text(
              'Its ${list.items.length} item(s) are deleted too. Agent tasks '
              'you created from them are kept.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        context.pop();
        await backend.deleteTodoList(list.id);
        messenger.showSnackBar(
          SnackBar(content: Text('Deleted "${list.title}"')),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(todoListProvider(listId));
    if (list == null) {
      return AppBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: const Text('List')),
          body: AsyncValueView(
            ref.watch(todoListsProvider),
            data: (_) => const ContentWidth(
              child: EmptyState(
                icon: Icons.checklist,
                message: 'This list no longer exists.',
              ),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final (:open, :done) = ref.watch(todoItemsProvider(listId));
    final range = dateRange(list.timelineStart, list.timelineEnd);
    final total = list.items.length;

    return AppBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(list.title, overflow: TextOverflow.ellipsis),
          actions: [
            PopupMenuButton<_ListAction>(
              tooltip: 'More',
              onSelected: (action) => _onAction(context, ref, action, list),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _ListAction.rename,
                  child: _MenuRow(Icons.edit_outlined, 'Rename list'),
                ),
                if (done.isNotEmpty)
                  const PopupMenuItem(
                    value: _ListAction.clearDone,
                    child: _MenuRow(Icons.playlist_remove, 'Clear done items'),
                  ),
                const PopupMenuItem(
                  value: _ListAction.delete,
                  child: _MenuRow(Icons.delete_outline, 'Delete list'),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButton: FloatingGlow(
          child: FloatingActionButton.extended(
            onPressed: () => showTodoItemSheet(context, listId: listId),
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ),
        body: SafeArea(
          top: false,
          child: total == 0
              ? ListView(
                  children: const [
                    ContentWidth(
                      child: EmptyState(
                        icon: Icons.playlist_add,
                        message:
                            'Nothing here yet.\nAdd items and tag the projects and '
                            'agents they belong to.',
                      ),
                    ),
                  ],
                )
              // The gutter centers the content but the whole width still
              // scrolls with a mouse wheel.
              : LayoutBuilder(
                  builder: (context, constraints) => CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: pageGutter(constraints.maxWidth),
                        ),
                        sliver: SliverMainAxisGroup(
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              sliver: SliverToBoxAdapter(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: done.length / total,
                                          minHeight: 8,
                                          color: StatusColors.of(context)
                                              .completed,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '${done.length}/$total done',
                                      style: theme.textTheme.labelLarge,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (range != null)
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  10,
                                  16,
                                  0,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: InfoChip(
                                      range,
                                      icon: Icons.date_range,
                                    ),
                                  ),
                                ),
                              ),
                            SliverToBoxAdapter(
                              child: SectionHeader('To do', count: open.length),
                            ),
                            if (open.isEmpty)
                              SliverPadding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: Text(
                                    'All done. Nice work!',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                sliver: SliverList.separated(
                                  itemCount: open.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, i) => _TodoItemTile(
                                    listId: listId,
                                    item: open[i],
                                  ),
                                ),
                              ),
                            if (done.isNotEmpty)
                              SliverPadding(
                                padding: const EdgeInsets.only(top: 12),
                                sliver: SliverToBoxAdapter(
                                  child: ExpansionTile(
                                    key: PageStorageKey('todo-done-$listId'),
                                    shape: const Border(),
                                    collapsedShape: const Border(),
                                    tilePadding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      12,
                                      0,
                                    ),
                                    childrenPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    title: SectionHeader(
                                      'Done',
                                      count: done.length,
                                      padding: EdgeInsets.zero,
                                    ),
                                    children: [
                                      for (final item in done)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: _TodoItemTile(
                                            listId: listId,
                                            item: item,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            // Keeps the last card clear of the extended FAB.
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 96),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

enum _ListAction { rename, clearDone, delete }

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    );
  }
}

/// A to-do with a checkbox, notes, dates and its project and agent tags.
class _TodoItemTile extends ConsumerWidget {
  const _TodoItemTile({required this.listId, required this.item});

  final String listId;
  final TodoItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final projects = [
      for (final id in item.projectIds) ?ref.watch(projectProvider(id)),
    ];
    final agents = [
      for (final id in item.agentIds) ?ref.watch(agentProvider(id)),
    ];
    final task = ref.watch(taskForTodoProvider(item.id));
    final taskAgent = task?.agentId == null
        ? null
        : ref.watch(agentProvider(task!.agentId!));
    final taskVisual = task?.state.visual(context);
    final due = item.dueVisual(context);
    final range = item.startDate == null
        ? null
        : dateRange(item.startDate, item.dueDate);
    final chips = [
      if (task != null && taskVisual != null)
        InfoChip(
          [?taskAgent?.name, taskVisual.label].join(' · '),
          icon: taskVisual.icon,
          color: taskVisual.color,
        ),
      if (due != null) InfoChip(due.label, icon: due.icon, color: due.color),
      if (range != null) InfoChip(range, icon: Icons.date_range),
      if (item.done && item.completedAt != null)
        InfoChip(
          'Done ${timeAgo(item.completedAt!)}',
          icon: Icons.check,
          color: StatusColors.of(context).completed,
        ),
      for (final p in projects) InfoChip(p.name, icon: Icons.folder_outlined),
      for (final a in agents) InfoChip(a.name, icon: a.type.icon),
    ];

    return Card(
      child: InkWell(
        onTap: () =>
            showTodoItemSheet(context, listId: listId, itemId: item.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: item.done,
                onChanged: (value) => ref
                    .read(backendProvider)
                    .updateTodoItem(listId, item.copyWith(done: value)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: item.done ? muted : null,
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (item.note.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.note,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: chips),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
