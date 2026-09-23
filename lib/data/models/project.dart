import 'log_entry.dart';
import 'test_run.dart';

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.path,
    required this.branch,
    required this.lastActivity,
    this.testRuns = const [],
    this.log = const [],
  });

  final String id;
  final String name;

  final String path;
  final String branch;
  final DateTime lastActivity;

  /// Newest first.
  final List<TestRun> testRuns;

  /// Newest first.
  final List<LogEntry> log;

  TestRun? get latestTestRun => testRuns.isEmpty ? null : testRuns.first;

  Project copyWith({
    String? branch,
    DateTime? lastActivity,
    List<TestRun>? testRuns,
    List<LogEntry>? log,
  }) {
    return Project(
      id: id,
      name: name,
      path: path,
      branch: branch ?? this.branch,
      lastActivity: lastActivity ?? this.lastActivity,
      testRuns: testRuns ?? this.testRuns,
      log: log ?? this.log,
    );
  }
}
