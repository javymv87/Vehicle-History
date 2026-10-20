import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../db/app_database.dart';
import '../db/database_file_inspector.dart';
import '../db/upgrade_safety.dart';
import '../models/audit_entry.dart';
import '../models/backup_manifest.dart';
import '../repositories/repository_support.dart';
import '../repositories/trash_cleanup_service.dart';
import 'backup_exceptions.dart';
import 'backup_files.dart';
import 'backup_package.dart';

/// A package built by [BackupService.exportPackage], ready to be saved.
class ExportedPackage {
  /// Creates the exported package.
  const ExportedPackage({
    required this.fileName,
    required this.bytes,
    required this.manifest,
  });

  /// Suggested file name, `vehicle-history-YYYYMMDD-HHmm.zip`.
  final String fileName;

  /// The zip itself.
  final Uint8List bytes;

  /// What the package holds, as written into its `manifest.json`.
  final BackupManifest manifest;
}

/// Tables a database at [schemaVersion] must have to be imported.
///
/// Every version keeps the tables of the previous ones: v1 owners, vehicles
/// and the audit log; v3 the history; v4 the odometer readings; v6 the
/// settings.
Set<String> requiredTablesAt(int schemaVersion) => {
      'owners',
      'vehicles',
      'audit_log',
      if (schemaVersion >= 3) 'log_entries',
      if (schemaVersion >= 4) 'mileage_readings',
      if (schemaVersion >= 6) 'settings',
    };

/// Exports the whole database as a backup package and imports one back,
/// replacing every local row (`Docs/05_sync_and_storage.md`).
///
/// Works next to the live database file: the temporary files and the
/// `pre_import` safety copy live in the same directory (the application
/// support directory on the phone).
class BackupService {
  /// Creates the service on the live [database].
  ///
  /// [openDatabase] opens a new connection on the same file; the import uses
  /// it to open (and migrate) the imported file and, on failure, to check
  /// the restored one. [appVersion] goes into the manifest.
  BackupService({
    required AppDatabase database,
    required AppDatabase Function() openDatabase,
    required String appVersion,
    BackupFiles files = const IoBackupFiles(),
    DatabaseFileInspector inspector = const SqliteDatabaseFileInspector(),
    UtcClock clock = systemUtcClock,
  })  : _database = database,
        _openDatabase = openDatabase,
        _appVersion = appVersion,
        _files = files,
        _inspector = inspector,
        _clock = clock;

  /// The live database: exported from, and closed before an import.
  final AppDatabase _database;

  /// Opens a new connection on the database file.
  final AppDatabase Function() _openDatabase;

  /// Version of the app, written into the manifest.
  final String _appVersion;

  /// File operations next to the database file.
  final BackupFiles _files;

  /// Checks the database inside a package.
  final DatabaseFileInspector _inspector;

  /// Source of the export and audit instants.
  final UtcClock _clock;

  /// Builds a package with a consistent copy of the whole database (Trash
  /// and audit log included) and its manifest.
  ///
  /// The copy is written with `VACUUM INTO` to a temporary file next to the
  /// database, which is deleted afterwards, also on failure.
  Future<ExportedPackage> exportPackage() async {
    final paths = await _paths();
    final dao = _database.backupDao;
    final exportedAt = utcNow(_clock);
    await _files.deleteIfExists(paths.exportTemp);
    try {
      final counts = await dao.liveCounts();
      final lastModifiedAt = await dao.lastModifiedAt();
      await dao.vacuumInto(paths.exportTemp);
      final manifest = BackupManifest(
        formatVersion: BackupManifest.currentFormatVersion,
        schemaVersion: _database.schemaVersion,
        appVersion: _appVersion,
        exportedAt: exportedAt,
        counts: counts,
        lastModifiedAt: lastModifiedAt,
      );
      final database = await _files.readBytes(paths.exportTemp);
      return ExportedPackage(
        fileName: backupFileName(exportedAt.toLocal()),
        bytes: encodeBackupPackage(manifest, database),
        manifest: manifest,
      );
    } finally {
      await _files.deleteIfExists(paths.exportTemp);
    }
  }

  /// Checks that [bytes] is a package this app can import, without touching
  /// the data, and returns its manifest for the confirmation dialog.
  ///
  /// Throws [BackupRejectedException] with the first problem found.
  Future<BackupManifest> inspectPackage(Uint8List bytes) async =>
      (await _validate(bytes, await _paths())).manifest;

