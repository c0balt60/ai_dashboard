import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:path/path.dart' as p;

import '../runners/agent_runner.dart' show truncate;

/// One notification, ready for a [PushSender].
class PushMessage {
  const PushMessage({
    required this.title,
    required this.body,
    this.tag,
    this.data = const {},
  });

  final String title;
  final String body;

  /// A newer notification with the same tag replaces the older one.
  final String? tag;

  /// Tells the app what to open on tap: `agentId`, `chatId`, `projectId`.
  final Map<String, String> data;
}

abstract interface class PushSender {
  /// Delivers [message] to the device with [token]. Returns false when the
  /// token is no longer registered, so the device can be forgotten; throws a
  /// [PushException] for any other failure.
  Future<bool> send(String token, PushMessage message);

  void close();
}

class PushException implements Exception {
  PushException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Watches a backend and pushes agent updates to the registered phones.
///
/// Works on snapshots alone, so it serves real and simulated agents alike.
/// Changes to one agent are gathered for [settle] before anything is sent,
/// because a finished turn arrives as several snapshots (the task, then the
/// agent) and may be followed right away by the next queued task. Each device
/// then gets at most one notification per agent: the most important event it
/// asked for, in [PushEvent] order.
class PushNotifier {
  PushNotifier(
    this.backend, {
    required String dataDir,
    this.sender,
    this.settle = const Duration(seconds: 3),
    void Function(String message)? log,
  }) : _file = File(p.join(dataDir, 'push.json')),
       _log = log ?? ((_) {}) {
    _loadDevices();
    _subscriptions = [
      backend.watchAgents().listen(_onAgents),
      backend.watchTasks().listen(_onTasks),
      backend.watchProjects().listen(
        (projects) => _projectNames = {for (final p in projects) p.id: p.name},
      ),
    ];
  }

  final AgentBackend backend;

  /// Null when the PC has no Firebase credentials: devices still register,
  /// but nothing is sent.
  final PushSender? sender;
  final Duration settle;
  final File _file;
  final void Function(String) _log;

  final _devices = <String, PushDevice>{};
  late final List<StreamSubscription<Object?>> _subscriptions;
  Map<String, Agent>? _agents;
  Map<String, AgentTask>? _tasks;
  var _projectNames = <String, String>{};
  final _pending = <String, _Pending>{};
  var _disposed = false;

  bool get canSend => sender != null;

  Iterable<PushDevice> get devices => _devices.values;

  /// Adds or updates [device], or forgets it when it wants no events.
  void register(PushDevice device) {
    if (device.token.isEmpty) throw ArgumentError('Missing device token');
    if (device.events.isEmpty) {
      if (_devices.remove(device.token) == null) return;
    } else {
      _devices[device.token] = device;
    }
    _saveDevices();
  }

  Future<void> sendTest(String token) async {
    final sender = this.sender;
    if (sender == null) throw PushException(notConfiguredMessage);
    final ok = await sender.send(
      token,
      const PushMessage(
        title: 'Notifications work',
        body: 'Your PC can reach this phone.',
        tag: 'test',
      ),
    );
    if (!ok) throw PushException('This phone is no longer registered with FCM');
  }

  static const notConfiguredMessage =
      "The PC can't send notifications yet. Set firebaseServiceAccount in "
      "the server's config.json.";

  void _onAgents(List<Agent> agents) {
    final previous = _agents;
    _agents = {for (final a in agents) a.id: a};
    if (previous == null) return;
    for (final agent in agents) {
      final before = previous[agent.id];
      if (before == null ||
          before.status != AgentStatus.running ||
          agent.status == AgentStatus.running) {
        continue;
      }
      _update(agent.id, (p) {
        p.turnEnded = true;
        p.taskTurn |= before.currentTaskId != null;
        if (agent.status == AgentStatus.failed) p.error = agent.activity;
      });
    }
  }

  /// Only tasks an agent was working on count, so moving a task by hand in
  /// the app doesn't notify.
  void _onTasks(List<AgentTask> tasks) {
    final previous = _tasks;
    _tasks = {for (final t in tasks) t.id: t};
    if (previous == null) return;
    for (final task in tasks) {
      final before = previous[task.id];
      final finished =
          task.state == TaskState.completed || task.state == TaskState.failed;
      if (before?.state != TaskState.active || !finished) continue;
      final key = task.agentId ?? before?.agentId ?? 'task:${task.id}';
      _update(key, (p) => p.task = task);
    }
  }

  void _update(String key, void Function(_Pending) change) {
    final pending = _pending.putIfAbsent(key, _Pending.new);
    change(pending);
    pending.timer?.cancel();
    pending.timer = Timer(settle, () => _flush(key));
  }

