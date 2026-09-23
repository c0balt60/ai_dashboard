import 'dart:async';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:ai_dashboard_server/config.dart';
import 'package:ai_dashboard_server/local_backend.dart';
import 'package:ai_dashboard_server/runners/agent_runner.dart';
import 'package:ai_dashboard_server/state_store.dart';
import 'package:ai_dashboard_server/test_summary.dart';
import 'package:test/test.dart';

class FakeTurn {
  FakeTurn(this.prompt, this.workingDir, this.sessionId);

  final String prompt;
  final String workingDir;
  final String? sessionId;
  final controller = StreamController<RunnerEvent>();
  var cancelled = false;

  void emit(RunnerEvent event) {
    controller.add(event);
    if (event is FinishedEvent) controller.close();
  }
}

/// Hands out turns the test drives by hand.
class FakeRunner implements AgentRunner {
  final turns = <FakeTurn>[];

  @override
  AgentTurn start({
    required String prompt,
    required String workingDir,
    String? sessionId,
  }) {
    final turn = FakeTurn(prompt, workingDir, sessionId);
    turns.add(turn);
    return AgentTurn(turn.controller.stream, () async {
      turn.cancelled = true;
      if (!turn.controller.isClosed) {
        turn.emit(const FinishedEvent(success: false, error: 'Stopped'));
      }
    });
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late Directory dir;
  late ServerConfig config;
  late FakeRunner runner;

  LocalAgentBackend create() => LocalAgentBackend(
    config,
    runnerFor: (_) => runner,
    store: StateStore(config.dataDir, debounce: Duration.zero),
    branchOf: (_) async => 'main',
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('local_backend');
    final project = Directory('${dir.path}/app')..createSync();
    runner = FakeRunner();
    config = ServerConfig(
      token: 'x' * 24,
      dataDir: '${dir.path}/data',
      projects: [
        ProjectConfig(
          id: 'app',
          name: 'app',
          path: project.path,
          testCommand: 'echo "00:01 +3 -1: Some tests failed."; exit 1',
        ),
      ],
      agents: const [
        AgentConfig(
          id: 'claude',
          name: 'Claude',
          type: AgentType.claudeCode,
          projectId: 'app',
        ),
      ],
    );
  });

  tearDown(() => dir.delete(recursive: true));

  Future<Agent> agent(LocalAgentBackend b) async =>
      (await b.watchAgents().first).single;

  test('a prompt runs a turn, posts replies and resumes the session', () async {
    final backend = create();
    addTearDown(backend.dispose);

    await backend.sendPrompt('claude', 'Explain main.dart');
    expect((await agent(backend)).status, AgentStatus.running);
    final turn = runner.turns.single;
    expect(turn.workingDir, config.projects.single.path);

    turn
      ..emit(const SessionEvent('s-1'))
      ..emit(const ActivityEvent('Reading main.dart'))
      ..emit(const ReplyEvent('It boots the app.'))
      ..emit(const FinishedEvent(success: true));
    await settle();

    expect((await agent(backend)).status, AgentStatus.waiting);
    final messages = await backend.watchMessages('claude').first;
    expect(messages.map((m) => (m.role, m.text)), [
      (MessageRole.user, 'Explain main.dart'),
      (MessageRole.agent, 'It boots the app.'),
    ]);

    await backend.sendPrompt('claude', 'Thanks');
    expect(runner.turns.last.sessionId, 's-1');
  });

  test(
    'a queued task starts right away, tracks steps and records tests',
    () async {
      final backend = create();
      addTearDown(backend.dispose);

      final created = await backend.createTask(
        'Fix login',
        'app',
        agentId: 'claude',
      );
      var task = (await backend.watchTasks().first).single;
      expect(task.state, TaskState.active);
      expect(runner.turns.single.prompt, contains('Fix login'));

      runner.turns.single.emit(
        const StepsEvent([
          TaskStep('Find bug', done: true),
          TaskStep('Fix it'),
        ]),
      );
      await settle();
      task = (await backend.watchTasks().first).single;
      expect(task.steps, hasLength(2));
      expect(task.progress, closeTo(0.475, 0.001));

      runner.turns.single.emit(const FinishedEvent(success: true));
      await settle();
      task = (await backend.watchTasks().first).single;
      expect(task.id, created.id);
      expect(task.state, TaskState.completed);
      expect((await agent(backend)).status, AgentStatus.completed);

      Future<Project> latest() async =>
          (await backend.watchProjects().first).single;
      for (var i = 0; i < 100; i++) {
        final run = (await latest()).latestTestRun;
        if (run != null && run.status != TestStatus.running) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final run = (await latest()).latestTestRun!;
      expect(run.status, TestStatus.failed);
      expect((run.passed, run.failed), (3, 1));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('stopping cancels the turn and moves its task to the backlog', () async {
    final backend = create();
    addTearDown(backend.dispose);

    await backend.createTask('Refactor', 'app', agentId: 'claude');
    await backend.stopAgent('claude');
    await settle();

    expect(runner.turns.single.cancelled, isTrue);
    final task = (await backend.watchTasks().first).single;
    expect(task.state, TaskState.backlog);
    expect(task.agentId, isNull);
    expect((await agent(backend)).status, AgentStatus.idle);
  });

  test('state survives a restart and interrupted work is requeued', () async {
    final first = create();
    await first.sendPrompt('claude', 'Remember me');
    runner.turns.single
      ..emit(const SessionEvent('s-9'))
      ..emit(const FinishedEvent(success: true));
    await settle();
    await first.createTask('Long job', 'app', agentId: 'claude');
    await first.createTodoList('Release');
    first.dispose();

    runner = FakeRunner();
    final second = create();
    addTearDown(second.dispose);

    final messages = await second.watchMessages('claude').first;
    expect(messages.first.text, 'Remember me');
    expect((await second.watchTodoLists().first).single.title, 'Release');
    final task = (await second.watchTasks().first).single;
    expect(task.state, TaskState.active, reason: 'restarted on boot');
    expect(runner.turns.single.sessionId, 's-9');
  });

  test('runCommand runs in the project folder and reports failures', () async {
    final backend = create();
    addTearDown(backend.dispose);

    final ok = await backend.runCommand('app', 'echo hello');
    expect(ok.trim(), 'hello');
    final failed = await backend.runCommand('app', 'exit 3');
    expect(failed, contains('[exit code 3]'));
    expect(await backend.runCommand('nope', 'ls'), startsWith('error:'));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('test summaries are read from common runners', () {
    final dart = parseTestSummary(
      '00:01 +1: a\n00:02 +1 -1: b [E]\r\n00:03 +2 -1: Some tests failed.',
    );
    expect((dart.passed, dart.failed), (2, 1));
    expect(dart.failing, ['b']);

    final pytest = parseTestSummary(
      'FAILED tests/x.py::t - boom\n=== 1 failed, 4 passed ===',
    );
    expect((pytest.passed, pytest.failed), (4, 1));
    expect(pytest.failing, ['tests/x.py::t']);

    final unknown = parseTestSummary('build ok');
    expect((unknown.passed, unknown.failed), (0, 0));
    expect(unknown.failing, isEmpty);
  });
}
