import 'package:flutter/widgets.dart' show BuildContext;

/// A file returned by a host-provided attachment picker
/// (`EasyLiveChatScreen.onPickAttachments`). The SDK uploads [bytes] via the
/// widget JWT and links the result to the next sent message.
class ElcPickedFile {
  /// Raw file bytes to upload.
  final List<int> bytes;

  /// File name (with extension) the server should record.
  final String filename;

  /// Optional MIME type (e.g. `image/jpeg`); the server infers one when null.
  final String? contentType;

  const ElcPickedFile({
    required this.bytes,
    required this.filename,
    this.contentType,
  });
}

/// Host hook that fully owns attachment picking (e.g. your app's own
/// camera/gallery bottom sheet). Return the picked files, or an empty list if
/// the user cancelled. When provided to [EasyLiveChatScreen], the composer's
/// attach button calls this instead of the built-in image/file pickers.
typedef ElcAttachmentPicker = Future<List<ElcPickedFile>> Function(
  BuildContext context,
);
