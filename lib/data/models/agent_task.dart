import 'enums.dart';

class TaskStep {
  const TaskStep(this.title, {this.done = false});

  final String title;
  final bool done;
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
