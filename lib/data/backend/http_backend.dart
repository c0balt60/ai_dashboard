import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:agent_core/agent_core.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'socket_connect.dart';

enum ConnectionStatus { connecting, connected, offline }

/// A failed request to the PC server.
class BackendException implements Exception {
  BackendException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// [AgentBackend] that talks to the PC server (see `server/`) over HTTP and a
/// single WebSocket.
///
/// Each `watch*` stream subscribes to a topic on the shared socket. The last
/// snapshot per topic is replayed to new listeners, and after a dropped
/// connection the socket reconnects with exponential backoff (1s up to 30s)
/// and re-subscribes to every topic still being watched.
class HttpAgentBackend implements AgentBackend {
  HttpAgentBackend({
    required this.baseUrl,
    required this.token,
    http.Client? client,
    WebSocketChannel Function(Uri uri)? connect,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _connectSocket = connect ?? connectSocket {
    _connect();
  }

  final Uri baseUrl;
  final String token;
  final Duration requestTimeout;
  final http.Client _client;
  final WebSocketChannel Function(Uri uri) _connectSocket;

  final _topics = <String, _Topic>{};
  final _status = StreamController<ConnectionStatus>.broadcast();
  var _currentStatus = ConnectionStatus.connecting;
  WebSocketChannel? _channel;
  Timer? _retry;
  var _attempt = 0;
  var _disposed = false;

  ConnectionStatus get status => _currentStatus;

  /// The current status, then every change.
  Stream<ConnectionStatus> get connection async* {
    yield _currentStatus;
    yield* _status.stream;
  }

  void _setStatus(ConnectionStatus value) {
    if (_currentStatus == value || _disposed) return;
    _currentStatus = value;
    _status.add(value);
  }

  Uri get _socketUri => baseUrl.replace(
    scheme: baseUrl.scheme == 'https' ? 'wss' : 'ws',
    path: ApiPaths.ws,
    queryParameters: {ApiPaths.tokenQuery: token},
  );

  Future<void> _connect() async {
    if (_disposed) return;
    _setStatus(ConnectionStatus.connecting);
    final WebSocketChannel channel;
    try {
      channel = _connectSocket(_socketUri);
      await channel.ready.timeout(requestTimeout);
    } catch (_) {
      _scheduleReconnect(await _diagnose());
      return;
    }
    if (_disposed) {
      channel.sink.close();
      return;
    }
    _channel = channel;
    _attempt = 0;
    _setStatus(ConnectionStatus.connected);
    for (final topic in _topics.keys) {
      _send(SubscribeFrame(topic));
    }
    channel.stream.listen(
      _onMessage,
      onError: (Object _) => _onClosed(channel),
      onDone: () => _onClosed(channel),
      cancelOnError: true,
    );
  }

  void _onClosed(WebSocketChannel channel) {
    if (!identical(_channel, channel)) return;
    _channel = null;
    _scheduleReconnect(BackendException('Lost the connection to the PC'));
  }

  /// Browsers don't expose why a WebSocket failed, so ask over HTTP to tell
  /// a wrong token apart from an unreachable PC.
  Future<BackendException> _diagnose() async {
    try {
      await _request('GET', ApiPaths.ping);
      return BackendException("Can't open the live connection to the PC");
    } on BackendException catch (e) {
      return e.statusCode == 401
          ? BackendException(
              'Wrong or missing access token. Set it in Settings.',
              statusCode: 401,
            )
          : e;
    }
  }

  void _scheduleReconnect(BackendException reason) {
    if (_disposed) return;
    _setStatus(ConnectionStatus.offline);
    for (final t in _topics.values) {
      if (t.last == null) t.addError(reason);
    }
    final delay = Duration(seconds: min(30, 1 << min(_attempt++, 5)));
    _retry?.cancel();
    _retry = Timer(delay, _connect);
  }

  void _onMessage(Object? raw) {
    final Frame frame;
    try {
      frame = Frame.fromJson(jsonDecode(raw as String) as Json);
    } on Object {
      return;
    }
    switch (frame) {
      case SnapshotFrame(:final topic, :final data):
        _topics[topic]?.add(data);
      case ErrorFrame(:final topic?, :final message):
        _topics[topic]?.addError(BackendException(message));
      case _:
        break;
    }
  }

  void _send(Frame frame) => _channel?.sink.add(jsonEncode(frame.toJson()));

  Stream<List<T>> _watch<T>(String topic, T Function(Json) fromJson) {
    final raw = Stream<List<Json>>.multi((listener) {
      final t = _topics.putIfAbsent(topic, _Topic.new);
      t.listeners.add(listener);
      if (t.last case final last?) listener.add(last);
      if (t.listeners.length == 1) _send(SubscribeFrame(topic));
      listener.onCancel = () {
        t.listeners.remove(listener);
        if (t.listeners.isEmpty && identical(_topics[topic], t)) {
          _topics.remove(topic);
          _send(UnsubscribeFrame(topic));
        }
      };
    });
    return raw.map((list) => List.unmodifiable(list.map(fromJson)));
  }

  Future<Json> _request(
    String method,
    String path, {
    Object? body,
    Duration? timeout,
  }) async {
    final request = http.Request(method, baseUrl.replace(path: path))
      ..headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout ?? requestTimeout),
      ).timeout(timeout ?? requestTimeout);
    } on TimeoutException {
      throw BackendException('The PC took too long to answer');
    } on Exception catch (e) {
      throw BackendException("Can't reach the PC: $e");
    }

