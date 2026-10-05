import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:path/path.dart' as p;

/// Files the owner attaches are saved in the chat's folder under
/// `.attachments/<chat id>/`, or `.attachments/tasks/<task id>/` for tasks.
const attachmentsFolder = '.attachments';

/// Writes [upload] into [dir], under its own name unless that is taken.
Attachment saveUpload(String dir, FileUpload upload) {
  final name = safeFileName(upload.name);
  final stem = p.basenameWithoutExtension(name);
  final ext = p.extension(name);
  var file = File(p.join(dir, name));
  for (var i = 1; file.existsSync(); i++) {
    file = File(p.join(dir, '$stem ($i)$ext'));
  }
  file.writeAsBytesSync(upload.bytes);
  return Attachment(
    name: p.basename(file.path),
    size: upload.bytes.length,
    path: file.path,
  );
}

/// [name] without folders or characters Windows doesn't allow in file names.
String safeFileName(String name) {
  final base = p.posix
      .basename(name.replaceAll(r'\', '/'))
      .replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_')
      .trim();
  return base.isEmpty || base == '.' || base == '..' ? 'file' : base;
}

/// Keeps the attachments folder in [dir] out of git with a `.gitignore` of its
/// own that ignores everything, itself included, so the project's files stay
/// untouched.
void ignoreAttachments(String dir) {
  final file = File(p.join(dir, attachmentsFolder, '.gitignore'));
  if (!file.existsSync()) file.writeAsStringSync('*\n');
}
