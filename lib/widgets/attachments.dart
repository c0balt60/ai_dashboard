import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/models/models.dart';
import 'file_drop.dart';

/// A file picked on this device, read only once it is known to fit.
typedef PickedFile = ({
  String name,
  int size,
  Future<Uint8List> Function() read,
});

/// Reads [files] in, leaving out the ones over [maxAttachmentBytes] and
/// telling the owner which.
Future<List<FileUpload>> _readFiles(
  ScaffoldMessengerState messenger,
  List<PickedFile> files,
) async {
  final kept = <FileUpload>[];
  final tooBig = <String>[];
  for (final f in files) {
    final bytes = f.size > maxAttachmentBytes ? null : await f.read();
    if (bytes == null || bytes.length > maxAttachmentBytes) {
      tooBig.add(f.name);
    } else {
      kept.add(FileUpload(f.name, bytes));
    }
  }
  if (tooBig.isNotEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${tooBig.join(', ')} ${tooBig.length == 1 ? 'is' : 'are'} over '
          'the ${formatBytes(maxAttachmentBytes)} limit',
        ),
      ),
    );
  }
  return kept;
}

Future<List<PickedFile>> _pickFiles() async => [
  for (final f in await FilePicker.pickFiles())
    (name: f.name, size: await f.length() ?? 0, read: f.readAsBytes),
];

/// Scaled down so Claude can take the photo inline.
Future<List<PickedFile>> _takePhoto() async {
  final photo = await ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 85,
  );
  if (photo == null) return const [];
  return [
    (name: photo.name, size: await photo.length(), read: photo.readAsBytes),
  ];
}

String formatBytes(int bytes) => switch (bytes) {
  < 1024 => '$bytes B',
  < 1024 * 1024 => '${(bytes / 1024).round()} KB',
  _ => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
};

/// A round button that adds files from the system picker. On phones, or with
/// [extraItems], it opens a menu offering the camera and those items too.
class AttachButton extends StatelessWidget {
  const AttachButton({
    super.key,
    required this.onFiles,
    this.style,
    this.icon = Icons.attach_file,
    this.tooltip = 'Attach files',
    this.extraItems = const [],
  });

  final ValueChanged<List<FileUpload>> onFiles;
  final ButtonStyle? style;
  final IconData icon;
  final String tooltip;
  final List<Widget> extraItems;

  static bool get _hasCamera =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _add(
    BuildContext context,
    Future<List<PickedFile>> Function() pick,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final files = await _readFiles(messenger, await pick());
    if (files.isNotEmpty) onFiles(files);
  }

  @override
  Widget build(BuildContext context) {
    Widget button(VoidCallback onPressed) => IconButton(
      style: style,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
    );
    if (!_hasCamera && extraItems.isEmpty) {
      return button(() => _add(context, _pickFiles));
    }
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.attach_file),
          onPressed: () => _add(context, _pickFiles),
          child: const Text('Attach files'),
        ),
        if (_hasCamera)
          MenuItemButton(
            leadingIcon: const Icon(Icons.photo_camera_outlined),
            onPressed: () => _add(context, _takePhoto),
            child: const Text('Take a photo'),
          ),
        ...extraItems,
      ],
      builder: (context, controller, _) => button(
        () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// A file's icon, name and size, with a remove button when [onDeleted] is
/// set.
class AttachmentChip extends StatelessWidget {
  const AttachmentChip({
    super.key,
    required this.name,
    required this.size,
    this.onDeleted,
  });

  final String name;
  final int size;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    // Filled, so it reads on the primary-colored bubbles of sent prompts.
    return Chip(
      backgroundColor: scheme.surfaceContainerHighest,
      side: BorderSide.none,
      avatar: Icon(
        imageMediaType(name) != null
            ? Icons.image_outlined
            : Icons.insert_drive_file_outlined,
        size: 18,
      ),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text(' · ${formatBytes(size)}', style: TextStyle(color: muted)),
          ],
        ),
      ),
      onDeleted: onDeleted,
      deleteButtonTooltipMessage: 'Remove $name',
    );
  }
}

/// The files about to be sent, in one row that scrolls sideways so any
/// number of them keeps the composer one chip tall.
class PendingAttachments extends StatelessWidget {
  const PendingAttachments(this.files, {super.key, required this.onRemove});

  final List<FileUpload> files;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        spacing: 6,
        children: [
          for (final (i, f) in files.indexed)
            AttachmentChip(
              name: f.name,
              size: f.bytes.length,
              onDeleted: () => onRemove(i),
            ),
        ],
      ),
    );
  }
}

/// Hands files pasted or dropped anywhere on the page to [onFiles] while
/// this screen is on top. Only browsers deliver those; elsewhere this just
/// shows [child].
class FileDropTarget extends StatefulWidget {
  const FileDropTarget({super.key, required this.onFiles, required this.child});

  final ValueChanged<List<FileUpload>> onFiles;
  final Widget child;

  @override
  State<FileDropTarget> createState() => _FileDropTargetState();
}

class _FileDropTargetState extends State<FileDropTarget> {
  late final void Function() _stop;

  @override
  void initState() {
    super.initState();
    _stop = listenForFiles(_take);
  }

  Future<void> _take(List<PickedFile> picked) async {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final files = await _readFiles(ScaffoldMessenger.of(context), picked);
    if (files.isNotEmpty && mounted) widget.onFiles(files);
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
