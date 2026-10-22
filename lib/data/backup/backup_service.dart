import 'package:flutter/foundation.dart' show debugPrint;

import '../attachments/attachment_store.dart';
import '../db/app_database.dart';
import '../db/database_file_inspector.dart';
import '../db/upgrade_safety.dart';
import '../models/attachment.dart';
import '../models/audit_entry.dart';
import '../models/backup_manifest.dart';
import '../models/setting_key.dart';
import '../repositories/repository_support.dart';
import '../repositories/settings_repository.dart';
import '../repositories/trash_cleanup_service.dart';
import 'backup_exceptions.dart';
import 'backup_files.dart';
import 'backup_package.dart';

/// A package built by [BackupService.exportPackage], ready to be saved.
class ExportedPackage {
  /// Creates the exported package.
  const ExportedPackage({
    required this.fileName,
    required this.path,
    required this.manifest,
    required this.previousLastExportAt,
  });

  /// Suggested file name, `vehicle-history-YYYYMMDD-HHmm.zip`.
  final String fileName;

  /// The temporary zip on disk, deleted by [BackupService.deleteExport]
  /// once it has been saved (or not).
  final String path;

  /// What the package holds, as written into its `manifest.json`.
  final BackupManifest manifest;

  /// The `last_export_at` value the export replaced (raw text, `null` when
  /// unset), put back by [BackupService.discardExport] if the package is
  /// never saved.
  final String? previousLastExportAt;
}

/// What a package holds, as checked before the import confirmation.
class ImportPreview {
  /// Creates the preview.
  const ImportPreview({
    required this.manifest,
    required this.attachmentCount,
    required this.attachmentBytes,
    required this.missingFiles,
  });

  /// The package's manifest.
  final BackupManifest manifest;

  /// Attachment files in the package that its database refers to.
  final int attachmentCount;

  /// Their total size in bytes.
  final int attachmentBytes;

  /// Attachment rows of the package's database whose file is not in the
  /// package. Tolerated: those rows are imported and show "File not found".
  final int missingFiles;
}

/// Tables a database at [schemaVersion] must have to be imported.
///
/// Every version keeps the tables of the previous ones: v1 owners, vehicles
/// and the audit log; v3 the history; v4 the odometer readings; v6 the
/// settings; v7 the attachments.
Set<String> requiredTablesAt(int schemaVersion) => {
      'owners',
      'vehicles',
      'audit_log',
      if (schemaVersion >= 3) 'log_entries',
      if (schemaVersion >= 4) 'mileage_readings',
      if (schemaVersion >= 6) 'settings',
      if (schemaVersion >= 7) 'attachments',
    };

/// Room kept free on top of what an import needs, so the phone is not left
/// with a full disk.
const int importSpaceMargin = 20 * 1024 * 1024;

/// Exports the whole database and every attachment file as a backup
/// package and imports one back, replacing every local row and file
/// (`Docs/05_sync_and_storage.md`).
///
/// Works next to the live database file: the temporary files, the
/// `attachments/` directory and the `pre_import` safety copies live in the
/// same directory (the application support directory on the phone). The
/// package is written and read file to file, never held in memory.
class BackupService {
  /// Creates the service on the live [database].
  ///
  /// [openDatabase] opens a new connection on the same file; the import uses
  /// it to open (and migrate) the imported file and, on failure, to check
  /// the restored one. [appVersion] goes into the manifest. [freeBytes]
  /// tells how much space is free on the volume of a directory (`null`
  /// when unknown: the check is skipped).
  BackupService({
    required AppDatabase database,
    required AppDatabase Function() openDatabase,
    required String appVersion,
    BackupFiles files = const IoBackupFiles(),
    DatabaseFileInspector inspector = const SqliteDatabaseFileInspector(),
    Future<int?> Function(String directory)? freeBytes,
    UtcClock clock = systemUtcClock,
  })  : _database = database,
        _openDatabase = openDatabase,
        _appVersion = appVersion,
        _files = files,
        _inspector = inspector,
        _freeBytes = freeBytes ?? _unknownFreeBytes,
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