    final decoded = response.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(response.body);
    if (response.statusCode != 200) {
      final error = decoded is Map ? decoded['error'] : null;
      throw BackendException(
        error is String ? error : 'The PC answered ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    return decoded as Json;
  }

  @override
  Stream<List<Agent>> watchAgents() => _watch(Topics.agents, Agent.fromJson);

  @override
  Stream<List<Project>> watchProjects() =>
      _watch(Topics.projects, Project.fromJson);

  @override
  Stream<List<AgentTask>> watchTasks() =>
      _watch(Topics.tasks, AgentTask.fromJson);

  @override
  Stream<List<AgentChat>> watchChats() =>
      _watch(Topics.chats, AgentChat.fromJson);

  @override
  Stream<List<ChatMessage>> watchMessages(String chatId) =>
      _watch(Topics.messages(chatId), ChatMessage.fromJson);

  @override
  Stream<List<TodoList>> watchTodoLists() =>
      _watch(Topics.todoLists, TodoList.fromJson);

  @override
  Future<void> sendPrompt(String chatId, String text) =>
      _request('POST', ApiPaths.prompt(chatId), body: {'text': text});

  @override
  Future<AgentChat> createChat(
    String agentId, {
    String? projectId,
    String title = '',
  }) async => AgentChat.fromJson(
    await _request(
      'POST',
      ApiPaths.chats,
      body: {'agentId': agentId, 'projectId': ?projectId, 'title': title},
    ),
  );

  @override
  Future<void> renameChat(String chatId, String title) =>
      _request('PATCH', ApiPaths.chat(chatId), body: {'title': title});

  @override
  Future<void> deleteChat(String chatId) =>
      _request('DELETE', ApiPaths.chat(chatId));

  @override
  Future<void> setAgentProjects(String agentId, List<String> projectIds) =>
      _request(
        'PUT',
        ApiPaths.agentProjects(agentId),
        body: {'projectIds': projectIds},
      );

  @override
  Future<void> assignAgent(
    String agentId, {
    required String projectId,
    required String workingDir,
    String? taskId,
  }) => _request(
    'POST',
    ApiPaths.assign(agentId),
    body: {'projectId': projectId, 'workingDir': workingDir, 'taskId': ?taskId},
  );

  @override
  Future<void> stopAgent(String agentId) =>
      _request('POST', ApiPaths.stop(agentId));

  @override
  Future<void> clearMessages(String chatId) =>
      _request('DELETE', ApiPaths.clearMessages(chatId));

  @override
  Future<AgentTask> createTask(
    String title,
    String projectId, {
    String? agentId,
    String description = '',
    TodoLink? todo,
  }) async => AgentTask.fromJson(
    await _request(
      'POST',
      ApiPaths.tasks,
      body: {
        'title': title,
        'projectId': projectId,
        'agentId': ?agentId,
        if (description.isNotEmpty) 'description': description,
        if (todo != null) 'todo': todo.toJson(),
      },
    ),
  );

  @override
  Future<void> updateTaskState(String taskId, TaskState state) =>
      _request('PUT', ApiPaths.taskState(taskId), body: {'state': state.name});

  @override
  Future<TodoList> createTodoList(String title) async => TodoList.fromJson(
    await _request('POST', ApiPaths.todoLists, body: {'title': title}),
  );

  @override
  Future<void> renameTodoList(String listId, String title) =>
      _request('PATCH', ApiPaths.todoList(listId), body: {'title': title});

  @override
  Future<void> deleteTodoList(String listId) =>
      _request('DELETE', ApiPaths.todoList(listId));

  @override
  Future<TodoItem> addTodoItem(
    String listId, {
    required String title,
    String note = '',
    List<String> projectIds = const [],
    List<String> agentIds = const [],
    DateTime? startDate,
    DateTime? dueDate,
  }) async => TodoItem.fromJson(
    await _request(
      'POST',
      ApiPaths.todoItems(listId),
      body: {
        'title': title,
        'note': note,
        'projectIds': projectIds,
        'agentIds': agentIds,
        if (startDate != null) 'startDate': encodeDay(startDate),
        if (dueDate != null) 'dueDate': encodeDay(dueDate),
      },
    ),
  );

  @override
  Future<void> updateTodoItem(String listId, TodoItem item) =>
      _request('PUT', ApiPaths.todoItem(listId, item.id), body: item.toJson());

  @override
  Future<void> deleteTodoItem(String listId, String itemId) =>
      _request('DELETE', ApiPaths.todoItem(listId, itemId));

  /// Waits longer than other requests, since the command may take minutes.
  @override
  Future<String> runCommand(String projectId, String command) async {
    final json = await _request(
      'POST',
      ApiPaths.runCommand(projectId),
      body: {'command': command},
      timeout: const Duration(minutes: 10),
    );
    return json['output'] as String? ?? '';
  }

  @override
  Future<Duration> ping() async {
    final watch = Stopwatch()..start();
    await _request('GET', ApiPaths.ping);
    return watch.elapsed;
  }

  /// Only has an effect when the server runs with `--simulate`.
  @override
  void setSimulationEnabled(bool enabled) {
    _request('POST', ApiPaths.simulation, body: {'enabled': enabled}).ignore();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retry?.cancel();
    _channel?.sink.close();
    _channel = null;
    for (final t in _topics.values) {
      for (final l in [...t.listeners]) {
        l.closeSync();
      }
    }
    _topics.clear();
    _status.close();
    _client.close();
  }
}

/// A subscribed topic: its live listeners and the last snapshot received.
class _Topic {
  final listeners = <MultiStreamController<List<Json>>>[];
  List<Json>? last;

  void add(List<Json> data) {
    last = data;
    for (final l in [...listeners]) {
      l.add(data);
    }
  }

  void addError(Object error) {
    for (final l in [...listeners]) {
      l.addError(error);
    }
  }
}
