import 'log_entry.dart';
import 'test_run.dart';
import 'json.dart';

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

  factory Project.fromJson(Json json) => Project(
    id: json['id'] as String,
    name: json['name'] as String,
    path: json['path'] as String,
    branch: json['branch'] as String? ?? '',
    lastActivity: decodeTime(json['lastActivity']),
    testRuns: decodeList(json['testRuns'], TestRun.fromJson),
    log: decodeList(json['log'], LogEntry.fromJson),
  );

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

  Json toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'branch': branch,
    'lastActivity': encodeTime(lastActivity),
    'testRuns': [for (final r in testRuns) r.toJson()],
    'log': [for (final e in log) e.toJson()],
  };

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