  Future<void> _flush(String key) async {
    final pending = _pending.remove(key);
    if (pending == null || _disposed) return;
    final wanted = {for (final d in _devices.values) ...d.events};
    if (sender == null || wanted.isEmpty) return;

    final agent = _agents?[key];
    final candidates = <PushEvent, PushMessage>{};
    if (pending.task case final task?) {
      final failed = task.state == TaskState.failed;
      candidates[failed ? PushEvent.failed : PushEvent.completed] =
          _taskMessage(task, agent, failed: failed);
    }
    if (agent != null) {
      if (pending.error case final error? when !pending.taskTurn) {
        candidates.putIfAbsent(
          PushEvent.failed,
          () => PushMessage(
            title: '${agent.name} ran into an error',
            body: truncate(error, 200),
            tag: agent.id,
            data: {'agentId': agent.id},
          ),
        );
      }
      if (pending.turnEnded &&
          !pending.taskTurn &&
          pending.error == null &&
          wanted.contains(PushEvent.replied)) {
        if (await _replyMessage(agent) case final reply?) {
          candidates[PushEvent.replied] = reply;
        }
      }
      final current = _agents?[key] ?? agent;
      if (current.status != AgentStatus.running) {
        candidates[PushEvent.waiting] = PushMessage(
          title: '${agent.name} is waiting for you',
          body: truncate(current.activity, 200),
          tag: agent.id,
          data: {'agentId': agent.id},
        );
      }
    }
    if (candidates.isEmpty) return;

    for (final device in [..._devices.values]) {
      final event = PushEvent.values
          .where((e) => device.events.contains(e) && candidates.containsKey(e))
          .firstOrNull;
      if (event != null) await _send(device, candidates[event]!);
    }
  }

  PushMessage _taskMessage(
    AgentTask task,
    Agent? agent, {
    required bool failed,
  }) {
    final who = agent?.name ?? 'An agent';
    final where = _projectNames[task.projectId] ?? task.projectId;
    return PushMessage(
      title: failed ? '$who failed a task' : '$who finished a task',
      body: truncate('${task.title} · $where', 200),
      tag: task.id,
      data: {'projectId': task.projectId, 'agentId': ?task.agentId},
    );
  }

  /// The last answer in the agent's most recently active chat.
  Future<PushMessage?> _replyMessage(Agent agent) async {
    final chats = await backend.watchChats().first;
    final chat = chats
        .where((c) => c.agentId == agent.id)
        .fold<AgentChat?>(
          null,
          (latest, c) => latest == null || c.updatedAt.isAfter(latest.updatedAt)
              ? c
              : latest,
        );
    if (chat == null) return null;
    final messages = await backend.watchMessages(chat.id).first;
    final reply = messages.where((m) => m.role == MessageRole.agent).lastOrNull;
    if (reply == null) return null;
    return PushMessage(
      title: chat.isDefault
          ? agent.name
          : '${agent.name} · ${chat.displayTitle}',
      body: truncate(reply.text, 200),
      tag: chat.id,
      data: {'agentId': agent.id, 'chatId': chat.id},
    );
  }

  Future<void> _send(PushDevice device, PushMessage message) async {
    try {
      if (!await sender!.send(device.token, message)) {
        _log('Push: forgetting a device that is no longer registered');
        register(PushDevice(token: device.token, events: const {}));
      }
    } on Object catch (e) {
      _log('Push failed: $e');
    }
  }

  void _loadDevices() {
    if (!_file.existsSync()) return;
    try {
      final json = jsonDecode(_file.readAsStringSync()) as Json;
      for (final e in json['devices'] as List? ?? const []) {
        final device = PushDevice.fromJson(e as Json);
        _devices[device.token] = device;
      }
    } on Object catch (e) {
      _log('Push: ignoring unreadable ${_file.path}: $e');
    }
  }

  void _saveDevices() {
    _file.parent.createSync(recursive: true);
    _file.writeAsStringSync(
      jsonEncode({
        'devices': [for (final d in _devices.values) d.toJson()],
      }),
    );
  }

  void dispose() {
    _disposed = true;
    for (final s in _subscriptions) {
      s.cancel();
    }
    for (final p in _pending.values) {
      p.timer?.cancel();
    }
    _pending.clear();
    sender?.close();
  }
}

/// What happened to one agent since its last notification.
class _Pending {
  AgentTask? task;
  var turnEnded = false;
  var taskTurn = false;
  String? error;
  Timer? timer;
}
