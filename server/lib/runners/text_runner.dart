import '../config.dart';
import 'agent_runner.dart';

/// Runs a CLI that answers in plain text: each output line becomes the
/// current activity and the whole output becomes the reply.
///
/// These CLIs don't expose a resumable session id here, so every turn starts
/// a fresh conversation.
class TextRunner extends CliRunner {
  TextRunner._({
    required super.executable,
    required super.extraArgs,
    required this.buildArgs,
    this.promptViaFile = false,
  });

  /// Gemini CLI reads the prompt from stdin in non-interactive mode.
  factory TextRunner.gemini(AgentConfig config) => TextRunner._(
    executable: config.executable ?? 'gemini',
    extraArgs: config.extraArgs,
    buildArgs: (_, extra) => extra,
  );

  /// Aider takes the prompt as a file and exits after answering.
  factory TextRunner.aider(AgentConfig config) => TextRunner._(
    executable: config.executable ?? 'aider',
    extraArgs: config.extraArgs,
    promptViaFile: true,
    buildArgs: (file, extra) => [
      '--message-file',
      file!,
      '--no-pretty',
      '--no-stream',
      ...extra,
    ],
  );

  final List<String> Function(String? promptFile, List<String> extra) buildArgs;

  @override
  final bool promptViaFile;

  final _output = <String>[];

  static const _maxReply = 8000;

  @override
  List<String> argsFor({String? sessionId, String? promptFile}) {
    _output.clear();
    return buildArgs(promptFile, extraArgs);
  }

  @override
  Iterable<RunnerEvent> parseLine(String line) sync* {
    _output.add(line);
    if (line.trim().isNotEmpty) yield ActivityEvent(truncate(line, 80));
  }

  @override
  Iterable<RunnerEvent> finish(int exitCode, String stderrTail) sync* {
    var reply = _output.join('\n').trim();
    if (reply.length > _maxReply) {
      reply = '…${reply.substring(reply.length - _maxReply)}';
    }
    if (reply.isNotEmpty) yield ReplyEvent(reply);
    yield* super.finish(exitCode, stderrTail);
  }
}
