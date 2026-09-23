import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:agent_core/agent_core.dart';

import 'config.dart';
import 'process_utils.dart';
import 'runners/agent_runner.dart';
import 'state_store.dart';
import 'test_summary.dart';

/// The real [AgentBackend]: agents are CLI processes on this PC, projects are
/// the folders listed in the config, and everything else lives in a
/// [StateStore] so it survives restarts.
///
/// Each agent runs at most one turn at a time. A task queued for an agent
/// (`waiting`) starts as soon as the agent is free and ends `completed` or
/// `failed` with its turn; after a successful task the project's
/// `testCommand`, if any, records a test run.
class LocalAgentBackend implements AgentBackend {
  LocalAgentBackend(
    this.config, {
    AgentRunner Function(AgentConfig)? runnerFor,
    StateStore? store,
    this._branchOf = gitBranch,
    Duration branchRefresh = const Duration(minutes: 1),
  }) : _store = store ?? StateStore(config.dataDir) {
    final make = runnerFor ?? AgentRunner.forConfig;
    for (final a in config.agents) {
      _runners[a.id] = make(a);
    }
    _restore(_store.load());
    _refreshBranches();
    _branchTimer = Timer.periodic(branchRefresh, (_) => _refreshBranches());
    for (final id in [..._agents.keys]) {
      _startNextTask(id);
    }
  }

  final ServerConfig config;
  final StateStore _store;
  final Future<String> Function(String dir) _branchOf;
  late final Timer _branchTimer;

  final _runners = <String, AgentRunner>{};
  final _projectConfigs = <String, ProjectConfig>{};
  final _projects = <String, Project>{};
  final _agents = <String, Agent>{};
  final _sessions = <String, String>{};
  final _tasks = <String, AgentTask>{};
  final _messages = <String, List<ChatMessage>>{};
  final _todoLists = <String, TodoList>{};
  final _turns = <String, AgentTurn>{};
  final _testing = <String>{};
  final _changes = StreamController<void>.broadcast();
  var _idCounter = 0;
  var _disposed = false;

  static const _maxMessages = 500;
  static const _maxLog = 200;
  static const _maxTestRuns = 50;

  void _restore(Json? saved) {
    final now = DateTime.now();
    _idCounter = saved?['nextId'] as int? ?? 0;

    final savedProjects = saved?['projects'] as Json? ?? const {};
    for (final c in config.projects) {
      _projectConfigs[c.id] = c;
      final old = switch (savedProjects[c.id]) {
        final Json json => Project.fromJson(json),
        _ => null,
      };
      _projects[c.id] = Project(
        id: c.id,
        name: c.name,
        path: c.path,
        branch: old?.branch ?? '',
        lastActivity: old?.lastActivity ?? now,
        testRuns: [
          for (final r in old?.testRuns ?? const <TestRun>[])
            if (r.status != TestStatus.running) r,
        ],
        log: old?.log ?? const [],
      );
    }

    final savedAgents = saved?['agents'] as Json? ?? const {};
    for (final c in config.agents) {
      final old = switch (savedAgents[c.id]) {
        final Json json => Agent.fromJson(json),
        _ => null,
      };
      final projectId = _projects.containsKey(old?.projectId)
          ? old!.projectId
          : c.projectId;
      final interrupted = old?.status == AgentStatus.running;
      _agents[c.id] = Agent(
        id: c.id,
        name: c.name,
        type: c.type,
        status: interrupted
            ? AgentStatus.idle
            : old?.status ?? AgentStatus.idle,
        activity: interrupted
            ? 'Interrupted by a server restart'
            : old?.activity ?? 'Ready',
        lastActive: old?.lastActive ?? now,
        projectId: projectId,
        workingDir: old?.workingDir ?? _projectPath(projectId),
        branch: old?.branch,
        currentTaskId: interrupted ? null : old?.currentTaskId,
      );
    }

    (saved?['sessions'] as Json? ?? const {}).forEach((agentId, session) {
      if (_agents.containsKey(agentId)) _sessions[agentId] = session as String;
    });

    for (final e in saved?['tasks'] as List? ?? const []) {
      final task = AgentTask.fromJson(e as Json);
      _tasks[task.id] = task.state == TaskState.active
          ? task.copyWith(
              state: task.agentId == null
                  ? TaskState.backlog
                  : TaskState.waiting,
              progress: 0,
            )
          : task;
    }

    (saved?['messages'] as Json? ?? const {}).forEach((agentId, list) {
      _messages[agentId] = [
        for (final m in list as List) ChatMessage.fromJson(m as Json),
      ];
    });

    for (final e in saved?['todoLists'] as List? ?? const []) {
      final list = TodoList.fromJson(e as Json);
      _todoLists[list.id] = list;
    }
  }

