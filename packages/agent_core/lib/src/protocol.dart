/// Wire format between the PC server and the app's HTTP backend.
///
/// Streams travel over one WebSocket at [ApiPaths.ws]: the client sends
/// [SubscribeFrame]s and the server answers each with a [SnapshotFrame] right
/// away and again on every change, mirroring the `watch*` contract of
/// [AgentBackend]. Actions are JSON requests to the other [ApiPaths]. Every
/// request carries `Authorization: Bearer <token>`; the WebSocket passes the
/// token as the [ApiPaths.tokenQuery] query parameter instead, because
/// browsers can't set headers on it.
library;

import 'backend/agent_backend.dart';
import 'models/models.dart';

abstract final class ApiPaths {
  static const tokenQuery = 'token';

  static const ping = '/api/ping';
  static const ws = '/api/ws';
  static const simulation = '/api/simulation';

  static String assign(String agentId) => '/api/agents/$agentId/assign';
  static String agentProjects(String agentId) =>
      '/api/agents/$agentId/projects';
  static String stop(String agentId) => '/api/agents/$agentId/stop';

  static const chats = '/api/chats';
  static String chat(String chatId) => '/api/chats/$chatId';
  static String prompt(String chatId) => '/api/chats/$chatId/prompt';
  static String clearMessages(String chatId) => '/api/chats/$chatId/messages';

  static const tasks = '/api/tasks';
  static String taskState(String taskId) => '/api/tasks/$taskId/state';

  static const todoLists = '/api/todo-lists';
  static String todoList(String listId) => '/api/todo-lists/$listId';
  static String todoItems(String listId) => '/api/todo-lists/$listId/items';
  static String todoItem(String listId, String itemId) =>
      '/api/todo-lists/$listId/items/$itemId';

  static String runCommand(String projectId) =>
      '/api/projects/$projectId/commands';

  /// Registers a [PushDevice]; an empty event set unregisters it. Tokens
  /// travel in the body so they never reach the request log.
  static const pushDevice = '/api/push/device';
  static const pushTest = '/api/push/test';
}

/// Names of the streams a client can subscribe to.
abstract final class Topics {
  static const agents = 'agents';
  static const projects = 'projects';
  static const tasks = 'tasks';
  static const todoLists = 'todoLists';
  static const chats = 'chats';
  static const _messagesPrefix = 'messages:';

  static String messages(String chatId) => '$_messagesPrefix$chatId';

  /// The chat id of a [messages] topic, or null for any other topic.
  static String? messagesChat(String topic) =>
      topic.startsWith(_messagesPrefix)
      ? topic.substring(_messagesPrefix.length)
      : null;
}

/// Streams [topic] from [backend] as JSON-ready lists, or returns null for an
/// unknown topic.
Stream<List<Json>>? watchTopicJson(AgentBackend backend, String topic) {
  List<Json> encode<T>(List<T> items, Json Function(T) toJson) => [
    for (final i in items) toJson(i),
  ];
  return switch (topic) {
    Topics.agents => backend.watchAgents().map(
      (l) => encode(l, (a) => a.toJson()),
    ),
    Topics.projects => backend.watchProjects().map(
      (l) => encode(l, (p) => p.toJson()),
    ),
    Topics.tasks => backend.watchTasks().map(
      (l) => encode(l, (t) => t.toJson()),
    ),
    Topics.todoLists => backend.watchTodoLists().map(
      (l) => encode(l, (t) => t.toJson()),
    ),
    Topics.chats => backend.watchChats().map(
      (l) => encode(l, (c) => c.toJson()),
    ),
    _ => switch (Topics.messagesChat(topic)) {
      final chatId? =>
        backend.watchMessages(chatId).map((l) => encode(l, (m) => m.toJson())),
      null => null,
    },
  };
}

sealed class Frame {
  const Frame();

  factory Frame.fromJson(Json json) => switch (json['type']) {
    'subscribe' => SubscribeFrame(json['topic'] as String),
    'unsubscribe' => UnsubscribeFrame(json['topic'] as String),
    'snapshot' => SnapshotFrame(json['topic'] as String, [
      for (final e in json['data'] as List) e as Json,
    ]),
    'error' => ErrorFrame(
      json['message'] as String,
      topic: json['topic'] as String?,
    ),
    final type => throw FormatException('Unknown frame type: $type'),
  };

  Json toJson();
}

final class SubscribeFrame extends Frame {
  const SubscribeFrame(this.topic);

  final String topic;

  @override
  Json toJson() => {'type': 'subscribe', 'topic': topic};
}

final class UnsubscribeFrame extends Frame {
  const UnsubscribeFrame(this.topic);

  final String topic;

  @override
  Json toJson() => {'type': 'unsubscribe', 'topic': topic};
}

final class SnapshotFrame extends Frame {
  const SnapshotFrame(this.topic, this.data);

  final String topic;
  final List<Json> data;

  @override
  Json toJson() => {'type': 'snapshot', 'topic': topic, 'data': data};
}

final class ErrorFrame extends Frame {
  const ErrorFrame(this.message, {this.topic});

  final String message;
  final String? topic;

  @override
  Json toJson() => {'type': 'error', 'message': message, 'topic': ?topic};
}
