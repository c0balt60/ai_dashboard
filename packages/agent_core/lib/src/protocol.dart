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

  static String prompt(String agentId) => '/api/agents/$agentId/prompt';
  static String assign(String agentId) => '/api/agents/$agentId/assign';
  static String stop(String agentId) => '/api/agents/$agentId/stop';
  static String clearMessages(String agentId) =>
      '/api/agents/$agentId/messages';

  static const tasks = '/api/tasks';
  static String taskState(String taskId) => '/api/tasks/$taskId/state';

  static const todoLists = '/api/todo-lists';
  static String todoList(String listId) => '/api/todo-lists/$listId';
  static String todoItems(String listId) => '/api/todo-lists/$listId/items';
  static String todoItem(String listId, String itemId) =>
      '/api/todo-lists/$listId/items/$itemId';

  static String runCommand(String projectId) =>
      '/api/projects/$projectId/commands';
}

/// Names of the streams a client can subscribe to.
abstract final class Topics {
  static const agents = 'agents';
  static const projects = 'projects';
  static const tasks = 'tasks';
  static const todoLists = 'todoLists';
  static const _messagesPrefix = 'messages:';

  static String messages(String agentId) => '$_messagesPrefix$agentId';

  /// The agent id of a [messages] topic, or null for any other topic.
  static String? messagesAgent(String topic) =>
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
    _ => switch (Topics.messagesAgent(topic)) {
      final agentId? =>
        backend.watchMessages(agentId).map((l) => encode(l, (m) => m.toJson())),
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
