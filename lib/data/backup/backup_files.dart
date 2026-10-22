import 'dart:io';
import 'dart:typed_data';

/// The file operations the backup service needs next to the database file.
///
/// Injected so tests can observe or break them; the app uses
/// [IoBackupFiles]. Nothing here reads a whole file into memory except
/// [readHead], which reads only its first bytes.
abstract interface class BackupFiles {
  /// Reads the first [length] bytes of the file at [path] (fewer when the
  /// file is shorter).
  Future<Uint8List> readHead(String path, int length);

  /// The size of the file at [path] in bytes, or 0 when it is missing.
  Future<int> sizeOf(String path);

  /// Whether a file or a directory exists at [path].
  Future<bool> exists(String path);

  /// Copies the file at [from] to [to], replacing [to] if it exists.
  Future<void> copy(String from, String to);

  /// Renames the file or directory at [from] to [to]. A file replaces [to];
  /// a directory needs [to] not to exist.
  Future<void> rename(String from, String to);

  /// Creates the directory at [path] and its parents, if missing.
  Future<void> createDirectory(String path);

  /// Deletes the file at [path] if it exists.
  Future<void> deleteIfExists(String path);

  /// Deletes the directory at [path] and everything in it, if it exists.
  Future<void> deleteDirectoryIfExists(String path);
}

/// [BackupFiles] on the real file system, through `dart:io`.
class IoBackupFiles implements BackupFiles {
  /// Creates the adapter. Stateless.
  const IoBackupFiles();

  @override
  Future<Uint8List> readHead(String path, int length) async {
    final file = await File(path).open();
    try {
      return await file.read(length);
    } finally {
      await file.close();
    }
  }

  @override
  Future<int> sizeOf(String path) async {
    final file = File(path);
    if (!await file.exists()) return 0;
    return file.length();
  }

  @override
  Future<bool> exists(String path) async =>
      await FileSystemEntity.type(path) != FileSystemEntityType.notFound;

  @override
  Future<void> copy(String from, String to) async {
    await File(from).copy(to);
  }

  @override
  Future<void> rename(String from, String to) async {
    if (await FileSystemEntity.isDirectory(from)) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }
  }

  @override
  Future<void> createDirectory(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> deleteDirectoryIfExists(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
