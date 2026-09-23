import 'dart:async';
import 'dart:math';

import '../models/models.dart';
import 'agent_backend.dart';
import 'mock_seed.dart';

/// In-memory [AgentBackend] that fakes a host PC running several agents.
///
/// With [simulate] on, a periodic tick advances active tasks, completes or
/// fails them, promotes queued work and records test runs, so the UI shows
/// live-looking activity without any server.
class MockAgentBackend implements AgentBackend {
  MockAgentBackend({
    bool simulate = true,
    this.latency = const Duration(milliseconds: 600),
    this.tickInterval = const Duration(seconds: 3),
    Random? random,
  }) : _random = random ?? Random(42) {
    final seed = MockSeed(DateTime.now());
    for (final p in seed.projects) {
      _projects[p.id] = p;
    }
    for (final a in seed.agents) {
      _agents[a.id] = a;
    }
    for (final t in seed.tasks) {
      _tasks[t.id] = t;
    }
    seed.messages.forEach((id, list) => _messages[id] = [...list]);
    setSimulationEnabled(simulate);
  }

  final Duration latency;
  final Duration tickInterval;
  final Random _random;

  final _projects = <String, Project>{};
  final _agents = <String, Agent>{};
  final _tasks = <String, AgentTask>{};
  final _messages = <String, List<ChatMessage>>{};
  final _changes = StreamController<void>.broadcast();
  Timer? _ticker;
  int _idCounter = 0;

  String _nextId(String prefix) => '$prefix-${++_idCounter}';

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  @override
  Stream<List<Agent>> watchAgents() =>
      _watch(() => List.unmodifiable(_agents.values));

  @override
  Stream<List<Project>> watchProjects() =>
      _watch(() => List.unmodifiable(_projects.values));

  @override
  Stream<List<AgentTask>> watchTasks() =>
      _watch(() => List.unmodifiable(_tasks.values));

  @override
  Stream<List<ChatMessage>> watchMessages(String agentId) =>
      _watch(() => List.unmodifiable(_messages[agentId] ?? const []));

  @override
  Future<void> sendPrompt(String agentId, String text) async {
    final agent = _agents[agentId];
    if (agent == null) return;
    _addMessage(agentId, MessageRole.user, text);
    _agents[agentId] = agent.copyWith(
      status: AgentStatus.running,
      activity: 'Thinking about: ${_truncate(text, 40)}',
      lastActive: DateTime.now(),
    );
    _notify();

    await Future<void>.delayed(latency);
    final current = _agents[agentId];
    if (current == null || _changes.isClosed) return;

    _addMessage(agentId, MessageRole.agent, _replyTo(current, text));
    final activeTask = _activeTaskFor(agentId);
    _agents[agentId] = current.copyWith(
      status: activeTask != null ? AgentStatus.running : AgentStatus.waiting,
      activity: activeTask != null
          ? _nextStepTitle(activeTask)
          : 'Waiting for your next instruction',
      lastActive: DateTime.now(),
    );
    _notify();
  }

  @override
  Future<void> assignAgent(
    String agentId, {
    required String projectId,
    required String workingDir,
    String? taskId,
  }) async {
    final agent = _agents[agentId];
    final project = _projects[projectId];
    if (agent == null || project == null) return;

    final previous = _activeTaskFor(agentId);
    if (previous != null && previous.id != taskId) {
      _tasks[previous.id] = previous.copyWith(
        state: TaskState.waiting,
        updatedAt: DateTime.now(),
      );
    }

    var updated = agent.copyWith(
      projectId: () => projectId,
      workingDir: () => workingDir,
      branch: () => project.branch,
      lastActive: DateTime.now(),
    );

    final task = taskId == null ? null : _tasks[taskId];
    if (task != null) {
      _tasks[task.id] = task.copyWith(
        state: TaskState.active,
        agentId: () => agentId,
        updatedAt: DateTime.now(),
      );
      updated = updated.copyWith(
        status: AgentStatus.running,
        currentTaskId: () => task.id,
        activity: _nextStepTitle(task),
      );
    } else {
      updated = updated.copyWith(
        status: AgentStatus.waiting,
        currentTaskId: () => null,
        activity: 'Waiting for instructions',
      );
    }
    _agents[agentId] = updated;

    _addMessage(
      agentId,
      MessageRole.system,
      task == null
          ? 'Assigned to $workingDir'
          : 'Assigned to $workingDir · task "${task.title}"',
    );
    _log(projectId, '${agent.name} assigned to $workingDir', agentId: agentId);
    _notify();
  }

