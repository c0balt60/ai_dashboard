import 'json.dart';

/// One conversation with an agent. Each agent has a default, general-purpose
/// chat that shares the agent's id; every other chat belongs to a project and
/// runs in that project's folder, so each project keeps its own history and
/// CLI session.
class AgentChat {
  const AgentChat({
    required this.id,
    required this.agentId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.projectId,
  });

  factory AgentChat.fromJson(Json json) => AgentChat(
    id: json['id'] as String,
    agentId: json['agentId'] as String,
    title: json['title'] as String? ?? '',
    createdAt: decodeTime(json['createdAt']),
    updatedAt: decodeTime(json['updatedAt']),
    projectId: json['projectId'] as String?,
  );

  /// The general-purpose chat every agent starts with.
  factory AgentChat.general(String agentId, DateTime at) => AgentChat(
    id: agentId,
    agentId: agentId,
    title: 'General',
    createdAt: at,
    updatedAt: at,
  );

  final String id;
  final String agentId;

  /// Empty until the first prompt names the chat.
  final String title;
  final String? projectId;
  final DateTime createdAt;

  /// When the last message was posted.
  final DateTime updatedAt;

  bool get isDefault => id == agentId;

  String get displayTitle => title.isEmpty ? 'New chat' : title;

  Json toJson() => {
    'id': id,
    'agentId': agentId,
    'title': title,
    'projectId': ?projectId,
    'createdAt': encodeTime(createdAt),
    'updatedAt': encodeTime(updatedAt),
  };

  AgentChat copyWith({String? title, DateTime? updatedAt}) => AgentChat(
    id: id,
    agentId: agentId,
    projectId: projectId,
    createdAt: createdAt,
    title: title ?? this.title,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
