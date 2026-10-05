import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Calls [onFiles] with the files of every paste or drop on the page until
/// the returned function is called. Pastes without files are left to the
/// text field.
void Function() listenForFiles(
  void Function(
    List<({String name, int size, Future<Uint8List> Function() read})>,
  )
  onFiles,
) {
  void take(web.FileList? list, web.Event event) {
    if (list == null || list.length == 0) return;
    event.preventDefault();
    onFiles([
      for (var i = 0; i < list.length; i++)
        if (list.item(i) case final file?)
          (
            name: file.name,
            size: file.size,
            read: () async =>
                (await file.arrayBuffer().toDart).toDart.asUint8List(),
          ),
    ]);
  }

  // Without this the browser opens a dropped file in place of the app.
  final dragOver = ((web.DragEvent e) => e.preventDefault()).toJS;
  final drop = ((web.DragEvent e) {
    e.preventDefault();
    take(e.dataTransfer?.files, e);
  }).toJS;
  final paste = ((web.ClipboardEvent e) => take(
    e.clipboardData?.files,
    e,
  )).toJS;
  web.window
    ..addEventListener('dragover', dragOver)
    ..addEventListener('drop', drop)
    ..addEventListener('paste', paste);
  return () => web.window
    ..removeEventListener('dragover', dragOver)
    ..removeEventListener('drop', drop)
    ..removeEventListener('paste', paste);
}
