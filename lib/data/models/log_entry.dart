import 'enums.dart';

class LogEntry {
  const LogEntry({
    required this.at,
    required this.message,
    this.level = LogLevel.info,
    this.agentId,
  });

  final DateTime at;
  final String message;
  final LogLevel level;
  final String? agentId;
}
