import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/backend_providers.dart';

/// Creates a to-do list, or renames the one with [listId]. Resolves to the
/// id of the new list, or null when renaming or dismissed.
Future<String?> showTodoListSheet(BuildContext context, {String? listId}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (context) => _TodoListSheet(listId: listId),
  );
}

class _TodoListSheet extends ConsumerStatefulWidget {
  const _TodoListSheet({this.listId});

  final String? listId;

  @override
  ConsumerState<_TodoListSheet> createState() => _TodoListSheetState();
}

class _TodoListSheetState extends ConsumerState<_TodoListSheet> {
  late final _title = TextEditingController(
    text: widget.listId == null
        ? null
        : ref.read(todoListProvider(widget.listId!))?.title,
  );
  bool _submitting = false;

  bool get _isRename => widget.listId != null;

  bool get _canSave => _title.text.trim().isNotEmpty && !_submitting;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final navigator = Navigator.of(context);
    final backend = ref.read(backendProvider);
    final title = _title.text.trim();
    setState(() => _submitting = true);
    if (_isRename) {
      await backend.renameTodoList(widget.listId!, title);
      if (mounted) navigator.pop();
    } else {
      final list = await backend.createTodoList(title);
      if (mounted) navigator.pop(list.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                _isRename ? 'Rename list' : 'New list',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'List name',
                  hintText: 'e.g. v1.2 release',
                  prefixIcon: Icon(Icons.checklist),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
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
                    : Icon(_isRename ? Icons.check : Icons.add),
                label: Text(_isRename ? 'Save' : 'Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
