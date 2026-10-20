import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// The system dialogs that save and open a backup package.
///
/// The user chooses the place (Downloads, Drive, any provider of the system
/// picker), so the app needs no storage permission. Injected so widget tests
/// can replace the platform dialogs.
abstract interface class BackupFilePicker {
  /// Asks where to save [bytes], suggesting [fileName].
  ///
  /// Resolves to `true` once the file is written, `false` if the user
  /// cancelled.
  Future<bool> savePackage(String fileName, Uint8List bytes);

  /// Asks for a package to import. Resolves to its bytes, or `null` if the
  /// user cancelled.
  Future<Uint8List?> pickPackage();
}

/// [BackupFilePicker] on the `file_picker` plugin (Android: Storage Access
/// Framework).
class PlatformBackupFilePicker implements BackupFilePicker {
  /// Creates the picker. Stateless.
  const PlatformBackupFilePicker();

  /// MIME type of the package, so the system picker shows it as a zip.
  static const String _zipMimeType = 'application/zip';

  @override
  Future<bool> savePackage(String fileName, Uint8List bytes) async {
    final saved = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: _zipMimeType,
    );
    return saved != null;
  }

  @override
  Future<Uint8List?> pickPackage() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    return file?.readAsBytes();
  }
}
