import 'package:agent_core/agent_core.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import 'agent_runner.dart';

/// Drives Claude Code in print mode:
/// `claude -p --output-format stream-json --verbose [--resume <id>]`, with the
/// prompt on stdin.
///
/// Headless Claude Code can only use tools it's allowed to, so give it
/// permissions through the agent's `extraArgs`, e.g.
/// `["--permission-mode", "acceptEdits", "--allowedTools", "Bash(git:*)"]`.
class ClaudeCodeRunner extends CliRunner {
  ClaudeCodeRunner(AgentConfig config)
    : super(
        executable: config.executable ?? 'claude',
        extraArgs: config.extraArgs,
      );

  @override
  List<String> argsFor({String? sessionId, String? promptFile}) => [
    '-p',
    '--output-format',
    'stream-json',
    '--verbose',
    if (sessionId != null) ...['--resume', sessionId],
    ...extraArgs,
  ];

  @override
  Iterable<RunnerEvent> parseLine(String line) => parseClaudeEvent(line);
}

Iterable<RunnerEvent> parseClaudeEvent(String line) sync* {
  final json = decodeJsonLine(line);
  if (json == null) return;
  final session = json['session_id'] as String?;

  switch (json['type']) {
    case 'system' when json['subtype'] == 'init':
      if (session != null) yield SessionEvent(session);
      yield const ActivityEvent('Starting up');
    case 'assistant':
      final message = json['message'] as Json? ?? const {};
      for (final block in message['content'] as List? ?? const []) {
        final b = block as Json;
        switch (b['type']) {
          case 'text':
            final text = (b['text'] as String? ?? '').trim();
            if (text.isNotEmpty) yield ReplyEvent(text);
          case 'tool_use':
            final name = b['name'] as String? ?? 'a tool';
            final input = b['input'] as Json? ?? const {};
            if (name == 'TodoWrite') {
              final todos = [
                for (final t in input['todos'] as List? ?? const []) t as Json,
              ];
              yield StepsEvent([
                for (final t in todos)
                  TaskStep(
                    t['content'] as String? ?? '',
                    done: t['status'] == 'completed',
                  ),
              ]);
              final current = todos
                  .where((t) => t['status'] == 'in_progress')
                  .firstOrNull;
              yield ActivityEvent(
                current?['activeForm'] as String? ??
                    current?['content'] as String? ??
                    'Planning',
              );
            } else {
              yield ActivityEvent(describeClaudeTool(name, input));
            }
        }
      }
    case 'result':
      if (session != null) yield SessionEvent(session);
      final ok = json['subtype'] == 'success' && json['is_error'] != true;
      yield FinishedEvent(
        success: ok,
        error: ok
            ? null
            : json['result'] as String? ??
                  'Claude Code stopped: ${json['subtype']}',
      );
  }
}

String describeClaudeTool(String name, Json input) {
  String file() => p.basename(input['file_path'] as String? ?? 'a file');
  return switch (name) {
    'Edit' || 'MultiEdit' || 'Write' || 'NotebookEdit' => 'Editing ${file()}',
    'Read' => 'Reading ${file()}',
    'Bash' => 'Running: ${truncate(input['command'] as String? ?? '', 60)}',
    'Grep' || 'Glob' => 'Searching the code',
    'WebFetch' || 'WebSearch' => 'Searching the web',
    'Task' || 'Agent' => 'Delegating to a subagent',
    _ => 'Using $name',
  };
}
