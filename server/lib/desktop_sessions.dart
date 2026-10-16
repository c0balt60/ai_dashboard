import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Turns quiet for longer than this count as over, so a CLI that was killed
/// mid-turn doesn't look busy forever.
// ponytail: a tool call silent for longer than this looks finished; hooks
// would be exact if that ever matters.
const _stale = Duration(minutes: 10);

/// How much of the end of a transcript to read to find its last message.
const _tail = 1 << 20;

/// The folders where Claude Code is in the middle of a turn that this server
/// didn't start, e.g. in a terminal, VS Code or the desktop app.
///
/// Claude Code writes every session to `<claude dir>/projects/*/<id>.jsonl`.
/// A turn is open while its last message is the owner's prompt, a tool
/// result or a reply that goes on to use a tool. Sessions named in [ignore]
/// (the server's own) are skipped.
Future<List<String>> busyClaudeDirs({
  Set<String> ignore = const {},
  String? claudeDir,
  DateTime? now,
}) async {
  final env = Platform.environment;
  final projects = Directory(
    p.join(
      claudeDir ??
          env['CLAUDE_CONFIG_DIR'] ??
          p.join(env['USERPROFILE'] ?? env['HOME'] ?? '.', '.claude'),
      'projects',
    ),
  );
  if (!projects.existsSync()) return const [];
  final since = (now ?? DateTime.now()).subtract(_stale);
  final dirs = <String>[];
  try {
    await for (final folder in projects.list()) {
      if (folder is! Directory) continue;
      await for (final file in folder.list()) {
        if (file is! File || p.extension(file.path) != '.jsonl') continue;
        if (ignore.contains(p.basenameWithoutExtension(file.path))) continue;
        try {
          if ((await file.lastModified()).isBefore(since)) continue;
          if (await _openTurnDir(file) case final dir?) dirs.add(dir);
        } on FileSystemException {
          continue;
        }
      }
    }
  } on FileSystemException {
    return dirs;
  }
  return dirs;
}

/// The folder [transcript] works in if its last turn hasn't ended.
Future<String?> _openTurnDir(File transcript) async {
  final file = await transcript.open();
  final List<int> bytes;
  try {
    await file.setPosition(max(0, await file.length() - _tail));
    bytes = await file.read(_tail);
  } finally {
    await file.close();
  }
  final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
  for (final line in lines.reversed) {
    final Object? entry;
    try {
      entry = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (entry
        case {
          'type': final String type,
          'cwd': final String cwd,
          'message': final Map<String, Object?> message,
        }
        when entry['isSidechain'] != true) {
      final open = switch (type) {
        'assistant' => switch (message['stop_reason']) {
          null || 'tool_use' => true,
          _ => false,
        },
        'user' => !_endsTurn(message['content']),
        _ => null,
      };
      if (open != null) return open ? cwd : null;
    }
  }
  return null;
}

/// Whether a user message is a local slash command, its output or an
/// interruption, none of which leave Claude working.
bool _endsTurn(Object? content) {
  final text = switch (content) {
    final String s => s,
    [{'type': 'text', 'text': final String s}, ...] => s,
    _ => '',
  };
  return text.startsWith('<command-') ||
      text.startsWith('<local-command-') ||
      text.startsWith('[Request interrupted');
}
