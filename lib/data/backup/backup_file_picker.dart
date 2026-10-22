import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// The system dialog that opens a backup package for an import.
///
/// The user chooses the file (Downloads, Drive, any provider of the system
/// picker), so the app needs no storage permission. Injected so widget tests
/// can replace the platform dialog. Saving a package goes through the native
/// "save as" channel instead (`NativeFiles`), which streams the file.
abstract interface class BackupFilePicker {
  /// Asks for a package to import and copies it, streamed, to the new file
  /// at [copyTo]. Resolves to `false` if the user cancelled.
  Future<bool> pickPackage(String copyTo);
}

/// [BackupFilePicker] on the `file_picker` plugin (Android: Storage Access
/// Framework).
class PlatformBackupFilePicker implements BackupFilePicker {
  /// Creates the picker. Stateless.
  const PlatformBackupFilePicker();

  @override
  Future<bool> pickPackage(String copyTo) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (file == null) return false;
    // The picked document may be a `content://` URI: read it as a stream
    // into a local file, never into memory.
    final sink = File(copyTo).openWrite();
    try {
      await sink.addStream(file.readAsByteStream());
    } finally {
      await sink.close();
    }
    return true;
  }
}
