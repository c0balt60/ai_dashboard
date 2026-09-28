import 'enums.dart';
import 'json.dart';
import 'usage.dart';

/// A coding agent on the PC. It can belong to several projects
/// ([projectIds]); [projectId] and [workingDir] are where it works right now.
///
/// [model] and [effort] are what the owner picked for it, null meaning the
/// CLI's default; [activeModel] is the model the CLI last said it runs on.
class Agent {
  const Agent({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.activity,
    required this.lastActive,
    this.projectId,
    this.projectIds = const [],
    this.workingDir,
    this.branch,
    this.currentTaskId,
    this.model,
    this.effort,
    this.activeModel,
    this.usage,
  });

  factory Agent.fromJson(Json json) {
    final projectId = json['projectId'] as String?;
    return Agent(
      id: json['id'] as String,
      name: json['name'] as String,
      type: AgentType.values.byName(json['type'] as String),
      status: AgentStatus.values.byName(json['status'] as String),
      activity: json['activity'] as String? ?? '',
      lastActive: decodeTime(json['lastActive']),
      projectId: projectId,
      // Saved before agents could join several projects.
      projectIds: json.containsKey('projectIds')
          ? decodeStrings(json['projectIds'])
          : [?projectId],
      workingDir: json['workingDir'] as String?,
      branch: json['branch'] as String?,
      currentTaskId: json['currentTaskId'] as String?,
      model: json['model'] as String?,
      effort: EffortLevel.tryParse(json['effort']),
      activeModel: json['activeModel'] as String?,
      usage: switch (json['usage']) {
        final Json usage => UsageLimits.fromJson(usage),
        _ => null,
      },
    );
  }

  final String id;
  final String name;
  final AgentType type;
  final AgentStatus status;

  final String activity;
  final DateTime lastActive;
  final String? projectId;
  final List<String> projectIds;
  final String? workingDir;
  final String? branch;
  final String? currentTaskId;
  final String? model;
  final EffortLevel? effort;
  final String? activeModel;
  final UsageLimits? usage;

  bool get isBusy =>
      status == AgentStatus.running || status == AgentStatus.waiting;

  bool belongsTo(String projectId) =>
      this.projectId == projectId || projectIds.contains(projectId);

  Json toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'status': status.name,
    'activity': activity,
    'lastActive': encodeTime(lastActive),
    'projectId': ?projectId,
    'projectIds': projectIds,
    'workingDir': ?workingDir,
    'branch': ?branch,
    'currentTaskId': ?currentTaskId,
    'model': ?model,
    'effort': ?effort?.name,
    'activeModel': ?activeModel,
    if (usage != null) 'usage': usage!.toJson(),
  };

  /// Moving the agent to a [projectId] also adds it to [projectIds].
  Agent copyWith({
    AgentStatus? status,
    String? activity,
    DateTime? lastActive,
    String? Function()? projectId,
    List<String>? projectIds,
    String? Function()? workingDir,
    String? Function()? branch,
    String? Function()? currentTaskId,
    String? Function()? model,
    EffortLevel? Function()? effort,
    String? activeModel,
    UsageLimits? usage,
  }) {
    final newProjectId = projectId != null ? projectId() : this.projectId;
    final ids = projectIds ?? this.projectIds;
    return Agent(
      id: id,
      name: name,
      type: type,
      status: status ?? this.status,
      activity: activity ?? this.activity,
      lastActive: lastActive ?? this.lastActive,
      projectId: newProjectId,
      projectIds: newProjectId == null || ids.contains(newProjectId)
          ? ids
          : List.unmodifiable([...ids, newProjectId]),
      workingDir: workingDir != null ? workingDir() : this.workingDir,
      branch: branch != null ? branch() : this.branch,
      currentTaskId: currentTaskId != null
          ? currentTaskId()
          : this.currentTaskId,
      model: model != null ? model() : this.model,
      effort: effort != null ? effort() : this.effort,
      activeModel: activeModel ?? this.activeModel,
      usage: usage ?? this.usage,
    );
  }
}