  @override
  Future<void> stopAgent(String agentId) async {
    final agent = _agents[agentId];
    if (agent == null) return;
    final task = _activeTaskFor(agentId);
    if (task != null) {
      _tasks[task.id] = task.copyWith(
        state: TaskState.backlog,
        agentId: () => null,
        updatedAt: DateTime.now(),
      );
    }
    _agents[agentId] = agent.copyWith(
      status: AgentStatus.idle,
      activity: 'Stopped by user',
      currentTaskId: () => null,
      lastActive: DateTime.now(),
    );
    _addMessage(agentId, MessageRole.system, 'Stopped by user');
    if (agent.projectId != null) {
      _log(
        agent.projectId!,
        '${agent.name} stopped by user',
        agentId: agentId,
        level: LogLevel.warning,
      );
    }
    _notify();
  }

  @override
  Future<void> clearMessages(String agentId) async {
    _messages[agentId] = [];
    _notify();
  }

  @override
  Future<AgentTask> createTask(
    String title,
    String projectId, {
    String? agentId,
  }) async {
    final now = DateTime.now();
    final task = AgentTask(
      id: _nextId('t'),
      title: title,
      projectId: projectId,
      agentId: agentId,
      state: agentId == null ? TaskState.backlog : TaskState.waiting,
      steps: _defaultSteps(title),
      createdAt: now,
      updatedAt: now,
    );
    _tasks[task.id] = task;
    _log(projectId, 'Task created: $title', agentId: agentId);
    _notify();
    return task;
  }

  @override
  Future<void> updateTaskState(String taskId, TaskState state) async {
    final task = _tasks[taskId];
    if (task == null) return;
    final now = DateTime.now();
    final done = state == TaskState.completed || state == TaskState.failed;
    _tasks[taskId] = task.copyWith(
      state: state,
      agentId: state == TaskState.backlog ? () => null : null,
      progress: state == TaskState.completed ? 1 : null,
      updatedAt: now,
      completedAt: () => done ? now : null,
    );

    final agent = task.agentId == null ? null : _agents[task.agentId];
    if (agent != null &&
        agent.currentTaskId == taskId &&
        state != TaskState.active) {
      _agents[agent.id] = agent.copyWith(
        status: switch (state) {
          TaskState.completed => AgentStatus.completed,
          TaskState.failed => AgentStatus.failed,
          _ => AgentStatus.idle,
        },
        activity: 'Task moved to ${state.name}',
        currentTaskId: () => null,
        lastActive: now,
      );
    }
    _notify();
  }

  @override
  Future<String> runCommand(String projectId, String command) async {
    final project = _projects[projectId];
    if (project == null) return 'error: unknown project $projectId';
    await Future<void>.delayed(latency);
    final output = _fakeOutput(project, command.trim());
    _log(projectId, '\$ ${command.trim()}');
    _notify();
    return output;
  }

  @override
  Future<Duration> ping() async {
    final rtt = Duration(milliseconds: 18 + _random.nextInt(40));
    await Future<void>.delayed(latency == Duration.zero ? Duration.zero : rtt);
    return rtt;
  }

  @override
  void setSimulationEnabled(bool enabled) {
    _ticker?.cancel();
    _ticker = enabled ? Timer.periodic(tickInterval, (_) => _tick()) : null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _changes.close();
  }

