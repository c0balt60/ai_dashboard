import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import '../../utils/time_format.dart';
import '../common.dart';
import '../status/status_visuals.dart';

/// Adds an item to [listId], or edits the item with [itemId]: title, notes,
/// tagged projects and agents, and an optional start and due date. The item
/// can also be handed off as a prefilled agent task.
Future<void> showTodoItemSheet(
  BuildContext context, {
  required String listId,
  String? itemId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (context) => _TodoItemSheet(listId: listId, itemId: itemId),
  );
}

class _TodoItemSheet extends ConsumerStatefulWidget {
  const _TodoItemSheet({required this.listId, this.itemId});

  final String listId;
  final String? itemId;

  @override
  ConsumerState<_TodoItemSheet> createState() => _TodoItemSheetState();
}

class _TodoItemSheetState extends ConsumerState<_TodoItemSheet> {
  late final TodoItem? _existing = widget.itemId == null
      ? null
      : ref
            .read(todoListProvider(widget.listId))
            ?.items
            .where((i) => i.id == widget.itemId)
            .firstOrNull;
  late final _title = TextEditingController(text: _existing?.title);
  late final _note = TextEditingController(text: _existing?.note);
  late final _projectIds = <String>{...?_existing?.projectIds};
  late final _agentIds = <String>{...?_existing?.agentIds};
  late DateTime? _startDate = _existing?.startDate;
  late DateTime? _dueDate = _existing?.dueDate;
  bool _submitting = false;

  bool get _canSave => _title.text.trim().isNotEmpty && !_submitting;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<TodoItem> _persist() async {
    final backend = ref.read(backendProvider);
    final title = _title.text.trim();
    final note = _note.text.trim();
    final existing = _existing;
    if (existing == null) {
      return backend.addTodoItem(
        widget.listId,
        title: title,
        note: note,
        projectIds: [..._projectIds],
        agentIds: [..._agentIds],
        startDate: _startDate,
        dueDate: _dueDate,
      );
    }
    final updated = existing.copyWith(
      title: title,
      note: note,
      projectIds: List.unmodifiable(_projectIds),
      agentIds: List.unmodifiable(_agentIds),
      startDate: () => _startDate,
      dueDate: () => _dueDate,
    );
    await backend.updateTodoItem(widget.listId, updated);
    return updated;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final navigator = Navigator.of(context);
    setState(() => _submitting = true);
    await _persist();
    if (mounted) navigator.pop();
  }

  /// Saves the item, then opens the new-task page prefilled from it. The
  /// to-do stays open so the user can tick it off once the agent is done.
  Future<void> _sendToAgent() async {
    if (!_canSave) return;
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    setState(() => _submitting = true);
    final item = await _persist();
    if (!mounted) return;
    navigator.pop();
    await router.push(
      AppRoutes.newTask(
        title: item.title,
        projectId: item.projectIds.firstOrNull,
        agentId: item.agentIds.firstOrNull,
      ),
    );
  }

  Future<void> _delete() async {
    final existing = _existing;
    if (existing == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _submitting = true);
    await ref.read(backendProvider).deleteTodoItem(widget.listId, existing.id);
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Item deleted')));
  }

  /// Keeps the start date on or before the due date.
  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final first = (start ? null : _startDate) ?? DateTime(2000);
    final last = (start ? _dueDate : null) ?? DateTime(now.year + 10);
    var initial =
        (start ? _startDate : _dueDate) ??
        DateTime(now.year, now.month, now.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: start ? 'Start date' : 'Due date',
    );
    if (picked == null || !mounted) return;
    setState(() => start ? _startDate = picked : _dueDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemId != null && _existing == null) {
      return const SafeArea(
        top: false,
        child: EmptyState(
          icon: Icons.checklist,
          message: 'This item no longer exists.',
        ),
      );
    }

    final theme = Theme.of(context);
    final projects = ref.watch(projectsProvider).value ?? const <Project>[];
    final agents = ref.watch(agentsProvider).value ?? const <Agent>[];
    final label = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _existing == null ? 'New item' : 'Edit item',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: _existing == null,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What needs doing?',
                  hintText: 'e.g. Ship dark mode',
                  prefixIcon: Icon(Icons.edit_note),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              if (projects.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Projects', style: label),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in projects)
                      FilterChip(
                        avatar: const Icon(Icons.folder_outlined, size: 18),
                        label: Text(p.name, overflow: TextOverflow.ellipsis),
                        selected: _projectIds.contains(p.id),
                        onSelected: (on) => setState(
                          () => on
                              ? _projectIds.add(p.id)
                              : _projectIds.remove(p.id),
                        ),
                      ),
                  ],
                ),
              ],
              if (agents.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Agents', style: label),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final a in agents)
                      FilterChip(
                        avatar: Icon(a.type.icon, size: 18),
                        label: Text(a.name, overflow: TextOverflow.ellipsis),
                        selected: _agentIds.contains(a.id),
                        onSelected: (on) => setState(
                          () =>
                              on ? _agentIds.add(a.id) : _agentIds.remove(a.id),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Text('Timeline', style: label),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  InputChip(
                    avatar: const Icon(Icons.play_arrow_outlined, size: 18),
                    label: Text(
                      _startDate == null
                          ? 'Start date'
                          : 'Starts ${shortDate(_startDate!)}',
                    ),
                    onPressed: () => _pickDate(start: true),
                    onDeleted: _startDate == null
                        ? null
                        : () => setState(() => _startDate = null),
                  ),
                  InputChip(
                    avatar: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      _dueDate == null
                          ? 'Due date'
                          : 'Due ${shortDate(_dueDate!)}',
                    ),
                    onPressed: () => _pickDate(start: false),
                    onDeleted: _dueDate == null
                        ? null
                        : () => setState(() => _dueDate = null),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _canSave ? _save : null,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_existing == null ? Icons.add : Icons.check),
                label: Text(_existing == null ? 'Add' : 'Save'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _canSave ? _sendToAgent : null,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Save and send to an agent'),
              ),
              if (_existing != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _submitting ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete item'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