  /// Free space on the volume of a directory.
  final Future<int?> Function(String directory) _freeBytes;

  /// Source of the export and audit instants.
  final UtcClock _clock;

  /// The default of [_freeBytes]: unknown.
  static Future<int?> _unknownFreeBytes(String directory) async => null;

  /// Builds a package with a consistent copy of the whole database (Trash
  /// and audit log included), every attachment file (those of deleted
  /// attachments too) and its manifest, as a temporary zip on disk.
  ///
  /// The database copy is written with `VACUUM INTO` to a temporary file
  /// next to the database, then streamed into the zip with the attachment
  /// files one by one. The copy is deleted afterwards; the zip is deleted by
  /// [deleteExport] once saved, or here if anything fails. An attachment row
  /// whose file is missing is left out of the zip (its row is in the
  /// database copy, so the import reports it as a missing file).
  ///
  /// `last_export_at` is set to the export instant **before** the copy, so
  /// the package carries its own export date and an import shows it. If the
  /// package is then not saved, the caller puts the previous value back with
  /// [discardExport]; a failure here puts it back itself.
  Future<ExportedPackage> exportPackage() async {
    final paths = await _paths();
    final settings = _settings();
    final exportedAt = utcNow(_clock);
    await _files.deleteIfExists(paths.exportTemp);
    await _files.deleteIfExists(paths.packageTemp);
    final previousLastExportAt = await settings.read(SettingKey.lastExportAt);
    await settings.writeLastExportAt(exportedAt);
    try {
      final dao = _database.backupDao;
      final counts = await dao.liveCounts();
      final lastModifiedAt = await dao.lastModifiedAt();
      await dao.vacuumInto(paths.exportTemp);

      final store = IoAttachmentStore(paths.directory);
      final attachments = <String, String>{};
      var attachmentBytes = 0;
      final relativePaths = await _database.attachmentsDao.allRelativePaths();
      for (final relativePath in relativePaths.toList()..sort()) {
        final path = store.absolutePath(relativePath);
        if (!isAttachmentEntryName(relativePath) ||
            !await _files.exists(path)) {
          continue;
        }
        attachments[relativePath] = path;
        attachmentBytes += await _files.sizeOf(path);
      }

      final manifest = BackupManifest(
        formatVersion: BackupManifest.currentFormatVersion,
        schemaVersion: _database.schemaVersion,
        appVersion: _appVersion,
        exportedAt: exportedAt,
        counts: BackupCounts(
          owners: counts.owners,
          vehicles: counts.vehicles,
          logEntries: counts.logEntries,
          mileageReadings: counts.mileageReadings,
          attachments: attachments.length,
        ),
        lastModifiedAt: lastModifiedAt,
        attachmentsBytes: attachmentBytes,
      );
      await writeBackupPackage(
        paths.packageTemp,
        manifest: manifest,
        databasePath: paths.exportTemp,
        attachments: attachments,
      );
      return ExportedPackage(
        fileName: backupFileName(exportedAt.toLocal()),
        path: paths.packageTemp,
        manifest: manifest,
        previousLastExportAt: previousLastExportAt,
      );
    } on Object {
      await settings.write(SettingKey.lastExportAt, previousLastExportAt);
      await _files.deleteIfExists(paths.packageTemp);
      rethrow;
    } finally {
      await _files.deleteIfExists(paths.exportTemp);
    }
  }

  /// Puts back the `last_export_at` value that [package] replaced, for a
  /// package the user did not save (save dialog cancelled or failed): the
  /// Backup page must not show an export that left no file anywhere.
  Future<void> discardExport(ExportedPackage package) =>
      _settings().write(SettingKey.lastExportAt, package.previousLastExportAt);

  /// Deletes the temporary zip of [package], saved or not.
  Future<void> deleteExport(ExportedPackage package) =>
      _files.deleteIfExists(package.path);

  /// Where a package picked for an import is copied before it is checked:
  /// a temporary file next to the database.
  Future<String> pickedPackagePath() async => (await _paths()).pickedTemp;

