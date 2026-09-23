/// Bumps the app version in pubspec.yaml and lib/app/app_version.dart.
///
/// Usage, from the project root:
///   `dart tool/bump_version.dart <major|minor|patch|build>`
///
/// Every bump also increments the build number, which never resets.
/// See VERSIONING.md for which part to bump.
library;

import 'dart:io';

final _pubspecVersion = RegExp(
  r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
  multiLine: true,
);

void main(List<String> args) {
  const parts = ['major', 'minor', 'patch', 'build'];
  if (args.length != 1 || !parts.contains(args.single)) {
    stderr.writeln('Usage: dart tool/bump_version.dart <${parts.join('|')}>');
    exit(64);
  }

  final pubspec = File('pubspec.yaml');
  final versionFile = File('lib/app/app_version.dart');
  if (!pubspec.existsSync() || !versionFile.existsSync()) {
    stderr.writeln('Run this from the project root.');
    exit(66);
  }

  final source = pubspec.readAsStringSync();
  final match = _pubspecVersion.firstMatch(source);
  if (match == null) {
    stderr.writeln('pubspec.yaml has no "version: X.Y.Z+N" line.');
    exit(65);
  }

  var [major, minor, patch, build] = [
    for (var i = 1; i <= 4; i++) int.parse(match.group(i)!),
  ];
  switch (args.single) {
    case 'major':
      (major, minor, patch) = (major + 1, 0, 0);
    case 'minor':
      (minor, patch) = (minor + 1, 0);
    case 'patch':
      patch++;
  }
  build++;

  final version = '$major.$minor.$patch';
  pubspec.writeAsStringSync(
    source.replaceRange(match.start, match.end, 'version: $version+$build'),
  );
  versionFile.writeAsStringSync(
    versionFile
        .readAsStringSync()
        .replaceFirst(
          RegExp(r"const appVersion = '[^']*';"),
          "const appVersion = '$version';",
        )
        .replaceFirst(
          RegExp(r'const appBuildNumber = \d+;'),
          'const appBuildNumber = $build;',
        ),
  );
  stdout.writeln('Version bumped to $version+$build');
}
