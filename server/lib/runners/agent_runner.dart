import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import '../process_utils.dart';
import 'claude_code_runner.dart';
import 'codex_runner.dart';
import 'text_runner.dart';

/// Something an agent CLI reported during a turn.
sealed class RunnerEvent {
  const RunnerEvent();
}

/// The CLI's conversation id, used to resume the conversation next turn.
final class SessionEvent extends RunnerEvent {
  const SessionEvent(this.sessionId);

  final String sessionId;
}

/// A short description of what the agent is doing right now.
final class ActivityEvent extends RunnerEvent {
  const ActivityEvent(this.activity);

  final String activity;
}

/// Text the agent wrote to the user.
final class ReplyEvent extends RunnerEvent {
  const ReplyEvent(this.text);

  final String text;
}

/// The agent's current plan, e.g. from Claude Code's to-do tool.
final class StepsEvent extends RunnerEvent {
  const StepsEvent(this.steps);

  final List<TaskStep> steps;
}

/// Always the last event of a turn.
final class FinishedEvent extends RunnerEvent {
  const FinishedEvent({required this.success, this.error});

  final bool success;
  final String? error;
}

/// One turn in progress. [events] always ends with a [FinishedEvent].
class AgentTurn {
  AgentTurn(this.events, this._cancel);

  final Stream<RunnerEvent> events;
  final Future<void> Function() _cancel;

  Future<void> cancel() => _cancel();
}

/// Runs one agent CLI headlessly, one process per turn.
abstract interface class AgentRunner {
  factory AgentRunner.forConfig(AgentConfig config) => switch (config.type) {
    AgentType.claudeCode => ClaudeCodeRunner(config),
    AgentType.codex => CodexRunner(config),
    AgentType.geminiCli => TextRunner.gemini(config),
    AgentType.aider => TextRunner.aider(config),
  };

  AgentTurn start({
    required String prompt,
    required String workingDir,
    String? sessionId,
  });
}

/// Starts [executable] for each turn, passes the prompt on stdin (or in a
/// temp file when [promptViaFile]) and turns its stdout lines into events.
abstract class CliRunner implements AgentRunner {
  CliRunner({required this.executable, this.extraArgs = const []});

  final String executable;
  final List<String> extraArgs;

  bool get promptViaFile => false;

  /// The full argument list for one turn, with [extraArgs] placed where the
  /// CLI accepts options.
  List<String> argsFor({String? sessionId, String? promptFile});

  Iterable<RunnerEvent> parseLine(String line);

  /// Called once the process exits, unless [parseLine] already finished the
  /// turn.
  Iterable<RunnerEvent> finish(int exitCode, String stderrTail) => [
    FinishedEvent(
      success: exitCode == 0,
      error: exitCode == 0 ? null : describeExit(exitCode, stderrTail),
    ),
  ];

  String describeExit(int exitCode, String stderrTail) {
    final detail = stderrTail.trim();
    return detail.isEmpty
        ? '${p.basename(executable)} exited with code $exitCode'
        : detail;
  }

  @override
  AgentTurn start({
    required String prompt,
    required String workingDir,
    String? sessionId,
  }) {
    final controller = StreamController<RunnerEvent>();
    Process? process;
    var cancelled = false;
    var finished = false;

    void emit(RunnerEvent event) {
      if (finished) return;
      controller.add(event);
      if (event is FinishedEvent) {
        finished = true;
        controller.close();
      }
    }

    Future<void> run() async {
      File? promptFile;
      try {
        if (promptViaFile) {
          final dir = await Directory.systemTemp.createTemp('agent_prompt');
          promptFile = File(p.join(dir.path, 'prompt.md'))
            ..writeAsStringSync(prompt);
        }
        final launch = await resolveLaunch(executable);
        if (launch == null) {
          emit(
            FinishedEvent(success: false, error: notFoundMessage(executable)),
          );
          return;
        }
        final started = await Process.start(
          launch.executable,
          argsFor(sessionId: sessionId, promptFile: promptFile?.path),
          workingDirectory: workingDir,
          runInShell: launch.runInShell,
        );
        process = started;
        if (cancelled) await killTree(started);
        if (!promptViaFile) started.stdin.add(utf8.encode(prompt));
        await started.stdin.close();

        final stderrTail = <String>[];
        final decoder = const Utf8Decoder(allowMalformed: true);
        final stderrDone = started.stderr
            .transform(decoder)
            .transform(const LineSplitter())
            .forEach((line) {
              stderrTail.add(line);
              if (stderrTail.length > 20) stderrTail.removeAt(0);
            });
        // The turn ends when the process exits, even if the CLI reported its
        // result earlier, so two turns never overlap in one folder.
        FinishedEvent? reported;
        await for (final line
            in started.stdout
                .transform(decoder)
                .transform(const LineSplitter())) {
          for (final event in parseLine(line)) {
            if (event is FinishedEvent) {
              reported ??= event;
            } else {
              emit(event);
            }
          }
        }
        final code = await started.exitCode;
        await stderrDone;
        if (cancelled) {
          emit(const FinishedEvent(success: false, error: 'Stopped'));
        } else if (reported != null) {
          emit(reported);
        } else {
          finish(code, stderrTail.join('\n')).forEach(emit);
        }
      } catch (e) {
        emit(
          FinishedEvent(success: false, error: 'Could not run $executable: $e'),
        );
      } finally {
        try {
          await promptFile?.parent.delete(recursive: true);
        } on FileSystemException {
          // Best effort: the OS cleans the temp folder eventually.
        }
        emit(const FinishedEvent(success: false, error: 'Ended unexpectedly'));
      }
    }

    run();
    return AgentTurn(controller.stream, () async {
      cancelled = true;
      if (process case final running?) await killTree(running);
    });
  }
}

String truncate(String text, int max) {
  final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return oneLine.length <= max ? oneLine : '${oneLine.substring(0, max - 1)}…';
}

Json? decodeJsonLine(String line) {
  if (!line.startsWith('{')) return null;
  try {
    return jsonDecode(line) as Json;
  } on FormatException {
    return null;
  }
}
