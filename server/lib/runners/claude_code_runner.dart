import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import '../process_utils.dart';
import 'agent_runner.dart';

/// Drives Claude Code in print mode with streaming JSON both ways:
/// `claude -p --input-format stream-json --output-format stream-json
/// --verbose [--model <m>] [--effort <e>] [--resume <id>]`.
///
/// The prompt goes in as a user message and stdin stays open while the turn
/// runs, so a model or effort change reaches the running CLI as a control
/// request and applies from its next step. Stdin closes once the result is
/// in, which ends the process. Slash commands are sent as prompts; Claude
/// Code runs the ones that make sense headless.
///
/// Headless Claude Code can only use tools it's allowed to, so give it
/// permissions through the agent's `extraArgs`, e.g.
/// `["--permission-mode", "acceptEdits", "--allowedTools", "Bash(git:*)"]`.
class ClaudeCodeRunner extends CliRunner {
  ClaudeCodeRunner(AgentConfig config)
    : super(
        executable: config.executable ?? 'claude',
        extraArgs: config.extraArgs,
        models: config.models,
      );

  static const _streamArgs = [
    '-p',
    '--input-format',
    'stream-json',
    '--output-format',
    'stream-json',
    '--verbose',
  ];

  var _parser = ClaudeStreamParser();
  var _requests = 0;

  @override
  bool get keepsInputOpen => true;

  @override
  List<String> argsFor({
    String? sessionId,
    String? promptFile,
    String? model,
    EffortLevel? effort,
  }) => [
    ..._streamArgs,
    if (model != null) ...['--model', model],
    if (effort != null) ...['--effort', effort.name],
    if (sessionId != null) ...['--resume', sessionId],
    ...extraArgs,
  ];

  @override
  AgentTurn start({
    required String prompt,
    required String workingDir,
    String? sessionId,
    String? model,
    EffortLevel? effort,
  }) {
    _parser = ClaudeStreamParser();
    return super.start(
      prompt: prompt,
      workingDir: workingDir,
      sessionId: sessionId,
      model: model,
      effort: effort,
    );
  }

  @override
  List<int> encodePrompt(String prompt) =>
      utf8.encode('${jsonEncode(claudeUserMessage(prompt))}\n');

  @override
  String? encodeChange(TurnChange change) => jsonEncode(switch (change) {
    ModelChange(:final model) => _control('set_model', {
      'model': model ?? ModelOption.defaultValue,
    }),
    EffortChange(:final effort) => _control('apply_flag_settings', {
      'settings': {'effortLevel': effort?.name},
    }),
  });

  Json _control(String subtype, Json fields) => {
    'type': 'control_request',
    'request_id': 'dashboard-${++_requests}',
    'request': {'subtype': subtype, ...fields},
  };

  @override
  Iterable<RunnerEvent> parseLine(String line) => _parser.parse(line);

  /// Starts Claude Code without a prompt and sends it the SDK's `initialize`
  /// request, which lists its models and commands without calling a model.
  @override
  Future<RunnerOptions> discover(String workingDir) async {
    final launch = await resolveLaunch(executable);
    if (launch == null) return super.discover(workingDir);
    final process = await Process.start(
      launch.executable,
      [..._streamArgs, ...extraArgs],
      workingDirectory: workingDir,
      runInShell: launch.runInShell,
    );
    process.stdin.done.ignore();
    process.stderr.drain<void>().ignore();
    try {
      process.stdin.writeln(jsonEncode(_control('initialize', const {})));
      final response = await process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .map(decodeJsonLine)
          .firstWhere((json) => json?['type'] == 'control_response')
          .timeout(const Duration(seconds: 45));
      final body = (response!['response'] as Json)['response'] as Json?;
      if (body == null) return await super.discover(workingDir);
      return parseClaudeOptions(body);
    } finally {
      await process.stdin.close().catchError((_) {});
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () async {
          await killTree(process);
          return -1;
        },
      );
    }
  }
}

Json claudeUserMessage(String prompt) => {
  'type': 'user',
  'message': {'role': 'user', 'content': prompt},
  'parent_tool_use_id': null,
  'session_id': '',
};

/// Commands that only make sense in Claude Code's interactive terminal.
const _terminalOnly = {
  'color',
  'doctor',
  'focus',
  'heapdump',
  'reload-plugins',
};

bool _offered(String name, String description) =>
    !name.startsWith('_') &&
    !_terminalOnly.contains(name) &&
    !description.startsWith('(removed)');

/// Reads the models and commands out of Claude Code's `initialize` response.
RunnerOptions parseClaudeOptions(Json response) => (
  models: [
    for (final m in response['models'] as List? ?? const [])
      ModelOption(
        value: (m as Json)['value'] as String,
        label: m['displayName'] as String? ?? m['value'] as String,
        description: m['description'] as String? ?? '',
        resolved: m['resolvedModel'] as String?,
        efforts: [
          for (final name in decodeStrings(m['supportedEffortLevels']))
            ?EffortLevel.tryParse(name),
        ],
      ),
  ],
  commands: [
    for (final c in response['commands'] as List? ?? const [])
      if (_offered(
        (c as Json)['name'] as String,
        c['description'] as String? ?? '',
      ))
        SlashCommand(
          c['name'] as String,
          description: c['description'] as String? ?? '',
          argumentHint: c['argumentHint'] as String? ?? '',
        ),
  ],
);

