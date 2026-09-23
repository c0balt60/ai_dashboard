/// Pass/fail counts pulled out of a test runner's output.
typedef TestSummary = ({int passed, int failed, List<String> failing});

/// Reads the summary of common test runners: Dart/Flutter (`+12 -1: ...`),
/// pytest, Jest/Vitest and cargo (`N passed`, `N failed`). Falls back to zero
/// counts when nothing matches, leaving the exit code to decide the result.
TestSummary parseTestSummary(String rawOutput) {
  final output = rawOutput.replaceAll('\r', '');
  final failing = <String>{};

  final dart = RegExp(
    r'^\d+:\d+ \+(\d+)(?: ~\d+)?(?: -(\d+))?: (.*)$',
    multiLine: true,
  ).allMatches(output).toList();
  if (dart.isNotEmpty) {
    for (final m in dart) {
      final name = m[3]!;
      if (name.endsWith(' [E]')) {
        failing.add(name.substring(0, name.length - 4).trim());
      }
    }
    return (
      passed: int.parse(dart.last[1]!),
      failed: int.parse(dart.last[2] ?? '0'),
      failing: failing.toList(),
    );
  }

  int count(String word) {
    final m = RegExp('(\\d+) $word').allMatches(output).lastOrNull;
    return m == null ? 0 : int.parse(m[1]!);
  }

  for (final m in RegExp(
    r'^FAILED (\S+)',
    multiLine: true,
  ).allMatches(output)) {
    failing.add(m[1]!);
  }
  return (
    passed: count('passed'),
    failed: count('failed'),
    failing: failing.toList(),
  );
}
