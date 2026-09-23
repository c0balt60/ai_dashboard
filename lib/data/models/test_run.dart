import 'enums.dart';

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
}
