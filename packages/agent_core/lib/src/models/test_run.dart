import 'enums.dart';
import 'json.dart';

class TestRun {
  const TestRun({
    required this.id,
    required this.suite,
    required this.status,
    required this.passed,
    required this.failed,
    required this.duration,
    required this.at,
    this.failingTests = const [],
    this.agentId,
  });

  factory TestRun.fromJson(Json json) => TestRun(
    id: json['id'] as String,
    suite: json['suite'] as String,
    status: TestStatus.values.byName(json['status'] as String),
    passed: json['passed'] as int? ?? 0,
    failed: json['failed'] as int? ?? 0,
    duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
    at: decodeTime(json['at']),
    failingTests: decodeStrings(json['failingTests']),
    agentId: json['agentId'] as String?,
  );

  final String id;

  final String suite;
  final TestStatus status;
  final int passed;
  final int failed;
  final List<String> failingTests;
  final Duration duration;
  final DateTime at;
  final String? agentId;

  int get total => passed + failed;

  Json toJson() => {
    'id': id,
    'suite': suite,
    'status': status.name,
    'passed': passed,
    'failed': failed,
    'failingTests': failingTests,
    'durationMs': duration.inMilliseconds,
    'at': encodeTime(at),
    'agentId': ?agentId,
  };
}
