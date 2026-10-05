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

/// One step on the agent's way to its reply: its reasoning, a remark it made
/// between tool calls, or a tool it used. Gathered into a thinking message.
final class ThinkingEvent extends RunnerEvent {
  const ThinkingEvent(this.text);

  final String text;
}

/// The agent asked the owner [questions] and waits until the turn gets a
/// [QuestionAnswer] with the same [id].
final class QuestionEvent extends RunnerEvent {
  const QuestionEvent(this.id, this.questions);

  final String id;
  final List<AgentQuestion> questions;
}

/// Something about the turn itself worth a line in the chat, such as a
/// finished `/compact`.
final class NoticeEvent extends RunnerEvent {
  const NoticeEvent(this.text);

  final String text;
}

/// The agent's current plan, e.g. from Claude Code's to-do tool.
final class StepsEvent extends RunnerEvent {
  const StepsEvent(this.steps);

  final List<TaskStep> steps;
}

/// The full id of the model the CLI runs on, e.g. `claude-opus-5-5`.
final class ModelEvent extends RunnerEvent {
  const ModelEvent(this.model);

  final String model;
}

/// How much of the account's usage limits is used.
final class UsageEvent extends RunnerEvent {
  const UsageEvent(this.usage);

  final UsageLimits usage;
}

/// How full the conversation is: [usedTokens] when the CLI sent the model a
/// request, [maxTokens] once it reports the model's context window.
final class ContextEvent extends RunnerEvent {
  const ContextEvent({this.usedTokens, this.maxTokens});

  final int? usedTokens;
  final int? maxTokens;
}

/// The slash commands the CLI accepts in this turn's folder.
final class CommandsEvent extends RunnerEvent {
  const CommandsEvent(this.names);

  final List<String> names;
}

/// Always the last event of a turn.
final class FinishedEvent extends RunnerEvent {
  const FinishedEvent({required this.success, this.error});

  final bool success;
  final String? error;
}

/// A setting to change while a turn runs.
sealed class TurnChange {
  const TurnChange();
}

final class ModelChange extends TurnChange {
  const ModelChange(this.model);

  /// Null switches back to the CLI's default.
  final String? model;
}

final class EffortChange extends TurnChange {
  const EffortChange(this.effort);

  final EffortLevel? effort;
}

/// The owner's answers to the [QuestionEvent] [id], keyed by question, or a
/// [response] in their own words instead.
final class QuestionAnswer extends TurnChange {
  const QuestionAnswer(this.id, {this.answers = const {}, this.response});

  final String id;
  final Map<String, String> answers;
  final String? response;
}

/// One turn in progress. [events] always ends with a [FinishedEvent].
class AgentTurn {
  AgentTurn(this.events, this._cancel, {this._apply});

  final Stream<RunnerEvent> events;
  final Future<void> Function() _cancel;
  final bool Function(TurnChange)? _apply;

  Future<void> cancel() => _cancel();

  /// Hands [change] to the running CLI. Returns false when the CLI can't take
  /// it mid-turn, in which case it applies from the next turn.
  bool apply(TurnChange change) => _apply?.call(change) ?? false;
}

/// The models and slash commands a CLI offers.
typedef RunnerOptions = ({
  List<ModelOption> models,
  List<SlashCommand> commands,
});

/// Runs one agent CLI headlessly, one process per turn.
abstract interface class AgentRunner {
  factory AgentRunner.forConfig(AgentConfig config) => switch (config.type) {
    AgentType.claudeCode => ClaudeCodeRunner(config),
    AgentType.codex => CodexRunner(config),
    AgentType.geminiCli => TextRunner.gemini(config),
    AgentType.aider => TextRunner.aider(config),
  };

  /// The [prompt] already tells the agent where its [attachments] are; a CLI
  /// that can take images directly also gets those.
  AgentTurn start({
    required String prompt,
    required String workingDir,
    String? sessionId,
    String? model,
    EffortLevel? effort,
    List<Attachment> attachments = const [],
  });

  /// Asks the CLI which models and commands it offers in [workingDir].
  Future<RunnerOptions> discover(String workingDir);
}

/// Starts [executable] for each turn, passes the prompt on stdin (or in a
/// temp file when [promptViaFile]) and turns its stdout lines into events.
///
/// A CLI that [keepsInputOpen] reads more input while it works, such as
/// [TurnChange]s, and is told the turn is over by closing its stdin once it
/// reported its result.
abstract class CliRunner implements AgentRunner {
  CliRunner({
    required this.executable,
    this.extraArgs = const [],
    this.models = const [],
  });

  final String executable;
  final List<String> extraArgs;

  /// The models listed for this agent in the config.
  final List<String> models;

  bool get promptViaFile => false;

  bool get keepsInputOpen => false;

  /// The full argument list for one turn, with [extraArgs] placed where the
  /// CLI accepts options.
  List<String> argsFor({
    String? sessionId,
    String? promptFile,
    String? model,
    EffortLevel? effort,
  });

  /// What goes on stdin to start the turn.
  List<int> encodePrompt(
    String prompt, {
    List<Attachment> attachments = const [],
  }) => utf8.encode(prompt);

  /// The stdin line that applies [change] mid-turn, or null when the CLI
  /// can't.
  String? encodeChange(TurnChange change) => null;

  /// A stdin line that answers [line] straight away, for requests from the
  /// CLI that need no one's input.
  String? replyTo(String line) => null;

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
  Future<RunnerOptions> discover(String workingDir) async => (
    models: [
      for (final m in models)
        ModelOption(value: m, label: modelDisplayName(m) ?? m),
    ],
    commands: BuiltinCommands.fallback(models: models.isNotEmpty),
  );

  @override
  AgentTurn start({
    required String prompt,
    required String workingDir,
    String? sessionId,
    String? model,
    EffortLevel? effort,
    List<Attachment> attachments = const [],
  }) {
    final controller = StreamController<RunnerEvent>();
    Process? process;
    var cancelled = false;
    var finished = false;
    var inputOpen = false;

    void emit(RunnerEvent event) {
      if (finished) return;
      controller.add(event);
      if (event is FinishedEvent) {
        finished = true;
        controller.close();
      }
    }

    void closeInput() {
      if (!inputOpen) return;
      inputOpen = false;
      process?.stdin.close().ignore();
    }

    bool apply(TurnChange change) {
      final line = encodeChange(change);
      final running = process;
      if (line == null || running == null || !inputOpen) return false;
      running.stdin.writeln(line);
      return true;
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
          argsFor(
            sessionId: sessionId,
            promptFile: promptFile?.path,
            model: model,
            effort: effort,
          ),
          workingDirectory: workingDir,
          runInShell: launch.runInShell,
        );
        process = started;
        // Writing to a CLI that already exited must not crash the server.
        started.stdin.done.ignore();
        if (cancelled) await killTree(started);
        if (!promptViaFile) {
          started.stdin.add(encodePrompt(prompt, attachments: attachments));
        }
        if (keepsInputOpen) {
          inputOpen = true;
        } else {
          await started.stdin.close();
        }

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
          if (replyTo(line) case final reply? when inputOpen) {
            started.stdin.writeln(reply);
          }
          for (final event in parseLine(line)) {
            if (event is FinishedEvent) {
              reported ??= event;
              closeInput();
            } else {
              emit(event);
            }
          }
        }
        closeInput();
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
        inputOpen = false;
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
      inputOpen = false;
      if (process case final running?) await killTree(running);
    }, apply: apply);
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
