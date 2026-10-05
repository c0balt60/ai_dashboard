import 'dart:typed_data';

void Function() listenForFiles(
  void Function(
    List<({String name, int size, Future<Uint8List> Function() read})>,
  )
  onFiles,
) => () {};
