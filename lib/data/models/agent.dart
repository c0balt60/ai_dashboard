import 'enums.dart';

class Agent {
  const Agent({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.activity,
    required this.lastActive,
    this.projectId,
    this.workingDir,
    this.branch,
    this.currentTaskId,
  });

  final String id;
  final String name;
  final AgentType type;
  final AgentStatus status;

  final String activity;
  final DateTime lastActive;
  final String? projectId;
  final String? workingDir;
  final String? branch;
  final String? currentTaskId;

  bool get isBusy =>
      status == AgentStatus.running || status == AgentStatus.waiting;

  Agent copyWith({
    AgentStatus? status,
    String? activity,
    DateTime? lastActive,
    String? Function()? projectId,
    String? Function()? workingDir,
    String? Function()? branch,
    String? Function()? currentTaskId,
  }) {
    return Agent(
      id: id,
      name: name,
      type: type,
      status: status ?? this.status,
      activity: activity ?? this.activity,
      lastActive: lastActive ?? this.lastActive,
      projectId: projectId != null ? projectId() : this.projectId,
      workingDir: workingDir != null ? workingDir() : this.workingDir,
      branch: branch != null ? branch() : this.branch,
      currentTaskId: currentTaskId != null
          ? currentTaskId()
          : this.currentTaskId,
    );
  }
}
