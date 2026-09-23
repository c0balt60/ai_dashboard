import 'enums.dart';
import 'json.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.agentId,
    required this.role,
    required this.text,
    required this.at,
  });

  factory ChatMessage.fromJson(Json json) => ChatMessage(
    id: json['id'] as String,
    agentId: json['agentId'] as String,
    role: MessageRole.values.byName(json['role'] as String),
    text: json['text'] as String,
    at: decodeTime(json['at']),
  );

  final String id;
  final String agentId;
  final MessageRole role;
  final String text;
  final DateTime at;

  Json toJson() => {
    'id': id,
    'agentId': agentId,
    'role': role.name,
    'text': text,
    'at': encodeTime(at),
  };
}
