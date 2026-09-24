import 'enums.dart';
import 'json.dart';

class TaskStep {
  const TaskStep(this.title, {this.done = false});

  factory TaskStep.fromJson(Json json) =>
      TaskStep(json['title'] as String, done: json['done'] as bool? ?? false);

  final String title;
  final bool done;

  Json toJson() => {'title': title, 'done': done};
}

/// Points a task at the to-do item it was created from. The backend ticks the
/// item off when the task completes and unticks it if the task is reopened.
class TodoLink {
  const TodoLink({required this.listId, required this.itemId});

  factory TodoLink.fromJson(Json json) => TodoLink(
    listId: json['listId'] as String,
    itemId: json['itemId'] as String,
  );

  final String listId;
  final String itemId;

  Json toJson() => {'listId': listId, 'itemId': itemId};
}

class AgentTask {
  const AgentTask({
    required this.id,
    required this.title,
    required this.projectId,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.agentId,
    this.todo,
    this.progress = 0,
    this.steps = const [],
    this.completedAt,
  });

  factory AgentTask.fromJson(Json json) => AgentTask(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    projectId: json['projectId'] as String,
    state: TaskState.values.byName(json['state'] as String),
    createdAt: decodeTime(json['createdAt']),
    updatedAt: decodeTime(json['updatedAt']),
    agentId: json['agentId'] as String?,
    todo: switch (json['todo']) {
      final Json link => TodoLink.fromJson(link),
      _ => null,
    },
    progress: (json['progress'] as num? ?? 0).toDouble(),
    steps: decodeList(json['steps'], TaskStep.fromJson),
    completedAt: decodeTimeOrNull(json['completedAt']),
  );

  final String id;
  final String title;

  /// Extra notes for the agent, sent along with the title.
  final String description;
  final String projectId;
  final String? agentId;
  final TodoLink? todo;
  final TaskState state;

  final double progress;
  final List<TaskStep> steps;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  bool get isDone => state == TaskState.completed || state == TaskState.failed;

  /// What the agent is told to do: the title, then the notes if any.
  String get brief => description.isEmpty
      ? 'Task: $title'
      : 'Task: $title\n\nNotes:\n$description';

  Json toJson() => {
    'id': id,
    'title': title,
    if (description.isNotEmpty) 'description': description,
    'projectId': projectId,
    'agentId': ?agentId,
    if (todo case final link?) 'todo': link.toJson(),
    'state': state.name,
    'progress': progress,
    'steps': [for (final s in steps) s.toJson()],
    'createdAt': encodeTime(createdAt),
    'updatedAt': encodeTime(updatedAt),
    if (completedAt case final t?) 'completedAt': encodeTime(t),
  };

  AgentTask copyWith({
    TaskState? state,
    String? Function()? agentId,
    double? progress,
    List<TaskStep>? steps,
    DateTime? updatedAt,
    DateTime? Function()? completedAt,
  }) {
    return AgentTask(
      id: id,
      title: title,
      description: description,
      projectId: projectId,
      todo: todo,
      createdAt: createdAt,
      state: state ?? this.state,
      agentId: agentId != null ? agentId() : this.agentId,
      progress: progress ?? this.progress,
      steps: steps ?? this.steps,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt != null ? completedAt() : this.completedAt,
    );
  }
}
