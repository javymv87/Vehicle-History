import 'dart:io';

import 'package:drift/drift.dart';

/// The database file was written by a newer version of the app.
///
/// Opening it is refused instead of "fixed": the newer schema may hold data
/// this version does not understand, and touching it could destroy that data.
/// The file is left exactly as it was.
class DatabaseNewerThanAppException implements Exception {
  /// Creates the exception for a file at [fileVersion] opened by an app that
  /// only knows up to [appVersion].
  const DatabaseNewerThanAppException(this.fileVersion, this.appVersion);

  /// Schema version stored in the database file.
  final int fileVersion;

  /// Highest schema version this app knows.
  final int appVersion;

  @override
  String toString() =>
      'DatabaseNewerThanAppException(file: v$fileVersion, app: v$appVersion)';
}

/// An upgrade finished its steps but left the data inconsistent.
///
/// The upgrade transaction is rolled back, so the database stays at its old
/// version, and the pre-upgrade copy is kept.
class MigrationIntegrityException implements Exception {
  /// Creates the exception for an upgrade from [from] to [to] that left
  /// [violations] rows failing `PRAGMA foreign_key_check`.
  const MigrationIntegrityException(this.from, this.to, this.violations);

  /// Schema version before the upgrade.
  final int from;

  /// Schema version the upgrade targeted.
  final int to;

  /// Number of rows reported by `PRAGMA foreign_key_check`.
  final int violations;

  @override
  String toString() => 'MigrationIntegrityException(v$from → v$to, '
      '$violations foreign key violation(s))';
}

/// The few file operations the pre-upgrade copy needs.
///
/// Injected so tests can observe or break them without touching the real
/// app directory.
abstract interface class BackupFileSystem {
  /// Names (not paths) of the files directly inside [directory].
  Future<List<String>> listFileNames(String directory);

  /// Deletes the file at [path] if it exists.
  Future<void> deleteIfExists(String path);

  /// Renames the file at [from] to [to], replacing [to] if it exists.
  Future<void> rename(String from, String to);
}

/// [BackupFileSystem] on the real file system, through `dart:io`.
class IoBackupFileSystem implements BackupFileSystem {
  /// Creates the file system adapter. Stateless.
  const IoBackupFileSystem();

  @override
  Future<List<String>> listFileNames(String directory) async {
    final entries = await Directory(directory).list().toList();
    return [
      for (final entry in entries)
        if (entry is File) entry.uri.pathSegments.last,
    ];
  }

  @override
  Future<void> deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> rename(String from, String to) async {
    await File(from).rename(to);
  }
}

/// Makes a copy of the database file before an upgrade touches it.
///
/// The copy is written with SQLite's `VACUUM INTO`, which produces a
/// consistent, self-contained database file from the open connection: it
/// includes any pages still in the WAL, it needs no second connection, and it
/// works inside drift's background isolate. A plain file copy could miss WAL
/// content or race with the open connection.
///
/// Only the latest copy is kept, next to the database file, named
/// `<name>.pre_v<from>.sqlite` (e.g. `vehicle_history.pre_v1.sqlite`).
class PreUpgradeCopier {
  /// Creates the copier on [fileSystem] (the real one by default).
  const PreUpgradeCopier({
    BackupFileSystem fileSystem = const IoBackupFileSystem(),
  }) : _fs = fileSystem;

  /// File operations used to rotate the copies.
  final BackupFileSystem _fs;

  /// Copies the database behind [db], currently at schema [fromVersion].
  ///
  /// Returns the path of the copy, or `null` for an in-memory database, which
  /// has no file and nothing that could outlive the process. Must be called
  /// outside any transaction: SQLite refuses `VACUUM` inside one.
  Future<String?> copy(DatabaseConnectionUser db, int fromVersion) async {
    final dbPath = await mainDatabasePath(db);
    if (dbPath == null) return null;

    final separator = dbPath.lastIndexOf(RegExp(r'[/\\]'));
    final directory = dbPath.substring(0, separator);
    final fileName = dbPath.substring(separator + 1);
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final copyPrefix = '$stem.pre_v';
    String pathOf(String name) => '$directory${dbPath[separator]}$name';

    final target = pathOf('$copyPrefix$fromVersion.sqlite');
    final temporary = '$target.tmp';

    // Write to a temporary name first, so an interrupted copy never replaces
    // a good one. VACUUM INTO refuses to overwrite an existing file.
    await _fs.deleteIfExists(temporary);
    await db.customStatement('VACUUM INTO ?', [temporary]);

    // Only now that the new copy exists, drop the older ones.
    for (final name in await _fs.listFileNames(directory)) {
      if (name.startsWith(copyPrefix) && name.endsWith('.sqlite')) {
        await _fs.deleteIfExists(pathOf(name));
      }
    }
    await _fs.rename(temporary, target);
    return target;
  }

  /// Path of the main database file, or `null` when it is in memory.
  static Future<String?> mainDatabasePath(DatabaseConnectionUser db) async {
    final rows = await db.customSelect('PRAGMA database_list').get();
    for (final row in rows) {
      if (row.read<String>('name') == 'main') {
        final file = row.read<String>('file');
        return file.isEmpty ? null : file;
      }
    }
    return null;
  }
}

/// Runs a schema upgrade so that it can never lose or corrupt data.
///
/// 1. A database newer than the app ([from] > [to]) is refused with
///    [DatabaseNewerThanAppException]; nothing is written.
/// 2. [copier] copies the database file before anything changes.
/// 3. [steps], the foreign key check and the new `user_version` run in one
///    transaction. If `PRAGMA foreign_key_check` reports any row, it throws
///    [MigrationIntegrityException] and everything is rolled back: the
///    database stays at [from] and the copy is kept.
///
/// Foreign keys are switched off for the steps (SQLite's documented
/// procedure for recreating tables) and enforced again by `beforeOpen`.
Future<void> runSafeUpgrade({
  required GeneratedDatabase db,
  required Migrator migrator,
  required int from,
  required int to,
  required OnUpgrade steps,
  required PreUpgradeCopier copier,
}) async {
  if (from > to) {
    throw DatabaseNewerThanAppException(from, to);
  }

  await copier.copy(db, from);

  // Not allowed inside a transaction, so it is set before opening one.
  await db.customStatement('PRAGMA foreign_keys = OFF');
  await db.transaction(() async {
    await steps(migrator, from, to);

    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    if (violations.isNotEmpty) {
      throw MigrationIntegrityException(from, to, violations.length);
    }

    // Recorded in the same transaction as the steps, so a crash can never
    // leave a migrated schema labelled with the old version. Drift writes
    // the same value again after a successful open.
    await db.customStatement('PRAGMA user_version = $to');
  });
}