  /// Deletes the copy of a picked package at [pickedPackagePath], imported
  /// or not.
  Future<void> deletePickedPackage() async =>
      _files.deleteIfExists((await _paths()).pickedTemp);

  /// The settings of the live database, stamped with the service clock.
  SettingsRepository _settings() =>
      DriftSettingsRepository(_database.settingsDao, clock: _clock);

  /// Checks that the file at [packagePath] is a package this app can
  /// import, without touching the data, and describes it for the
  /// confirmation dialog.
  ///
  /// Throws [BackupRejectedException] with the first problem found.
  Future<ImportPreview> inspectPackage(String packagePath) async {
    final paths = await _paths();
    final package = await BackupPackageReader.open(packagePath);
    try {
      return (await _validate(package, paths)).preview;
    } finally {
      await package.close();
      await _files.deleteIfExists(paths.importTemp);
    }
  }

  /// Replaces the whole local database and the attachment files with the
  /// package at [packagePath] and returns its manifest.
  ///
  /// 1. The package is validated as by [inspectPackage]; a rejection throws
  ///    [BackupRejectedException] and changes nothing. Its database and the
  ///    attachment files its rows refer to are unpacked next to the live
  ///    ones.
  /// 2. The `pre_import` material of the previous import is set aside; the
  ///    current data is copied to `vehicle_history.pre_import.sqlite` with
  ///    `VACUUM INTO`, consistent whatever the WAL state; then the live
  ///    connection is closed.
  /// 3. The current `attachments/` directory becomes
  ///    `attachments.pre_import/`, the unpacked one takes its place, and the
  ///    imported database takes the place of the live file, without the old
  ///    `-wal` / `-shm` files, which belong to the replaced file.
  /// 4. A new connection opens it: `runSafeUpgrade` migrates an older schema
  ///    (with its own `pre_v<n>` copy), the 30-day Trash cleanup runs as on
  ///    any start, and an `import` row is added to the audit log.
  /// 5. The `pre_import` material of the previous import is deleted.
  ///
  /// If step 2 or anything after it fails, the database copy and the
  /// attachments directory are both put back and the database checked, and
  /// [BackupImportFailedException] is thrown: the data is as before the
  /// import. If putting it back fails too, [BackupRestoreFailedException] is
  /// thrown and the `pre_import` material is kept.
  ///
  /// The live connection is closed whenever this returns or throws anything
  /// but a rejection: the caller must open a new one.
  Future<BackupManifest> importPackage(String packagePath) async {
    final paths = await _paths();
    final package = await BackupPackageReader.open(packagePath);
    var replaced = false;
    var attachmentsMoved = false;
    var newAttachmentsInPlace = false;
    try {
      final validated = await _validate(package, paths);
      await _unpackAttachments(package, validated.referenced, paths);

      try {
        await _setPreviousImportAside(paths);
        await _files.deleteIfExists(paths.preImportTemp);
        await _database.backupDao.vacuumInto(paths.preImportTemp);
        await _files.rename(paths.preImportTemp, paths.preImport);
        await _database.close();

        replaced = true;
        if (await _files.exists(paths.attachments)) {
          await _files.rename(paths.attachments, paths.preImportAttachments);
          attachmentsMoved = true;
        }
        await _files.rename(paths.importAttachments, paths.attachments);
        newAttachmentsInPlace = true;
        await _deleteSidecars(paths.database);
        await _files.rename(paths.importTemp, paths.database);

        await _openImported(paths);
        await _deletePreviousImport(paths);
        return validated.preview.manifest;
        // Deliberately catches everything, errors included: whatever stopped
        // the import, the previous data must come back.
        // ignore: avoid_catches_without_on_clauses
      } catch (error, stackTrace) {
        debugPrint(
          'Import failed, restoring previous data: $error\n$stackTrace',
        );
        // Before the swap the live files were never touched; the live
        // connection may be closed already, which the caller handles anyway.
        if (replaced) {
          await _restorePreImport(
            paths,
            error,
            attachmentsMoved: attachmentsMoved,
            newAttachmentsInPlace: newAttachmentsInPlace,
          );
          // The data is back: the material of the import before is no longer
          // needed (only the latest `pre_import` is kept).
          await _deletePreviousImport(paths);
        }
        throw BackupImportFailedException(error);
      }
    } finally {
      await package.close();
      await _files.deleteIfExists(paths.importTemp);
      await _files.deleteIfExists(paths.preImportTemp);
      await _files.deleteDirectoryIfExists(paths.importAttachments);
    }
  }

