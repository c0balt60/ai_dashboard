import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// How to start a program: directly for real executables, or through the
/// shell for Windows batch shims such as npm's `claude.cmd`, which
/// `Process.start` can't launch on its own.
typedef Launch = ({String executable, bool runInShell});

/// Finds [name] the way the shell would. Returns null on Windows when it
/// isn't on the PATH, so callers can explain that instead of passing on
/// cmd.exe's "is not recognized" message.
Future<Launch?> resolveLaunch(String name) async {
  if (!Platform.isWindows) return (executable: name, runInShell: false);
  bool isBatch(String ext) => ext == '.cmd' || ext == '.bat';

  final ext = p.extension(name).toLowerCase();
  if (ext.isNotEmpty) return (executable: name, runInShell: isBatch(ext));

  final exts = (Platform.environment['PATHEXT'] ?? '.EXE;.CMD;.BAT')
      .split(';')
      .where((e) => e.isNotEmpty)
      .map((e) => e.toLowerCase());
  final hasDir = name.contains('/') || name.contains(r'\');
  final dirs = hasDir
      ? const ['']
      : (Platform.environment['PATH'] ?? '').split(';');
  for (final dir in dirs) {
    for (final e in exts) {
      final candidate = dir.isEmpty ? '$name$e' : p.join(dir, '$name$e');
      if (File(candidate).existsSync()) {
        return (executable: candidate, runInShell: isBatch(e));
      }
    }
  }
  return null;
}

String notFoundMessage(String executable) =>
    "Can't find $executable on this PC's PATH. Install its CLI, or set "
    '"executable" for this agent in server/config.json to its full path.';

/// Kills [process] and, on Windows, every child it spawned.
Future<void> killTree(Process process) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', ['/pid', '${process.pid}', '/t', '/f']);
  } else {
    process.kill();
  }
}

class ShellResult {
  const ShellResult(this.exitCode, this.output, {this.timedOut = false});

  final int exitCode;

  /// Standard output and error interleaved, trimmed to the last
  /// [maxShellOutput] characters.
  final String output;
  final bool timedOut;
}

const maxShellOutput = 64 * 1024;

/// Runs a free-form [command] line in [workingDir].
///
/// With no [shell] configured, Windows uses PowerShell with
/// `-EncodedCommand`, which sidesteps cmd.exe quoting entirely, and other
/// systems use `/bin/sh -c`. A configured [shell] gets the command appended as
/// its last argument.
Future<ShellResult> runShell(
  String command, {
  required String workingDir,
  required Duration timeout,
  List<String> shell = const [],
}) async {
  final (executable, args) = switch (shell) {
    [final exe, ...final rest] => (exe, [...rest, command]),
    _ when Platform.isWindows => (
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-EncodedCommand', _encodePs(command)],
    ),
    _ => ('/bin/sh', ['-c', command]),
  };

  final process = await Process.start(
    executable,
    args,
    workingDirectory: workingDir,
  );
  await process.stdin.close();
  final buffer = StringBuffer();
  void collect(String chunk) {
    buffer.write(chunk);
    if (buffer.length > maxShellOutput * 2) {
      final kept = buffer.toString();
      buffer
        ..clear()
        ..write(kept.substring(kept.length - maxShellOutput));
    }
  }

  final decoder = const Utf8Decoder(allowMalformed: true);
  final done = Future.wait([
    process.stdout.transform(decoder).forEach(collect),
    process.stderr.transform(decoder).forEach(collect),
  ]);

  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () async {
      timedOut = true;
      await killTree(process);
      return -1;
    },
  );
  await done.timeout(const Duration(seconds: 2), onTimeout: () => const []);

  var output = buffer.toString();
  if (output.length > maxShellOutput) {
    output = '…${output.substring(output.length - maxShellOutput)}';
  }
  return ShellResult(exitCode, output, timedOut: timedOut);
}

/// Wraps [command] so PowerShell writes UTF-8 plain text (errors included)
/// and exits with the last native exit code, then encodes it for
/// `-EncodedCommand`.
String _encodePs(String command) {
  final script =
      '''
\$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
& {
$command
} 2>&1 | ForEach-Object { "\$_" }
if (\$LASTEXITCODE) { exit \$LASTEXITCODE }
''';
  final units = script.codeUnits;
  final bytes = <int>[
    for (final u in units) ...[u & 0xff, u >> 8],
  ];
  return base64.encode(bytes);
}

/// The current git branch of [dir], or an empty string outside a repository.
Future<String> gitBranch(String dir) async {
  try {
    final result = await Process.run('git', [
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ], workingDirectory: dir);
    return result.exitCode == 0 ? (result.stdout as String).trim() : '';
  } on ProcessException {
    return '';
  }
}