  Json _snapshot() => {
    'version': 1,
    'nextId': _idCounter,
    'projects': {for (final p in _projects.values) p.id: p.toJson()},
    'agents': {for (final a in _agents.values) a.id: a.toJson()},
    'sessions': _sessions,
    'tasks': [for (final t in _tasks.values) t.toJson()],
    'messages': {
      for (final e in _messages.entries)
        e.key: [for (final m in e.value) m.toJson()],
    },
    'todoLists': [for (final l in _todoLists.values) l.toJson()],
  };

  String _nextId(String prefix) => '$prefix-${++_idCounter}';

  void _notify() {
    if (_disposed) return;
    _changes.add(null);
    _store.save(_snapshot);
  }

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  String? _projectPath(String? projectId) => _projectConfigs[projectId]?.path;

  String? _workingDirOf(Agent agent) =>
      agent.workingDir ?? _projectPath(agent.projectId);

  void _addMessage(String agentId, MessageRole role, String text) {
    final list = _messages.putIfAbsent(agentId, () => []);
    list.add(
      ChatMessage(
        id: _nextId('m'),
        agentId: agentId,
        role: role,
        text: text,
        at: DateTime.now(),
      ),
    );
    if (list.length > _maxMessages) {
      list.removeRange(0, list.length - _maxMessages);
    }
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
    final entry = LogEntry(
      at: now,
      message: message,
      level: level,
      agentId: agentId,
    );
    _projects[projectId] = project.copyWith(
      log: [entry, ...project.log.take(_maxLog - 1)],
      lastActivity: now,
    );
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
  Stream<List<TodoList>> watchTodoLists() =>
      _watch(() => List.unmodifiable(_todoLists.values));

  @override
  Future<void> sendPrompt(String agentId, String text) async {
    final agent = _requireAgent(agentId);
    _addMessage(agentId, MessageRole.user, text);
    if (_turns.containsKey(agentId)) {
      _addMessage(
        agentId,
        MessageRole.system,
        '${agent.name} is still busy. Wait for it or stop it first.',
      );
    } else if (_workingDirOf(agent) case final dir?) {
      _startTurn(agent, text, dir);
    } else {
      _addMessage(
        agentId,
        MessageRole.system,
        'Assign ${agent.name} to a project folder first.',
      );
    }
    _notify();
  }

  @override
  Future<void> assignAgent(
    String agentId, {
    required String projectId,
    required String workingDir,
    String? taskId,
  }) async {
    final agent = _requireAgent(agentId);
    final project = _projects[projectId];
    if (project == null) throw ArgumentError('Unknown project $projectId');
    if (!Directory(workingDir).existsSync()) {
      throw ArgumentError('No such folder on the PC: $workingDir');
    }
    await _interrupt(agentId);

    if (agent.workingDir != workingDir) _sessions.remove(agentId);
    final assigned = _agents[agentId]!.copyWith(
      projectId: () => projectId,
      workingDir: () => workingDir,
      branch: () => project.branch.isEmpty ? null : project.branch,
      status: AgentStatus.waiting,
      activity: 'Waiting for instructions',
      currentTaskId: () => null,
      lastActive: DateTime.now(),
    );
    _agents[agentId] = assigned;

    final task = taskId == null ? null : _tasks[taskId];
    _addMessage(
      agentId,
      MessageRole.system,
      task == null
          ? 'Assigned to $workingDir'
          : 'Assigned to $workingDir · task "${task.title}"',
    );
    _log(projectId, '${agent.name} assigned to $workingDir', agentId: agentId);
    if (task != null) {
      _tasks[task.id] = task.copyWith(agentId: () => agentId);
      _startTask(assigned, _tasks[task.id]!, workingDir);
    }
    _notify();
    _refreshBranches();
  }

  @override
  Future<void> stopAgent(String agentId) async {
    final agent = _requireAgent(agentId);
    await _interrupt(agentId, requeueAs: TaskState.backlog);
    _agents[agentId] = _agents[agentId]!.copyWith(
      status: AgentStatus.idle,
      activity: 'Stopped by user',
      currentTaskId: () => null,
      lastActive: DateTime.now(),
    );
    _addMessage(agentId, MessageRole.system, 'Stopped by user');
    if (agent.projectId case final projectId?) {
      _log(
        projectId,
        '${agent.name} stopped by user',
        agentId: agentId,
        level: LogLevel.warning,
      );
    }
    _notify();
  }

  /// Starting a fresh chat also starts a fresh CLI conversation.
  @override
  Future<void> clearMessages(String agentId) async {
    _messages[agentId] = [];
    _sessions.remove(agentId);
    _notify();
  }

  @override
  Future<AgentTask> createTask(
    String title,
    String projectId, {
    String? agentId,
  }) async {
    if (!_projects.containsKey(projectId)) {
      throw ArgumentError('Unknown project $projectId');
    }
    if (agentId != null) _requireAgent(agentId);
    final now = DateTime.now();
    final task = AgentTask(
      id: _nextId('t'),
      title: title,
      projectId: projectId,
      agentId: agentId,
      state: agentId == null ? TaskState.backlog : TaskState.waiting,
      createdAt: now,
      updatedAt: now,
    );
    _tasks[task.id] = task;
    _log(projectId, 'Task created: $title', agentId: agentId);
    _notify();
    if (agentId != null) _startNextTask(agentId);
    return task;
  }

  @override
  Future<void> updateTaskState(String taskId, TaskState state) async {
    final task = _tasks[taskId];
    if (task == null) return;
    final now = DateTime.now();
    final done = state == TaskState.completed || state == TaskState.failed;
    final agent = task.agentId == null ? null : _agents[task.agentId];
    final isCurrent = agent != null && agent.currentTaskId == taskId;

    if (isCurrent && state != TaskState.active) {
      _turns.remove(agent.id)?.cancel();
    }
    _tasks[taskId] = task.copyWith(
      state: state,
      agentId: state == TaskState.backlog ? () => null : null,
      progress: state == TaskState.completed ? 1 : null,
      updatedAt: now,
      completedAt: () => done ? now : null,
    );
    if (isCurrent && state != TaskState.active) {
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

    if (agent == null || _turns.containsKey(agent.id)) return;
    if (state == TaskState.active) {
      final dir = agent.projectId == task.projectId
          ? _workingDirOf(agent)
          : _projectPath(task.projectId);
      if (dir != null) _startTask(_agents[agent.id]!, _tasks[taskId]!, dir);
      _notify();
    } else if (state == TaskState.waiting) {
      _startNextTask(agent.id);
    }
  }

  @override
  Future<TodoList> createTodoList(String title) async {
    final now = DateTime.now();
    final list = TodoList(
      id: _nextId('l'),
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    _todoLists[list.id] = list;
    _notify();
    return list;
  }

  @override
  Future<void> renameTodoList(String listId, String title) async {
    final list = _todoLists[listId];
    if (list == null) return;
    _todoLists[listId] = list.copyWith(title: title, updatedAt: DateTime.now());
    _notify();
  }

  @override
  Future<void> deleteTodoList(String listId) async {
    if (_todoLists.remove(listId) != null) _notify();
  }

  @override
  Future<TodoItem> addTodoItem(
    String listId, {
    required String title,
    String note = '',
    List<String> projectIds = const [],
    List<String> agentIds = const [],
    DateTime? startDate,
    DateTime? dueDate,
  }) async {
    final now = DateTime.now();
    final item = TodoItem(
      id: _nextId('i'),
      title: title,
      note: note,
      projectIds: List.unmodifiable(projectIds),
      agentIds: List.unmodifiable(agentIds),
      startDate: startDate,
      dueDate: dueDate,
      createdAt: now,
    );
    final list = _todoLists[listId];
    if (list == null) throw ArgumentError('Unknown to-do list $listId');
    _todoLists[listId] = list.copyWith(
      items: [...list.items, item],
      updatedAt: now,
    );
    _notify();
    return item;
  }

  @override
  Future<void> updateTodoItem(String listId, TodoItem item) async {
    final list = _todoLists[listId];
    final previous = list?.items.where((i) => i.id == item.id).firstOrNull;
    if (list == null || previous == null) return;
    final now = DateTime.now();
    final updated = item.done == previous.done
        ? item
        : item.copyWith(completedAt: () => item.done ? now : null);
    _todoLists[listId] = list.copyWith(
      items: [for (final i in list.items) i.id == item.id ? updated : i],
      updatedAt: now,
    );
    _notify();
  }

  @override
  Future<void> deleteTodoItem(String listId, String itemId) async {
    final list = _todoLists[listId];
    if (list == null) return;
    _todoLists[listId] = list.copyWith(
      items: list.items.where((i) => i.id != itemId).toList(),
      updatedAt: DateTime.now(),
    );
    _notify();
  }

  @override
  Future<String> runCommand(String projectId, String command) async {
    final project = _projectConfigs[projectId];
    if (project == null) return 'error: unknown project $projectId';
    final line = command.trim();
    _log(projectId, '\$ $line');
    _notify();

    final ShellResult result;
    try {
      result = await runShell(
        line,
        workingDir: project.path,
        timeout: config.commandTimeout,
        shell: config.shell,
      );
    } on ProcessException catch (e) {
      _log(projectId, 'Command failed: ${e.message}', level: LogLevel.error);
      _notify();
      return 'error: ${e.message}';
    }

    if (result.timedOut) {
      _log(projectId, 'Command timed out: $line', level: LogLevel.warning);
    } else if (result.exitCode != 0) {
      _log(
        projectId,
        'Command exited with ${result.exitCode}: $line',
        level: LogLevel.warning,
      );
    }
    _notify();
    _refreshBranches();
    return [
      result.output.trimRight(),
      if (result.timedOut)
        '[timed out after ${config.commandTimeout.inSeconds}s]'
      else if (result.exitCode != 0)
        '[exit code ${result.exitCode}]',
    ].where((s) => s.isNotEmpty).join('\n');
  }

  @override
  Future<Duration> ping() async => Duration.zero;

  /// Real agents can't be simulated; the switch only affects the mock.
  @override
  void setSimulationEnabled(bool enabled) {}

  @override
  void dispose() {
    if (_disposed) return;
    _branchTimer.cancel();
    for (final turn in _turns.values) {
      turn.cancel();
    }
    _turns.clear();
    _store
      ..save(_snapshot)
      ..flush();
    _disposed = true;
    _changes.close();
  }

  Agent _requireAgent(String agentId) =>
      _agents[agentId] ?? (throw ArgumentError('Unknown agent $agentId'));

  void _startTurn(Agent agent, String prompt, String dir, {AgentTask? task}) {
    final now = DateTime.now();
    final turn = _runners[agent.id]!.start(
      prompt: prompt,
      workingDir: dir,
      sessionId: _sessions[agent.id],
    );
    _turns[agent.id] = turn;
    _agents[agent.id] = agent.copyWith(
      status: AgentStatus.running,
      activity: task == null
          ? 'Thinking about: ${truncate(prompt, 40)}'
          : 'Starting "${truncate(task.title, 40)}"',
      currentTaskId: () => task?.id,
      lastActive: now,
    );
    if (task != null) {
      _tasks[task.id] = task.copyWith(
        state: TaskState.active,
        agentId: () => agent.id,
        progress: 0.05,
        updatedAt: now,
        completedAt: () => null,
      );
    }
    turn.events.listen(
      (event) => _onEvent(agent.id, turn, task?.id, event),
      onError: (Object e) => _onEvent(
        agent.id,
        turn,
        task?.id,
        FinishedEvent(success: false, error: '$e'),
      ),
    );
  }

  /// Applies a runner event, ignoring turns that were stopped or replaced.
  void _onEvent(
    String agentId,
    AgentTurn turn,
    String? taskId,
    RunnerEvent event,
  ) {
    final agent = _agents[agentId];
    if (agent == null || _disposed || !identical(_turns[agentId], turn)) {
      return;
    }
    final now = DateTime.now();
    final task = taskId == null ? null : _tasks[taskId];

    switch (event) {
      case SessionEvent(:final sessionId):
        _sessions[agentId] = sessionId;
      case ActivityEvent(:final activity):
        _agents[agentId] = agent.copyWith(activity: activity, lastActive: now);
        if (task != null && task.steps.isEmpty) {
          _tasks[task.id] = task.copyWith(
            progress: min(0.9, task.progress + 0.02),
            updatedAt: now,
          );
        }
      case ReplyEvent(:final text):
        _addMessage(agentId, MessageRole.agent, text);
        _agents[agentId] = agent.copyWith(lastActive: now);
      case StepsEvent(:final steps):
        if (task != null && steps.isNotEmpty) {
          final done = steps.where((s) => s.done).length;
          _tasks[task.id] = task.copyWith(
            steps: steps,
            progress: max(0.05, 0.95 * done / steps.length),
            updatedAt: now,
          );
        }
      case FinishedEvent():
        _finishTurn(agent, task, event);
    }
    _notify();
  }

  void _finishTurn(Agent agent, AgentTask? task, FinishedEvent event) {
    _turns.remove(agent.id);
    final now = DateTime.now();
    final ok = event.success;
    final error = event.error ?? 'unknown error';
    if (!ok) {
      _addMessage(agent.id, MessageRole.system, 'Failed: $error');
      // A broken session would fail every later turn too.
      _sessions.remove(agent.id);
    }

    if (task != null) {
      _tasks[task.id] = task.copyWith(
        state: ok ? TaskState.completed : TaskState.failed,
        progress: ok ? 1 : null,
        updatedAt: now,
        completedAt: () => now,
      );
      _log(
        task.projectId,
        '${ok ? 'Completed' : 'Failed'}: ${task.title}',
        agentId: agent.id,
        level: ok ? LogLevel.success : LogLevel.error,
      );
    }

    _agents[agent.id] = agent.copyWith(
      status: switch ((ok, task)) {
        (false, _) => AgentStatus.failed,
        (true, null) => AgentStatus.waiting,
        (true, _) => AgentStatus.completed,
      },
      activity: !ok
          ? 'Failed: ${truncate(error, 60)}'
          : task == null
          ? 'Waiting for your next instruction'
          : 'Finished "${truncate(task.title, 40)}"',
      currentTaskId: () => null,
      lastActive: now,
    );

    if (ok && task != null) _runTests(task.projectId, agent.id);
    _refreshBranches();
    scheduleMicrotask(() => _startNextTask(agent.id));
  }

  /// Cancels the agent's running turn, putting its task back as [requeueAs].
  Future<void> _interrupt(
    String agentId, {
    TaskState requeueAs = TaskState.waiting,
  }) async {
    final turn = _turns.remove(agentId);
    if (turn == null) return;
    final taskId = _agents[agentId]?.currentTaskId;
    if (_tasks[taskId] case final task?) {
      _tasks[task.id] = task.copyWith(
        state: requeueAs,
        agentId: requeueAs == TaskState.backlog ? () => null : null,
        progress: 0,
        updatedAt: DateTime.now(),
      );
    }
    await turn.cancel();
  }

  /// Starts the oldest task queued for [agentId] if the agent is free.
  void _startNextTask(String agentId) {
    final agent = _agents[agentId];
    if (agent == null || _disposed || _turns.containsKey(agentId)) return;
    AgentTask? next;
    for (final t in _tasks.values) {
      if (t.agentId == agentId &&
          t.state == TaskState.waiting &&
          (next == null || t.createdAt.isBefore(next.createdAt))) {
        next = t;
      }
    }
    if (next == null) return;
    final dir = agent.projectId == next.projectId
        ? _workingDirOf(agent)
        : _projectPath(next.projectId);
    if (dir == null) return;
    _startTask(agent, next, dir);
    _notify();
  }

  void _startTask(Agent agent, AgentTask task, String dir) {
    var current = agent;
    if (agent.projectId != task.projectId || agent.workingDir != dir) {
      _sessions.remove(agent.id);
      final branch = _projects[task.projectId]?.branch ?? '';
      current = agent.copyWith(
        projectId: () => task.projectId,
        workingDir: () => dir,
        branch: () => branch.isEmpty ? null : branch,
      );
    }
    _addMessage(agent.id, MessageRole.system, 'Starting task "${task.title}"');
    _startTurn(
      current,
      'Task: ${task.title}\n\n'
      'Work on this in the current project. When you are done, summarize '
      'what you changed.',
      dir,
      task: task,
    );
  }

  Future<void> _runTests(String projectId, String? agentId) async {
    final project = _projectConfigs[projectId];
    final command = project?.testCommand;
    if (project == null || command == null || !_testing.add(projectId)) return;

    final id = _nextId('r');
    final started = DateTime.now();
    final suite = truncate(command.split(RegExp(r'[\\/]')).last, 40);
    void put(TestRun run) {
      final p = _projects[projectId]!;
      _projects[projectId] = p.copyWith(
        testRuns: [
          run,
          ...p.testRuns.where((r) => r.id != run.id).take(_maxTestRuns - 1),
        ],
      );
    }

    TestRun run(TestStatus status, {TestSummary? summary}) => TestRun(
      id: id,
      suite: suite,
      status: status,
      passed: summary?.passed ?? 0,
      failed: summary?.failed ?? 0,
      failingTests: summary?.failing ?? const [],
      duration: DateTime.now().difference(started),
      at: started,
      agentId: agentId,
    );

    put(run(TestStatus.running));
    _notify();
    try {
      final result = await runShell(
        command,
        workingDir: project.path,
        timeout: const Duration(minutes: 30),
        shell: config.shell,
      );
      final summary = parseTestSummary(result.output);
      final passed = result.exitCode == 0 && !result.timedOut;
      put(
        run(passed ? TestStatus.passed : TestStatus.failed, summary: summary),
      );
      _log(
        projectId,
        passed
            ? 'Tests passed (${summary.passed})'
            : 'Tests failed (${summary.failed} failing)',
        agentId: agentId,
        level: passed ? LogLevel.success : LogLevel.error,
      );
    } on Exception catch (e) {
      put(run(TestStatus.failed));
      _log(projectId, 'Could not run tests: $e', level: LogLevel.error);
    } finally {
      _testing.remove(projectId);
      _notify();
    }
  }

  Future<void> _refreshBranches() async {
    var changed = false;
    for (final c in _projectConfigs.values) {
      final branch = await _branchOf(c.path);
      final project = _projects[c.id];
      if (_disposed || project == null) return;
      if (project.branch != branch) {
        _projects[c.id] = project.copyWith(branch: branch);
        changed = true;
      }
    }
    for (final id in [..._agents.keys]) {
      final dir = _workingDirOf(_agents[id]!);
      if (dir == null) continue;
      final branch = await _branchOf(dir);
      final agent = _agents[id];
      if (_disposed || agent == null) return;
      final value = branch.isEmpty ? null : branch;
      if (agent.branch != value) {
        _agents[id] = agent.copyWith(branch: () => value);
        changed = true;
      }
    }
    if (changed) _notify();
  }
}
