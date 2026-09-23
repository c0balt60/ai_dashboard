import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/backend_providers.dart';

/// Runs a shell command in a project folder on the PC and shows its output.
Future<void> showRunCommandSheet(BuildContext context, String projectId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RunCommandSheet(projectId),
  );
}

const _quickCommands = [
  'git status',
  'git log',
  'git branch',
  'flutter test',
  'npm test',
];

typedef _Run = ({String command, String output, bool failed});

class _RunCommandSheet extends ConsumerStatefulWidget {
  const _RunCommandSheet(this.projectId);

  final String projectId;

  @override
  ConsumerState<_RunCommandSheet> createState() => _RunCommandSheetState();
}

class _RunCommandSheetState extends ConsumerState<_RunCommandSheet> {
  final _controller = TextEditingController();
  final _outputScroll = ScrollController();
  final _runs = <_Run>[];
  bool _running = false;

  @override
  void dispose() {
    _controller.dispose();
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

    // Wait for the new output to be laid out before scrolling to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_outputScroll.hasClients) return;
      _outputScroll.animateTo(
        _outputScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = ref.watch(projectProvider(widget.projectId));
    const mono = TextStyle(fontFamily: 'monospace');

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Run command', style: theme.textTheme.titleLarge),
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
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final command in _quickCommands)
                  ActionChip(
                    avatar: const Icon(Icons.bolt, size: 16),
                    label: Text(command, style: mono),
                    onPressed: _running ? null : () => _run(command),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, value, _) => FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _running || value.text.trim().isEmpty ? null : _run,
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
        borderRadius: BorderRadius.circular(12),
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
