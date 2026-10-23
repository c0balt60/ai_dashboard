import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../providers/backend_providers.dart';
import 'app_sheet.dart';

/// Runs a shell command in a project folder on the PC and shows its output.
/// The project's quick commands can be edited, reordered and reset here.
Future<void> showRunCommandSheet(BuildContext context, String projectId) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => _RunCommandSheet(projectId),
  );
}

typedef _Run = ({String command, String output, bool failed});

class _RunCommandSheet extends ConsumerStatefulWidget {
  const _RunCommandSheet(this.projectId);

  final String projectId;

  @override
  ConsumerState<_RunCommandSheet> createState() => _RunCommandSheetState();
}

class _RunCommandSheetState extends ConsumerState<_RunCommandSheet> {
  final _controller = TextEditingController();
  final _sheetScroll = ScrollController();
  final _outputScroll = ScrollController();
  final _runs = <_Run>[];
  bool _running = false;
  bool _editing = false;

  /// The owner's last edit to the quick commands, shown straight away rather
  /// than after the PC sends the project back.
  List<String>? _commands;
  String? _saveError;

  @override
  void dispose() {
    _controller.dispose();
    _sheetScroll.dispose();
    _outputScroll.dispose();
    super.dispose();
  }

  Future<void> _run([String? preset]) async {
    if (_running) return;
    if (preset != null) _controller.text = preset;
    final command = _controller.text.trim();
    if (command.isEmpty) return;

    setState(() => _running = true);
    final backend = ref.read(backendProvider);
    String output;
    var failed = false;
    try {
      output = await backend.runCommand(widget.projectId, command);
    } catch (e) {
      output = 'error: $e';
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _runs.add((command: command, output: output.trimRight(), failed: failed));
      _running = false;
    });

    // Wait for the new output to be laid out before scrolling to it. The
    // sheet scrolls too, since on short screens the bottom of the output box
    // would otherwise sit under the system navigation bar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final scroll in [_sheetScroll, _outputScroll]) {
        if (!scroll.hasClients) continue;
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _saveCommands(List<String> commands) async {
    final cleaned = Project.cleanCommands(commands);
    setState(() {
      _commands = cleaned;
      _saveError = null;
    });
    try {
      await ref
          .read(backendProvider)
          .setQuickCommands(widget.projectId, cleaned);
    } catch (e) {
      // The app's snackbar would sit hidden under this sheet.
      if (!mounted) rethrow;
      setState(() {
        _commands = null;
        _saveError = "Couldn't save quick commands: $e";
      });
    }
  }