  void _tick() {
    final now = DateTime.now();

    for (final task in _tasks.values.toList()) {
      if (task.state != TaskState.active || task.agentId == null) continue;
      final agent = _agents[task.agentId];
      if (agent == null) continue;

      final progress = (task.progress + 0.03 + _random.nextDouble() * 0.06)
          .clamp(0.0, 1.0);
      if (progress >= 1) {
        _finishTask(task, agent, failed: _random.nextDouble() < 0.2);
        continue;
      }
      final updated = task.copyWith(
        progress: progress,
        steps: _stepsFor(task.steps, progress),
        updatedAt: now,
      );
      _tasks[task.id] = updated;
      _agents[agent.id] = agent.copyWith(
        status: AgentStatus.running,
        activity: _nextStepTitle(updated),
        lastActive: now,
      );
      _projects[task.projectId] = _projects[task.projectId]!.copyWith(
        lastActivity: now,
      );
    }

    _promoteWaitingTasks(now);
    _notify();
  }

  void _finishTask(AgentTask task, Agent agent, {required bool failed}) {
    final now = DateTime.now();
    _tasks[task.id] = task.copyWith(
      state: failed ? TaskState.failed : TaskState.completed,
      progress: failed ? task.progress : 1,
      steps: failed ? task.steps : _stepsFor(task.steps, 1),
      updatedAt: now,
      completedAt: () => now,
    );
    _agents[agent.id] = agent.copyWith(
      status: failed ? AgentStatus.failed : AgentStatus.completed,
      activity: failed ? 'Failed: ${task.title}' : 'Finished: ${task.title}',
      currentTaskId: () => null,
      lastActive: now,
    );

    final failCount = failed ? 1 + _random.nextInt(3) : 0;
    final project = _projects[task.projectId]!;
    final run = TestRun(
      id: _nextId('r'),
      suite: _testCommandFor(project),
      status: failed ? TestStatus.failed : TestStatus.passed,
      passed: 20 + _random.nextInt(80),
      failed: failCount,
      failingTests: [
        for (var i = 0; i < failCount; i++) '${task.title} › case ${i + 1}',
      ],
      duration: Duration(seconds: 10 + _random.nextInt(90)),
      at: now,
      agentId: agent.id,
    );
    _projects[project.id] = project.copyWith(
      testRuns: [run, ...project.testRuns],
      lastActivity: now,
    );
    _log(
      project.id,
      failed ? 'Failed: ${task.title}' : 'Completed: ${task.title}',
      agentId: agent.id,
      level: failed ? LogLevel.error : LogLevel.success,
    );
    _addMessage(
      agent.id,
      MessageRole.agent,
      failed
          ? 'I could not finish "${task.title}": $failCount test(s) still fail. Can you take a look?'
          : 'Done with "${task.title}". All ${run.passed} tests pass.',
    );
  }

  /// Starts the oldest waiting task of every agent that is free.
  void _promoteWaitingTasks(DateTime now) {
    for (final agent in _agents.values.toList()) {
      if (agent.status == AgentStatus.failed) continue;
      if (_activeTaskFor(agent.id) != null) continue;
      final waiting =
          _tasks.values
              .where(
                (t) => t.agentId == agent.id && t.state == TaskState.waiting,
              )
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (waiting.isEmpty) continue;
      // Leave agents waiting for user input alone, unless they just finished.
      if (agent.status == AgentStatus.waiting && _random.nextDouble() < 0.7) {
        continue;
      }

      final task = waiting.first;
      final project = _projects[task.projectId]!;
      _tasks[task.id] = task.copyWith(state: TaskState.active, updatedAt: now);
      _agents[agent.id] = agent.copyWith(
        status: AgentStatus.running,
        projectId: () => project.id,
        workingDir: () => project.path,
        branch: () => project.branch,
        currentTaskId: () => task.id,
        activity: _nextStepTitle(task),
        lastActive: now,
      );
      _log(
        project.id,
        '${agent.name} started: ${task.title}',
        agentId: agent.id,
      );
    }
  }

  AgentTask? _activeTaskFor(String agentId) {
    for (final t in _tasks.values) {
      if (t.agentId == agentId && t.state == TaskState.active) return t;
    }
    return null;
  }

