import 'dart:io';
import 'dart:typed_data';

/// The file operations the backup service needs next to the database file.
///
/// Injected so tests can observe or break them; the app uses
/// [IoBackupFiles].
abstract interface class BackupFiles {
  /// Reads the whole file at [path].
  Future<Uint8List> readBytes(String path);

  /// Writes [bytes] to [path], replacing the file if it exists.
  Future<void> writeBytes(String path, Uint8List bytes);

  /// Copies the file at [from] to [to], replacing [to] if it exists.
  Future<void> copy(String from, String to);

  /// Renames the file at [from] to [to], replacing [to] if it exists.
  Future<void> rename(String from, String to);

  /// Deletes the file at [path] if it exists.
  Future<void> deleteIfExists(String path);
}

/// [BackupFiles] on the real file system, through `dart:io`.
class IoBackupFiles implements BackupFiles {
  /// Creates the adapter. Stateless.
  const IoBackupFiles();

  @override
  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    await File(path).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> copy(String from, String to) async {
    await File(from).copy(to);
  }

  @override
  Future<void> rename(String from, String to) async {
    await File(from).rename(to);
  }

  @override
  Future<void> deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