  /// Replaces the whole local database with the one in the package [bytes]
  /// and returns its manifest.
  ///
  /// 1. The package is validated as by [inspectPackage]; a rejection throws
  ///    [BackupRejectedException] and changes nothing.
  /// 2. The current data is copied to `vehicle_history.pre_import.sqlite`
  ///    (replacing an older one) with `VACUUM INTO`, consistent whatever
  ///    the WAL state; then the live connection is closed.
  /// 3. The imported file takes the place of the database, without the old
  ///    `-wal` / `-shm` files, which belong to the replaced file.
  /// 4. A new connection opens it: `runSafeUpgrade` migrates an older schema
  ///    (with its own `pre_v<n>` copy), the 30-day Trash cleanup runs as on
  ///    any start, and an `import` row is added to the audit log.
  ///
  /// If step 2 or anything after it fails, the `pre_import` copy is put back
  /// and checked, and [BackupImportFailedException] is thrown: the data is
  /// as before the import. If putting it back fails too,
  /// [BackupRestoreFailedException] is thrown and the copy is kept.
  ///
  /// The live connection is closed whenever this returns or throws anything
  /// but a rejection: the caller must open a new one.
  Future<BackupManifest> importPackage(Uint8List bytes) async {
    final paths = await _paths();
    final package = await _validate(bytes, paths);

    var replaced = false;
    try {
      await _files.writeBytes(paths.importTemp, package.database);

      await _files.deleteIfExists(paths.preImportTemp);
      await _database.backupDao.vacuumInto(paths.preImportTemp);
      await _files.rename(paths.preImportTemp, paths.preImport);
      await _database.close();

      replaced = true;
      await _deleteSidecars(paths.database);
      await _files.rename(paths.importTemp, paths.database);

      await _openImported();
      return package.manifest;
      // Deliberately catches everything, errors included: whatever stopped
      // the import, the previous data must come back.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stackTrace) {
      debugPrint('Import failed, restoring previous data: $error\n$stackTrace');
      // Before the swap the database file was never touched; the live
      // connection may be closed already, which the caller handles anyway.
      if (replaced) await _restorePreImport(paths, error);
      throw BackupImportFailedException(error);
    } finally {
      await _files.deleteIfExists(paths.importTemp);
      await _files.deleteIfExists(paths.preImportTemp);
    }
  }

  /// Opens the imported file on a new connection: migration, startup
  /// cleanup and the `import` audit row. Always closes the connection.
  Future<void> _openImported() async {
    final db = _openDatabase();
    try {
      await db.open();
      await runStartupCleanupSafely(
        TrashCleanupService(db.trashDao, db.auditLogDao),
        utcNow(_clock),
      );
      await db.auditLogDao.insertEntry(
        AuditEntry(
          id: newId(),
          entityType: AuditEntityType.database,
          entityId: AuditEntry.databaseEntityId,
          operation: AuditOperation.import,
          at: utcNow(_clock),
        ),
      );
    } finally {
      await db.close();
    }
  }

  /// Puts the `pre_import` copy back in place of the database and checks
  /// that it opens. The copy itself is kept.
  ///
  /// Throws [BackupRestoreFailedException] if that fails too.
  Future<void> _restorePreImport(_BackupPaths paths, Object cause) async {
    try {
      await _deleteSidecars(paths.database);
      await _files.copy(paths.preImport, paths.database);
      final db = _openDatabase();
      try {
        await db.open();
      } finally {
        await db.close();
      }
      // Reported whatever it is: the caller must know the restore failed.
      // ignore: avoid_catches_without_on_clauses
    } catch (restoreError) {
      throw BackupRestoreFailedException(cause, restoreError);
    }
  }

  /// Deletes the `-wal` and `-shm` files of the database at [path]: they
  /// belong to the file being replaced, and SQLite would otherwise apply
  /// them to the new one.
  Future<void> _deleteSidecars(String path) async {
    await _files.deleteIfExists('$path-wal');
    await _files.deleteIfExists('$path-shm');
  }

  /// Validates the package [bytes]: its structure ([decodeBackupPackage]),
  /// a schema no newer than this app's, then the integrity and the tables
  /// of the database on a temporary copy, deleted afterwards.
  Future<DecodedBackupPackage> _validate(
    Uint8List bytes,
    _BackupPaths paths,
  ) async {
    final package = decodeBackupPackage(bytes);
    final schemaVersion = package.manifest.schemaVersion;
    if (schemaVersion > _database.schemaVersion) {
      throw const BackupRejectedException(BackupRejection.newerSchema);
    }

    await _files.writeBytes(paths.inspectTemp, package.database);
    final DatabaseFileReport report;
    try {
      report = await _inspector.inspect(paths.inspectTemp, schemaVersion);
    } finally {
      await _files.deleteIfExists(paths.inspectTemp);
    }
    if (!report.intact) {
      throw const BackupRejectedException(BackupRejection.corruptDatabase);
    }
    if (!report.tableNames.containsAll(requiredTablesAt(schemaVersion))) {
      throw const BackupRejectedException(BackupRejection.missingTables);
    }
    return package;
  }

  /// The paths of the live database file and of the files next to it.
  Future<_BackupPaths> _paths() async {
    final path = await PreUpgradeCopier.mainDatabasePath(_database);
    if (path == null) {
      throw StateError('The backup needs a database file, not in memory');
    }
    return _BackupPaths(path);
  }
}

/// Paths of the database file and of the backup files next to it.
///
/// None of the names starts with `vehicle_history.pre_v`, so the rotation of
/// the pre-upgrade copies never deletes them.
class _BackupPaths {
  /// Derives every path from the database file at [database].
  _BackupPaths(this.database)
      : _stem = database.endsWith('.sqlite')
            ? database.substring(0, database.length - '.sqlite'.length)
            : database;

  /// The live database file, e.g. `.../vehicle_history.sqlite`.
  final String database;

  /// [database] without its `.sqlite` extension.
  final String _stem;

  /// Copy of the data from before the last import.
  String get preImport => '$_stem.pre_import.sqlite';

  /// [preImport] while it is being written.
  String get preImportTemp => '$_stem.pre_import.sqlite.tmp';

  /// The database copy being exported.
  String get exportTemp => '$_stem.export.tmp';

  /// The database of a package being imported, before it takes the place
  /// of [database].
  String get importTemp => '$_stem.import.tmp';

  /// The database of a package being validated.
  String get inspectTemp => '$_stem.inspect.tmp';
}