  /// Unpacks the attachment files of [package] that [referenced] names into
  /// the temporary directory next to `attachments/`. Nothing live is
  /// touched; a failure is an import failure with the data unchanged.
  Future<void> _unpackAttachments(
    BackupPackageReader package,
    Set<String> referenced,
    _BackupPaths paths,
  ) async {
    await _files.deleteDirectoryIfExists(paths.importAttachments);
    await _files.createDirectory(paths.importAttachments);
    try {
      for (final name in package.attachmentEntries.keys) {
        if (!referenced.contains(name)) continue;
        await package.extractAttachment(
          name,
          paths.inImportAttachments(name),
        );
      }
    } on Object catch (error) {
      throw BackupImportFailedException(error);
    }
  }

  /// Moves the `pre_import` material of the previous import aside, so it
  /// survives until this import has succeeded.
  Future<void> _setPreviousImportAside(_BackupPaths paths) async {
    await _deletePreviousImport(paths);
    if (await _files.exists(paths.preImport)) {
      await _files.rename(paths.preImport, paths.previousPreImport);
    }
    if (await _files.exists(paths.preImportAttachments)) {
      await _files.rename(
        paths.preImportAttachments,
        paths.previousPreImportAttachments,
      );
    }
  }

  /// Deletes the `pre_import` material set aside by
  /// [_setPreviousImportAside].
  Future<void> _deletePreviousImport(_BackupPaths paths) async {
    await _files.deleteIfExists(paths.previousPreImport);
    await _files.deleteDirectoryIfExists(paths.previousPreImportAttachments);
  }

