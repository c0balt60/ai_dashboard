import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:path/path.dart' as p;

/// Keeps the server's state in one JSON file between restarts.
///
/// Saves are debounced and written to a temp file first, then renamed over
/// the old one, so a crash mid-write never leaves a half-written state.
class StateStore {
  StateStore(
    String dataDir, {
    this.debounce = const Duration(milliseconds: 500),
  }) : file = File(p.join(dataDir, 'state.json'));

  final File file;
  final Duration debounce;
  Json Function()? _pending;
  Timer? _timer;

  /// The saved state, or null when there is none. An unreadable file is set
  /// aside as `state.json.corrupt` rather than overwritten.
  Json? load() {
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(file.readAsStringSync()) as Json;
    } on Object {
      file.renameSync('${file.path}.corrupt');
      return null;
    }
  }

  void save(Json Function() snapshot) {
    _pending = snapshot;
    _timer ??= Timer(debounce, flush);
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    final snapshot = _pending;
    if (snapshot == null) return;
    _pending = null;
    file.parent.createSync(recursive: true);
    final temp = File('${file.path}.tmp')
      ..writeAsStringSync(jsonEncode(snapshot()), flush: true);
    temp.renameSync(file.path);
  }
}
