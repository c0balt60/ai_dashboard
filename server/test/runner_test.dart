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
  List<String> argsFor({String? sessionId, String? promptFile}) => [
    script,
    ?sessionId,
  ];

  @override
  Iterable<RunnerEvent> parseLine(String line) => parseClaudeEvent(line);
}

void main() {
  test(
    'Claude Code stream-json becomes session, activity, replies and steps',
    () {
      final events = claudeFixture.expand(parseClaudeEvent).toList();

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
    final events = parseClaudeEvent(
      '{"type":"result","subtype":"error_during_execution","is_error":true,'
      '"result":"Credit balance too low"}',
    ).toList();
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
}