  /// Opens the imported file on a new connection: migration, startup
  /// cleanup and the `import` audit row. Always closes the connection.
  Future<void> _openImported(_BackupPaths paths) async {
    final db = _openDatabase();
    try {
      await db.open();
      final store = IoAttachmentStore(paths.directory);
      await runStartupCleanupSafely(
        TrashCleanupService(db.trashDao, db.auditLogDao, store),
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

  /// Puts the `pre_import` copy back in place of the database and the
  /// attachments directory as it was: the imported one removed (when
  /// [newAttachmentsInPlace]) and `attachments.pre_import/` renamed back
  /// (when [attachmentsMoved]). Then checks that the database opens. The
  /// database copy itself is kept.
  ///
  /// Throws [BackupRestoreFailedException] if that fails too.
  Future<void> _restorePreImport(
    _BackupPaths paths,
    Object cause, {
    required bool attachmentsMoved,
    required bool newAttachmentsInPlace,
  }) async {
    try {
      if (newAttachmentsInPlace) {
        await _files.deleteDirectoryIfExists(paths.attachments);
      }
      if (attachmentsMoved) {
        await _files.rename(paths.preImportAttachments, paths.attachments);
      }
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

  /// Validates the opened [package]: its database entry is an SQLite file
  /// of the manifest's schema, no newer than this app's, intact and with
  /// the tables of its version; and the phone has room for it.
  ///
  /// The database is unpacked to the import temporary file, which the
  /// caller deletes or moves into place.
  Future<({ImportPreview preview, Set<String> referenced})> _validate(
    BackupPackageReader package,
    _BackupPaths paths,
  ) async {
    final schemaVersion = package.manifest.schemaVersion;
    await _files.deleteIfExists(paths.importTemp);
    await package.extractDatabase(paths.importTemp);
    final header = await _files.readHead(paths.importTemp, sqliteHeaderLength);
    if (sqliteUserVersion(header) != schemaVersion) {
      throw const BackupRejectedException(BackupRejection.notADatabase);
    }
    if (schemaVersion > _database.schemaVersion) {
      throw const BackupRejectedException(BackupRejection.newerSchema);
    }

    final report = await _inspector.inspect(paths.importTemp, schemaVersion);
    if (!report.intact) {
      throw const BackupRejectedException(BackupRejection.corruptDatabase);
    }
    if (!report.tableNames.containsAll(requiredTablesAt(schemaVersion))) {
      throw const BackupRejectedException(BackupRejection.missingTables);
    }

    final referenced = {
      for (final path in report.attachmentPaths)
        if (package.attachmentEntries.containsKey(path)) path,
    };
    final attachmentBytes = referenced.fold(
      0,
      (sum, name) => sum + package.attachmentEntries[name]!.size,
    );

    // Room for the unpacked files and for the `pre_import` copy of the
    // current database (the current attachments are renamed, not copied).
    // The imported database is already unpacked.
    final free = await _freeBytes(paths.directory);
    final needed = attachmentBytes +
        await _files.sizeOf(paths.database) +
        importSpaceMargin;
    if (free != null && free < needed) {
      throw const BackupRejectedException(BackupRejection.notEnoughSpace);
    }

    return (
      preview: ImportPreview(
        manifest: package.manifest,
        attachmentCount: referenced.length,
        attachmentBytes: attachmentBytes,
        missingFiles: report.attachmentPaths.length - referenced.length,
      ),
      referenced: referenced,
    );
  }

  /// The paths found by the first [_paths], kept: after an import the live
  /// connection is closed and can no longer be asked for its file.
  _BackupPaths? _knownPaths;

  /// The paths of the live database file and of the files next to it.
  Future<_BackupPaths> _paths() async {
    final known = _knownPaths;
    if (known != null) return known;
    final path = await PreUpgradeCopier.mainDatabasePath(_database);
    if (path == null) {
      throw StateError('The backup needs a database file, not in memory');
    }
    return _knownPaths = _BackupPaths(path);
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
            : database,
        directory = _parentOf(database);

  /// The directory part of [path], whatever the separator.
  static String _parentOf(String path) {
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    return cut <= 0 ? '.' : path.substring(0, cut);
  }

  /// The live database file, e.g. `.../vehicle_history.sqlite`.
  final String database;

  /// The directory holding [database] and `attachments/`: the application
  /// support directory on the phone.
  final String directory;

  /// [database] without its `.sqlite` extension.
  final String _stem;

  /// Separator used to build the paths below.
  String get _sep => database.contains(r'\') ? r'\' : '/';

  /// The live attachments directory.
  String get attachments => '$directory$_sep$attachmentsDirName';

  /// Copy of the data from before the last import.
  String get preImport => '$_stem.pre_import.sqlite';

  /// [preImport] while it is being written.
  String get preImportTemp => '$_stem.pre_import.sqlite.tmp';

  /// The attachments directory from before the last import.
  String get preImportAttachments => '$attachments.pre_import';

  /// [preImport] of the import before the current one, kept until the
  /// current one has succeeded.
  String get previousPreImport => '$_stem.pre_import.previous.sqlite';

  /// [preImportAttachments] of the import before the current one.
  String get previousPreImportAttachments => '$attachments.pre_import.previous';

  /// The database copy being exported.
  String get exportTemp => '$_stem.export.tmp';

  /// The copy of a package picked for an import.
  String get pickedTemp => '$_stem.picked.zip.tmp';

  /// The zip being exported, until it is saved.
  String get packageTemp => '$_stem.package.zip.tmp';

  /// The database of a package being validated or imported, before it takes
  /// the place of [database].
  String get importTemp => '$_stem.import.tmp';

  /// The attachment files of a package being imported, before the
  /// directory takes the place of [attachments].
  String get importAttachments => '$attachments.import.tmp';

  /// Where the package entry [entryName] (`attachments/<file>`) is unpacked.
  String inImportAttachments(String entryName) =>
      '$importAttachments$_sep${entryName.substring(attachmentsEntryName.length)}';
}
