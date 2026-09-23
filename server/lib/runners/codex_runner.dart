import 'package:agent_core/agent_core.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import 'agent_runner.dart';

/// Drives OpenAI Codex CLI non-interactively:
/// `codex exec --json [...] -` for a new conversation and
/// `codex exec --json [...] resume <id> -` to continue one, with the prompt
/// on stdin.
///
/// Codex runs sandboxed by default; widen that through the agent's
/// `extraArgs`, e.g. `["--full-auto"]`. The JSON event names follow
/// `codex exec --json`; check them against your installed version.
class CodexRunner extends CliRunner {
  CodexRunner(AgentConfig config)
    : super(
        executable: config.executable ?? 'codex',
        extraArgs: config.extraArgs,
      );

  String? _lastError;

  @override
  List<String> argsFor({String? sessionId, String? promptFile}) {
    _lastError = null;
    return [
      'exec',
      '--json',
      '--skip-git-repo-check',
      ...extraArgs,
      if (sessionId != null) ...['resume', sessionId],
      '-',
    ];
  }

  @override
  Iterable<RunnerEvent> parseLine(String line) sync* {
    final json = decodeJsonLine(line);
    if (json == null) return;
    final item = json['item'] as Json? ?? const {};

    switch (json['type']) {
      case 'thread.started':
        if (json['thread_id'] case final String id) yield SessionEvent(id);
      case 'item.started' || 'item.updated' || 'item.completed':
        final done = json['type'] == 'item.completed';
        switch (item['type']) {
          case 'agent_message' when done:
            final text = (item['text'] as String? ?? '').trim();
            if (text.isNotEmpty) yield ReplyEvent(text);
          case 'reasoning':
            yield const ActivityEvent('Thinking');
          case 'command_execution':
            yield ActivityEvent(
              'Running: ${truncate(item['command'] as String? ?? '', 60)}',
            );
          case 'file_change':
            final changes = item['changes'] as List? ?? const [];
            final first = changes.isEmpty ? null : changes.first as Json;
            yield ActivityEvent(
              'Editing ${p.basename(first?['path'] as String? ?? 'files')}',
            );
          case 'web_search':
            yield const ActivityEvent('Searching the web');
          case 'todo_list':
            yield StepsEvent([
              for (final t in item['items'] as List? ?? const [])
                TaskStep(
                  (t as Json)['text'] as String? ?? '',
                  done: t['completed'] == true,
                ),
            ]);
        }
      case 'turn.completed':
        yield const FinishedEvent(success: true);
      case 'turn.failed':
        final error = json['error'] as Json?;
        yield FinishedEvent(
          success: false,
          error: error?['message'] as String? ?? _lastError ?? 'Turn failed',
        );
      case 'error':
        _lastError = json['message'] as String?;
    }
  }

  @override
  String describeExit(int exitCode, String stderrTail) =>
      _lastError ?? super.describeExit(exitCode, stderrTail);
}
