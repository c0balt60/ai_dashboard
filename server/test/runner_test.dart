import 'dart:convert';
import 'dart:io';

import 'package:ai_dashboard_server/config.dart';
import 'package:ai_dashboard_server/runners/agent_runner.dart';
import 'package:ai_dashboard_server/runners/claude_code_runner.dart';
import 'package:ai_dashboard_server/runners/codex_runner.dart';
import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

/// Recorded from `claude -p --output-format stream-json --verbose`.
const claudeFixture = [
  '{"type":"system","subtype":"init","session_id":"s-1","cwd":"C:/dev/app"}',
  '{"type":"assistant","session_id":"s-1","message":{"content":[{"type":"text","text":"Looking at the tests."},{"type":"tool_use","name":"Bash","input":{"command":"flutter test"}}]}}',
  '{"type":"user","session_id":"s-1","message":{"content":[{"type":"tool_result","content":"ok"}]}}',
  '{"type":"assistant","session_id":"s-1","message":{"content":[{"type":"tool_use","name":"TodoWrite","input":{"todos":[{"content":"Fix parser","status":"completed","activeForm":"Fixing parser"},{"content":"Add test","status":"in_progress","activeForm":"Adding a test"}]}}]}}',
  '{"type":"assistant","session_id":"s-1","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"C:/dev/app/lib/parser.dart"}}]}}',
  'not json',
  '{"type":"result","subtype":"success","is_error":false,"result":"Done.","session_id":"s-1"}',
];

/// Runs the Dart VM on a script that behaves like Claude Code, to exercise
/// process start, stdin and line parsing.
class FakeClaudeRunner extends CliRunner {
  FakeClaudeRunner(this.script)
    : super(executable: Platform.resolvedExecutable);

  final String script;

  @override
  List<String> argsFor({
    String? sessionId,
    String? promptFile,
    String? model,
    EffortLevel? effort,
  }) => [script, ?sessionId];

  final _parser = ClaudeStreamParser();

  @override
  Iterable<RunnerEvent> parseLine(String line) => _parser.parse(line);
}

