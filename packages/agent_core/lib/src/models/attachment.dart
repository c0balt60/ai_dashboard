import 'dart:convert';
import 'dart:typed_data';

import 'json.dart';

/// The largest file the owner may attach.
const maxAttachmentBytes = 20 * 1024 * 1024;

/// A file the owner picked, on its way to the PC with a prompt or task.
class FileUpload {
  const FileUpload(this.name, this.bytes);

  factory FileUpload.fromJson(Json json) =>
      FileUpload(json['name'] as String, base64Decode(json['data'] as String));

  final String name;
  final Uint8List bytes;

  Json toJson() => {'name': name, 'data': base64Encode(bytes)};
}

/// A file the PC saved for the agent, which reads it at [path].
class Attachment {
  const Attachment({
    required this.name,
    required this.size,
    required this.path,
  });

  factory Attachment.fromJson(Json json) => Attachment(
    name: json['name'] as String,
    size: json['size'] as int,
    path: json['path'] as String,
  );

  final String name;
  final int size;
  final String path;

  /// The media type of an image Claude can look at directly, else null.
  String? get imageType => imageMediaType(name);

  Json toJson() => {'name': name, 'size': size, 'path': path};
}

String? imageMediaType(String name) =>
    switch (name.split('.').last.toLowerCase()) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => null,
    };

/// [prompt] followed by where the agent finds [files].
String withAttachments(String prompt, List<Attachment> files) => files.isEmpty
    ? prompt
    : [
        if (prompt.isNotEmpty) '$prompt\n',
        'Attached files:',
        for (final f in files) '- ${f.path}',
      ].join('\n');
