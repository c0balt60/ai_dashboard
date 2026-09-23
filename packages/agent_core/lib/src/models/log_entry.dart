import 'enums.dart';
import 'json.dart';

class LogEntry {
  const LogEntry({
    required this.at,
    required this.message,
    this.level = LogLevel.info,
    this.agentId,
  });

  factory LogEntry.fromJson(Json json) => LogEntry(
    at: decodeTime(json['at']),
    message: json['message'] as String,
    level: LogLevel.values.byName(json['level'] as String? ?? 'info'),
    agentId: json['agentId'] as String?,
  );

  final DateTime at;
  final String message;
  final LogLevel level;
  final String? agentId;

  Json toJson() => {
    'at': encodeTime(at),
    'message': message,
    'level': level.name,
    'agentId': ?agentId,
  };
}