  void _addMessage(String agentId, MessageRole role, String text) {
    (_messages[agentId] ??= []).add(
      ChatMessage(
        id: _nextId('m'),
        agentId: agentId,
        role: role,
        text: text,
        at: DateTime.now(),
      ),
    );
  }

  void _log(
    String projectId,
    String message, {
    String? agentId,
    LogLevel level = LogLevel.info,
  }) {
    final project = _projects[projectId];
    if (project == null) return;
    final now = DateTime.now();
    _projects[projectId] = project.copyWith(
      lastActivity: now,
      log: [
        LogEntry(at: now, message: message, agentId: agentId, level: level),
        ...project.log.take(49),
      ],
    );
  }

  List<TaskStep> _stepsFor(List<TaskStep> steps, double progress) {
    final done = (progress * steps.length).floor();
    return [
      for (var i = 0; i < steps.length; i++)
        TaskStep(steps[i].title, done: i < done),
    ];
  }

  String _nextStepTitle(AgentTask task) {
    for (final s in task.steps) {
      if (!s.done) return s.title;
    }
    return task.title;
  }

  List<TaskStep> _defaultSteps(String title) => [
    const TaskStep('Explore relevant code'),
    TaskStep('Plan changes for "${_truncate(title, 30)}"'),
    const TaskStep('Implement changes'),
    const TaskStep('Run tests'),
    const TaskStep('Summarize and commit'),
  ];

  String _testCommandFor(Project project) {
    if (project.testRuns.isNotEmpty) return project.testRuns.first.suite;
    return 'npm test';
  }

  String _replyTo(Agent agent, String prompt) {
    final p = prompt.toLowerCase();
    final dir = agent.workingDir ?? 'the current folder';
    final task = _activeTaskFor(agent.id);
    if (p.contains('test')) {
      final n = 20 + _random.nextInt(60);
      return 'Ran the test suite in $dir: $n passed, 0 failed. '
          'Coverage is unchanged.';
    }
    if (p.contains('commit')) {
      return 'Committed staged changes on ${agent.branch ?? 'the current branch'}: '
          '"${task?.title ?? 'Apply requested changes'}" '
          '(${2 + _random.nextInt(8)} files changed).';
    }
    if (p.contains('summar') ||
        p.contains('progress') ||
        p.contains('status')) {
      if (task == null) return 'No active task right now. Waiting in $dir.';
      final done = task.steps.where((s) => s.done).length;
      return 'Working on "${task.title}" — $done/${task.steps.length} steps done '
          '(${(task.progress * 100).round()}%). Next: ${_nextStepTitle(task)}.';
    }
    return 'Got it. I\'ll ${_truncate(prompt, 80)}\n\n'
        'I\'ll start by exploring $dir, then report back with a plan.';
  }

  String _fakeOutput(Project project, String command) {
    if (command.startsWith('git status')) {
      return 'On branch ${project.branch}\n'
          'Changes not staged for commit:\n'
          '  modified:   src/app.ts\n'
          '  modified:   README.md\n\n'
          'no changes added to commit (use "git add" and/or "git commit -a")';
    }
    if (command.startsWith('git log')) {
      return 'a1b2c3d (HEAD -> ${project.branch}) Add webhook route\n'
          '9f8e7d6 Fix lint warnings\n'
          '4c5b6a7 Initial commit';
    }
    if (command.startsWith('git branch')) {
      return '* ${project.branch}\n  main';
    }
    if (command.contains('test')) {
      final passed = 20 + _random.nextInt(80);
      return '> $command\n\n'
          'Running tests in ${project.path}...\n'
          '✓ $passed passed\n'
          '✗ 0 failed\n\n'
          'Done in ${(2 + _random.nextDouble() * 20).toStringAsFixed(1)}s';
    }
    if (command.startsWith('ls') || command.startsWith('dir')) {
      return 'README.md\nlib\npubspec.yaml\nsrc\ntest';
    }
    return '> $command\n(mock) command executed in ${project.path}';
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';
}
