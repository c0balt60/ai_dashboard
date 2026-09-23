import 'enums.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.agentId,
    required this.role,
    required this.text,
    required this.at,
  });

  final String id;
  final String agentId;
  final MessageRole role;
  final String text;
  final DateTime at;
}
