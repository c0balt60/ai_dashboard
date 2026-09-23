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

class AgentTask {
  const AgentTask({
    required this.id,
    required this.title,
    required this.projectId,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.agentId,
    this.progress = 0,
    this.steps = const [],
    this.completedAt,
  });

  factory AgentTask.fromJson(Json json) => AgentTask(
    id: json['id'] as String,
    title: json['title'] as String,
    projectId: json['projectId'] as String,
    state: TaskState.values.byName(json['state'] as String),
    createdAt: decodeTime(json['createdAt']),
    updatedAt: decodeTime(json['updatedAt']),
    agentId: json['agentId'] as String?,
    progress: (json['progress'] as num? ?? 0).toDouble(),
    steps: decodeList(json['steps'], TaskStep.fromJson),
    completedAt: decodeTimeOrNull(json['completedAt']),
  );

  final String id;
  final String title;
  final String projectId;
  final String? agentId;
  final TaskState state;

  final double progress;
  final List<TaskStep> steps;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  bool get isDone => state == TaskState.completed || state == TaskState.failed;

  Json toJson() => {
    'id': id,
    'title': title,
    'projectId': projectId,
    'agentId': ?agentId,
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
      projectId: projectId,
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