/// Turns Claude Code's stream-json output into [RunnerEvent]s. One parser
/// follows one turn, since the context window of a result depends on the
/// model the turn ran on.
class ClaudeStreamParser {
  String? _model;

  Iterable<RunnerEvent> parse(String line) sync* {
    final json = decodeJsonLine(line);
    if (json == null) return;
    final session = json['session_id'] as String?;

    switch (json['type']) {
      case 'system':
        yield* _system(json, session);
      case 'rate_limit_event':
        if (parseClaudeRateLimits(json['rate_limit_info'] as Json?)
            case final usage?) {
          yield UsageEvent(usage);
        }
      case 'assistant':
        yield* _assistant(json);
      case 'control_response':
        final response = json['response'] as Json? ?? const {};
        if (response['subtype'] == 'error') {
          yield NoticeEvent(
            "Claude Code couldn't apply the change: "
            '${response['error'] ?? 'unknown error'}',
          );
        }
      case 'result':
        yield* _result(json, session);
    }
  }

  Iterable<RunnerEvent> _system(Json json, String? session) sync* {
    switch (json['subtype']) {
      case 'init':
        if (session != null) yield SessionEvent(session);
        if (json['model'] case final String model) yield* _useModel(model);
        final terminal = decodeStrings(json['terminal_slash_commands']).toSet();
        yield CommandsEvent([
          for (final name in decodeStrings(json['slash_commands']))
            if (!terminal.contains(name) && _offered(name, '')) name,
        ]);
        yield const ActivityEvent('Starting up');
      case 'status' when json['status'] == 'compacting':
        yield const ActivityEvent('Compacting the conversation');
      case 'compact_boundary':
        final meta = json['compact_metadata'] as Json? ?? const {};
        final before = meta['pre_tokens'] as int?;
        final after = meta['post_tokens'] as int?;
        if (after != null) yield ContextEvent(usedTokens: after);
        final sizes = before != null && after != null
            ? ': ${formatTokens(before)} → ${formatTokens(after)} tokens'
            : '';
        yield NoticeEvent(
          meta['trigger'] == 'auto'
              ? 'The context was nearly full, so the conversation was '
                    'compacted$sizes'
              : 'Compacted the conversation$sizes',
        );
    }
  }

  Iterable<RunnerEvent> _useModel(String model) sync* {
    if (model == _model || model.startsWith('<')) return;
    _model = model;
    yield ModelEvent(model);
  }

  Iterable<RunnerEvent> _assistant(Json json) sync* {
    final message = json['message'] as Json? ?? const {};
    final model = message['model'] as String?;
    // Local commands echo their output as a synthetic message; the result
    // carries the same text.
    if (model == '<synthetic>') return;
    final mainThread = json['parent_tool_use_id'] == null;
    if (mainThread && model != null) yield* _useModel(model);
    if (message['usage'] case final Json usage when mainThread) {
      int tokens(String key) => usage[key] as int? ?? 0;
      yield ContextEvent(
        usedTokens:
            tokens('input_tokens') +
            tokens('cache_creation_input_tokens') +
            tokens('cache_read_input_tokens') +
            tokens('output_tokens'),
      );
    }
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
  }

  Iterable<RunnerEvent> _result(Json json, String? session) sync* {
    if (session != null) yield SessionEvent(session);
    final windows = <String, int>{
      for (final e in (json['modelUsage'] as Json? ?? const {}).entries)
        if ((e.value as Json)['contextWindow'] case final int window)
          e.key: window,
    };
    final window =
        windows[_model] ??
        windows.entries
            .where((e) => _model != null && e.key.startsWith(_model!))
            .map((e) => e.value)
            .firstOrNull ??
        windows.values.fold<int?>(
          null,
          (best, w) => best == null || w > best ? w : best,
        );
    if (window != null) yield ContextEvent(maxTokens: window);

    final ok = json['subtype'] == 'success' && json['is_error'] != true;
    final text = (json['result'] as String? ?? '').trim();
    if (ok && json['local_command'] != null && text.isNotEmpty) {
      yield ReplyEvent(text);
    }
    yield FinishedEvent(
      success: ok,
      error: ok
          ? null
          : text.isNotEmpty
          ? text
          : 'Claude Code stopped: ${json['subtype']}',
    );
  }
}

/// Reads Claude Code's `rate_limit_info`, which lists every limit window
/// under `unifiedWindows` (or just the one it is about in older versions).
UsageLimits? parseClaudeRateLimits(Json? info) {
  if (info == null) return null;
  DateTime? resets(Object? seconds) => seconds is num
      ? DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round())
      : null;
  final unified = info['unifiedWindows'] as Json? ?? const {};
  final windows = [
    for (final e in unified.entries)
      if ((e.value as Json)['utilization'] case final num used)
        UsageWindow(
          kind: e.key,
          utilization: used.toDouble(),
          resetsAt: resets((e.value as Json)['resetsAt']),
        ),
  ];
  if (windows.isEmpty) {
    if (info case {
      'rateLimitType': final String kind,
      'utilization': final num used,
    }) {
      windows.add(
        UsageWindow(
          kind: kind,
          utilization: used.toDouble(),
          resetsAt: resets(info['resetsAt']),
        ),
      );
    }
  }
  if (windows.isEmpty) return null;
  return UsageLimits(
    windows: windows,
    updatedAt: DateTime.now(),
    limited: info['status'] == 'rejected',
  );
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