  /// Edits the command at [index], or adds one without it.
  Future<void> _editCommand(List<String> commands, [int? index]) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _CommandDialog(index == null ? '' : commands[index]),
    );
    if (text == null || text.trim().isEmpty) return;
    final updated = [...commands];
    if (index == null) {
      updated.add(text);
    } else {
      updated[index] = text;
    }
    await _saveCommands(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final project = ref.watch(projectProvider(widget.projectId));
    final commands = _commands ?? project?.quickCommands ?? const <String>[];
    const mono = TextStyle(fontFamily: 'monospace');
    // The theme paints unselected chips in the card color, which is also the
    // sheet color, so these chips need their own fill to stay visible.
    final chipColor = WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? scheme.onSurface.withValues(alpha: 0.06)
          : scheme.surfaceContainerHigh,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          controller: _sheetScroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHeader('Run command'),
              if (project != null)
                Text(
                  project.path,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.go,
                style: mono,
                decoration: const InputDecoration(
                  prefixText: '\$ ',
                  prefixStyle: mono,
                  hintText: 'git status',
                ),
                onSubmitted: (_) => _run(),
              ),
              const SizedBox(height: 12),
              if (_editing) ...[
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: (from, to) => _saveCommands(
                    [...commands]
                      ..removeAt(from)
                      ..insert(to, commands[from]),
                  ),
                  children: [
                    for (final (i, command) in commands.indexed)
                      ListTile(
                        key: ValueKey(command),
                        contentPadding: EdgeInsets.zero,
                        leading: ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                        title: Text(
                          command,
                          style: mono,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _editCommand(commands, i),
                        trailing: IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              _saveCommands([...commands]..removeAt(i)),
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _editCommand(commands),
                      icon: const Icon(Icons.add),
                      label: const Text('Add command'),
                    ),
                    if (!listEquals(commands, Project.defaultQuickCommands))
                      TextButton.icon(
                        onPressed: () =>
                            _saveCommands(Project.defaultQuickCommands),
                        icon: const Icon(Icons.restore),
                        label: const Text('Reset to defaults'),
                      ),
                    TextButton.icon(
                      onPressed: () => setState(() => _editing = false),
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                    ),
                  ],
                ),
              ] else
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final command in commands)
                      ActionChip(
                        color: chipColor,
                        avatar: const Icon(Icons.bolt, size: 16),
                        label: Text(command, style: mono),
                        onPressed: _running ? null : () => _run(command),
                      ),
                    ActionChip(
                      color: chipColor,
                      avatar: const Icon(Icons.edit_outlined, size: 16),
                      label: Text(
                        commands.isEmpty ? 'Add quick commands' : 'Edit',
                      ),
                      tooltip: 'Edit quick commands',
                      onPressed: project == null
                          ? null
                          : () => setState(() => _editing = true),
                    ),
                  ],
                ),
              if (_saveError case final error?) ...[
                const SizedBox(height: 8),
                Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ValueListenableBuilder(
                valueListenable: _controller,
                builder: (context, value, _) => FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _running || value.text.trim().isEmpty
                      ? null
                      : _run,
                  icon: _running
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_running ? 'Running…' : 'Run'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Output', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  TextButton(
                    onPressed: _runs.isEmpty || _running
                        ? null
                        : () => setState(_runs.clear),
                    child: const Text('Clear'),
                  ),
                ],
              ),
              _OutputBox(runs: _runs, controller: _outputScroll),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandDialog extends StatefulWidget {
  const _CommandDialog(this.initial);

  final String initial;

  @override
  State<_CommandDialog> createState() => _CommandDialogState();
}

class _CommandDialogState extends State<_CommandDialog> {
  late final _command = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'monospace');
    return AlertDialog(
      title: Text(widget.initial.isEmpty ? 'Add command' : 'Edit command'),
      content: TextField(
        controller: _command,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        style: mono,
        decoration: const InputDecoration(
          prefixText: '\$ ',
          prefixStyle: mono,
          hintText: 'git status',
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _command.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _OutputBox extends StatelessWidget {
  const _OutputBox({required this.runs, required this.controller});

  final List<_Run> runs;
  final ScrollController controller;

  static const _background = Color(0xFF1E1F22);
  static const _text = Color(0xFFD4D4D4);
  static const _dim = Color(0xFF8B8F97);
  static const _prompt = Color(0xFF6DD58C);
  static const _error = Color(0xFFFF8A80);

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.4,
      color: _text,
    );

    return Container(
      constraints: BoxConstraints(
        minHeight: 140,
        maxHeight: MediaQuery.sizeOf(context).height * 0.4,
      ),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Scrollbar(
        controller: controller,
        child: SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: runs.isEmpty
                ? Text(
                    'Output will appear here.',
                    style: style.copyWith(color: _dim),
                  )
                : SelectableText.rich(
                    TextSpan(
                      style: style,
                      children: [
                        for (final (i, run) in runs.indexed) ...[
                          if (i > 0) const TextSpan(text: '\n\n'),
                          TextSpan(
                            text: '\$ ${run.command}\n',
                            style: const TextStyle(
                              color: _prompt,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text: run.output.isEmpty
                                ? '(no output)'
                                : run.output,
                            style: run.failed
                                ? const TextStyle(color: _error)
                                : run.output.isEmpty
                                ? const TextStyle(color: _dim)
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