void main() {
  test(
    'Claude Code stream-json becomes session, activity, replies and steps',
    () {
      final events = claudeFixture.expand(ClaudeStreamParser().parse).toList();

      expect(events.whereType<SessionEvent>().first.sessionId, 's-1');
      expect(events.whereType<ReplyEvent>().map((e) => e.text), [
        'Looking at the tests.',
      ]);
      expect(events.whereType<ActivityEvent>().map((e) => e.activity), [
        'Starting up',
        'Running: flutter test',
        'Adding a test',
        'Editing parser.dart',
      ]);
      final steps = events.whereType<StepsEvent>().single.steps;
      expect(steps.map((s) => (s.title, s.done)), [
        ('Fix parser', true),
        ('Add test', false),
      ]);
      final finished = events.last as FinishedEvent;
      expect(finished.success, isTrue);
    },
  );

  test('a Claude Code error result fails the turn with its message', () {
    final events = ClaudeStreamParser()
        .parse(
          '{"type":"result","subtype":"error_during_execution","is_error":true,'
          '"result":"Credit balance too low"}',
        )
        .toList();
    final finished = events.single as FinishedEvent;
    expect(finished.success, isFalse);
    expect(finished.error, 'Credit balance too low');
  });

  test('Codex JSON events map to the same runner events', () {
    final runner = CodexRunner(
      const AgentConfig(id: 'c', name: 'Codex', type: AgentType.codex),
    );
    expect(runner.argsFor(sessionId: 'th-1'), [
      'exec',
      '--json',
      '--skip-git-repo-check',
      'resume',
      'th-1',
      '-',
    ]);
    final events = [
      '{"type":"thread.started","thread_id":"th-2"}',
      '{"type":"item.started","item":{"type":"command_execution","command":"ls"}}',
      '{"type":"item.completed","item":{"type":"agent_message","text":"All good"}}',
      '{"type":"turn.completed"}',
    ].expand(runner.parseLine).toList();
    expect((events[0] as SessionEvent).sessionId, 'th-2');
    expect((events[1] as ActivityEvent).activity, 'Running: ls');
    expect((events[2] as ReplyEvent).text, 'All good');
    expect((events[3] as FinishedEvent).success, isTrue);
  });

  test(
    'CliRunner feeds the prompt on stdin and streams parsed output',
    () async {
      final dir = await Directory.systemTemp.createTemp('fake_cli');
      addTearDown(() => dir.delete(recursive: true));
      final script = File('${dir.path}/fake_claude.dart')
        ..writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final prompt = await stdin.transform(utf8.decoder).join();
  final session = args.isEmpty ? 'new' : args.first;
  print(jsonEncode({'type': 'system', 'subtype': 'init', 'session_id': session}));
  print(jsonEncode({'type': 'assistant', 'message': {'content': [
    {'type': 'text', 'text': 'You said: $prompt'},
  ]}}));
  print(jsonEncode({'type': 'result', 'subtype': 'success', 'session_id': session}));
}
''');
      final turn = FakeClaudeRunner(script.path).start(
        prompt: 'héllo & "quotes"',
        workingDir: dir.path,
        sessionId: 'old',
      );
      final events = await turn.events.toList();
      expect((events.first as SessionEvent).sessionId, 'old');
      expect(
        events.whereType<ReplyEvent>().single.text,
        'You said: héllo & "quotes"',
      );
      expect((events.last as FinishedEvent).success, isTrue);
    },
  );

  test(
    'a CLI missing from the PATH fails the turn with a clear message',
    () async {
      final runner = ClaudeCodeRunner(
        const AgentConfig(
          id: 'x',
          name: 'X',
          type: AgentType.claudeCode,
          executable: 'definitely-not-a-real-cli-123',
        ),
      );
      final events = await runner
          .start(prompt: 'hi', workingDir: Directory.current.path)
          .events
          .toList();
      final finished = events.single as FinishedEvent;
      expect(finished.success, isFalse);
      expect(finished.error, contains("Can't find definitely-not-a-real-cli"));
    },
    skip: Platform.isWindows ? false : 'PATH lookup only runs on Windows',
  );

  test('a missing CLI fails the turn instead of throwing', () async {
    final runner = ClaudeCodeRunner(
      const AgentConfig(
        id: 'x',
        name: 'X',
        type: AgentType.claudeCode,
        executable: 'definitely-not-a-real-cli-123.exe',
      ),
    );
    final events = await runner
        .start(prompt: 'hi', workingDir: Directory.current.path)
        .events
        .toList();
    final finished = events.single as FinishedEvent;
    expect(finished.success, isFalse);
  });

  test('Claude Code reports its model, limits and context fill', () {
    final parser = ClaudeStreamParser();
    final events = [
      '{"type":"system","subtype":"init","session_id":"s-2","model":"claude-haiku-4-5-20251001","slash_commands":["compact","doctor","context","__hidden"],"terminal_slash_commands":["doctor"]}',
      '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed_warning","resetsAt":1790726400,"rateLimitType":"seven_day","utilization":0.82,"unifiedWindows":{"five_hour":{"utilization":0.02,"resetsAt":1790583000},"seven_day":{"utilization":0.82,"resetsAt":1790726400}}}}',
      '{"type":"assistant","parent_tool_use_id":null,"message":{"model":"claude-haiku-4-5-20251001","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":9,"cache_creation_input_tokens":35280,"cache_read_input_tokens":0,"output_tokens":4}}}',
      '{"type":"assistant","parent_tool_use_id":"tool-1","message":{"model":"claude-sonnet-5","content":[],"usage":{"input_tokens":999999}}}',
      '{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"s-2","modelUsage":{"claude-sonnet-5":{"contextWindow":1000000},"claude-haiku-4-5-20251001":{"contextWindow":200000}}}',
    ].expand(parser.parse).toList();

    expect(events.whereType<ModelEvent>().single.model, contains('haiku'));
    expect(events.whereType<CommandsEvent>().single.names, [
      'compact',
      'context',
    ]);
    final usage = events.whereType<UsageEvent>().single.usage;
    expect(
      [for (final w in usage.windows) (w.kind, w.utilization)],
      [('five_hour', 0.02), ('seven_day', 0.82)],
    );
    expect(
      usage.windows.first.resetsAt!.toUtc(),
      DateTime.utc(2026, 9, 28, 8, 10),
    );
    final context = events.whereType<ContextEvent>().toList();
    // The subagent's request doesn't count, and the window is the one of
    // the model the turn ran on.
    expect(context.map((c) => (c.usedTokens, c.maxTokens)), [
      (35293, null),
      (null, 200000),
    ]);
    expect(events.whereType<ReplyEvent>().map((e) => e.text), ['ok']);
  });

  test('local commands answer once and /compact shrinks the context', () {
    final parser = ClaudeStreamParser();
    final context = [
      '{"type":"assistant","message":{"model":"<synthetic>","content":[{"type":"text","text":"## Context Usage"}]}}',
      '{"type":"result","subtype":"success","is_error":false,"num_turns":0,"result":"## Context Usage","local_command":"context"}',
    ].expand(parser.parse).toList();
    expect(context.whereType<ReplyEvent>().map((e) => e.text), [
      '## Context Usage',
    ]);

    final compact = [
      '{"type":"system","subtype":"status","status":"compacting"}',
      '{"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"manual","pre_tokens":35429,"post_tokens":1799}}',
      '{"type":"control_response","response":{"subtype":"error","request_id":"r1","error":"Model \'x\' not found"}}',
      '{"type":"result","subtype":"success","is_error":false,"result":"","local_command":"compact"}',
    ].expand(ClaudeStreamParser().parse).toList();
    expect(
      compact.whereType<ActivityEvent>().single.activity,
      'Compacting the conversation',
    );
    expect(compact.whereType<ContextEvent>().single.usedTokens, 1799);
    expect(compact.whereType<NoticeEvent>().map((e) => e.text), [
      'Compacted the conversation: 35.4k → 1.8k tokens',
      "Claude Code couldn't apply the change: Model 'x' not found",
    ]);
    expect(compact.whereType<ReplyEvent>(), isEmpty);
  });

  test('Claude Code gets the model and effort and takes changes on stdin', () {
    final runner = ClaudeCodeRunner(
      const AgentConfig(
        id: 'c',
        name: 'Claude',
        type: AgentType.claudeCode,
        extraArgs: ['--permission-mode', 'acceptEdits'],
      ),
    );
    expect(
      runner.argsFor(
        sessionId: 's-1',
        model: 'sonnet',
        effort: EffortLevel.xhigh,
      ),
      [
        '-p',
        '--input-format',
        'stream-json',
        '--output-format',
        'stream-json',
        '--verbose',
        '--model',
        'sonnet',
        '--effort',
        'xhigh',
        '--resume',
        's-1',
        '--permission-mode',
        'acceptEdits',
      ],
    );
    Json request(TurnChange change) =>
        (jsonDecode(runner.encodeChange(change)!) as Json)['request'] as Json;
    expect(request(const ModelChange(null)), {
      'subtype': 'set_model',
      'model': 'default',
    });
    expect(request(const EffortChange(EffortLevel.low)), {
      'subtype': 'apply_flag_settings',
      'settings': {'effortLevel': 'low'},
    });
    final prompt = jsonDecode(utf8.decode(runner.encodePrompt('/compact')));
    expect(((prompt as Json)['message'] as Json)['content'], '/compact');
  });

  test('the initialize response lists models and usable commands', () {
    final options = parseClaudeOptions({
      'models': [
        {
          'value': 'default',
          'resolvedModel': 'claude-opus-5-5[1m]',
          'displayName': 'Default (recommended)',
          'description': 'Opus 5.5 with 1M context',
          'supportedEffortLevels': ['low', 'medium', 'high', 'xhigh', 'max'],
        },
        {'value': 'haiku', 'resolvedModel': 'claude-haiku-4-5-20251001'},
      ],
      'commands': [
        {
          'name': 'compact',
          'description': 'Free up context',
          'argumentHint': '<instructions>',
        },
        {'name': 'doctor', 'description': 'Health-check'},
        {'name': '__remote-workflow', 'description': 'Internal'},
        {'name': 'agents', 'description': '(removed) Ask Claude'},
      ],
    });
    expect(options.models.map((m) => (m.shortName, m.efforts.length)), [
      ('Opus 5.5 (1M)', 5),
      ('Haiku 4.5', 0),
    ]);
    expect(options.commands.single.argumentHint, '<instructions>');
  });

  test('an interactive CLI takes a model change mid-turn and exits after its result', () async {
    final dir = await Directory.systemTemp.createTemp('fake_cli');
    addTearDown(() => dir.delete(recursive: true));
    final script = File('${dir.path}/fake_claude.dart')
      ..writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';

void send(Object json) => print(jsonEncode(json));

Future<void> main() async {
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    final json = jsonDecode(line) as Map;
    if (json['type'] == 'user') {
      send({
        'type': 'system',
        'subtype': 'init',
        'session_id': 's',
        'model': 'claude-haiku-4-5',
      });
    } else if (json['type'] == 'control_request') {
      final model = (json['request'] as Map)['model'];
      send({
        'type': 'assistant',
        'message': {
          'model': 'claude-$model-5',
          'content': [
            {'type': 'text', 'text': 'now on $model'},
          ],
        },
      });
      send({'type': 'result', 'subtype': 'success', 'session_id': 's'});
    }
  }
}
''');
    final runner = FakeInteractiveClaude(script.path);
    final turn = runner.start(prompt: 'hi', workingDir: dir.path);
    final events = <RunnerEvent>[];
    await for (final event in turn.events) {
      events.add(event);
      if (event is ModelEvent && event.model == 'claude-haiku-4-5') {
        expect(turn.apply(const ModelChange('sonnet')), isTrue);
      }
    }
    expect(events.whereType<ModelEvent>().map((e) => e.model), [
      'claude-haiku-4-5',
      'claude-sonnet-5',
    ]);
    expect(events.whereType<ReplyEvent>().single.text, 'now on sonnet');
    expect((events.last as FinishedEvent).success, isTrue);
    expect(turn.apply(const ModelChange('opus')), isFalse);
  }, timeout: const Timeout(Duration(seconds: 60)));
}

/// Runs a Dart script that talks stream-json the way Claude Code does.
class FakeInteractiveClaude extends ClaudeCodeRunner {
  FakeInteractiveClaude(this.script)
    : super(
        AgentConfig(
          id: 'fake',
          name: 'Fake',
          type: AgentType.claudeCode,
          executable: Platform.resolvedExecutable,
        ),
      );

  final String script;

  @override
  List<String> argsFor({
    String? sessionId,
    String? promptFile,
    String? model,
    EffortLevel? effort,
  }) => [script];
}
