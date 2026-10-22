import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../shared/constants/app_version.dart';
import 'attachments/attachment_picker.dart';
import 'attachments/attachment_staging.dart';
import 'attachments/attachment_store.dart';
import 'attachments/file_opener.dart';
import 'backup/backup_file_picker.dart';
import 'backup/backup_service.dart';
import 'catalog/country_names.dart';
import 'catalog/vehicle_catalog.dart';
import 'db/app_database.dart';
import 'platform/native_files.dart';
import 'platform/temporary_files.dart';
import 'repositories/attachment_repository.dart';
import 'repositories/attachment_writer.dart';
import 'repositories/drift_attachment_repository.dart';
import 'repositories/drift_log_entry_repository.dart';
import 'repositories/drift_mileage_reading_repository.dart';
import 'repositories/drift_owner_repository.dart';
import 'repositories/drift_vehicle_repository.dart';
import 'repositories/log_entry_repository.dart';
import 'repositories/mileage_reading_repository.dart';
import 'repositories/owner_repository.dart';
import 'repositories/repository_support.dart';
import 'repositories/settings_repository.dart';
import 'repositories/trash_cleanup_service.dart';
import 'repositories/vehicle_repository.dart';

/// The single [AppDatabase] of the app, opened once and closed when the
/// [ProviderScope] is disposed.
///
/// Invalidating it is how the database is closed and reopened at runtime,
/// after an import replaced the file: the old instance is closed (again,
/// harmlessly), a new one is created on the same file, [databaseReadyProvider]
/// opens it and runs the cleanup as on any start, and every repository and
/// screen provider that depends on it is rebuilt on the new connection.
///
/// Tests override it with an in-memory database, or override the repository
/// providers below with fakes.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// The application support directory, where the database file and the
/// attachment files live. Resolved once, before the database opens.
final appSupportDirectoryProvider = FutureProvider<String>(
  (ref) async => (await getApplicationSupportDirectory()).path,
);

/// The attachment files under the application support directory.
///
/// Read only once [databaseReadyProvider] has completed, which waits for
/// the directory; tests override it with an in-memory store.
final attachmentStoreProvider = Provider<AttachmentStore>(
  (ref) => IoAttachmentStore(
    ref.watch(appSupportDirectoryProvider).requireValue,
  ),
);

/// Completes once the database is open, any pending migration has run, and
/// the 30-day Trash cleanup and the attachment sweep have had their turn.
///
/// Fails with the error that stopped the opening, such as
/// `DatabaseNewerThanAppException`; the app then shows the startup error
/// screen instead of the router. Never retried automatically: a refused or
/// failed upgrade does not fix itself, and retrying would only repeat it.
///
/// First the app's cache is emptied (`wipeTemporaryDirectorySafely`): the
/// copies the pickers left and the files prepared for sharing.
///
/// The cleanup runs here, once per app start (this provider is created once
/// and never retried), and only after a successful opening. Its failure is
/// logged and never stops the start (`runStartupCleanupSafely`). Then the
/// staging directory is wiped and the orphan files deleted
/// (`runAttachmentSweepSafely`), which never stops the start either.
final databaseReadyProvider = FutureProvider<void>(
  (ref) async {
    await ref.watch(appSupportDirectoryProvider.future);
    // Before the database opens: nothing uses the cache yet.
    await wipeTemporaryDirectorySafely(getTemporaryDirectory);
    final db = ref.watch(appDatabaseProvider);
    await db.open();
    await runStartupCleanupSafely(
      ref.read(trashCleanupServiceProvider),
      systemUtcClock(),
    );
    await runAttachmentSweepSafely(
      ref.read(attachmentStoreProvider),
      db.attachmentsDao.allRelativePaths,
    );
  },
  retry: (retryCount, error) => null,
);

/// The [TrashCleanupService] on the app database.
final trashCleanupServiceProvider = Provider<TrashCleanupService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TrashCleanupService(
    db.trashDao,
    db.auditLogDao,
    ref.watch(attachmentStoreProvider),
  );
});

/// The [AttachmentWriter] on the app database, shared by the attachment and
/// history entry repositories.
final attachmentWriterProvider = Provider<AttachmentWriter>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return AttachmentWriter(
    db.attachmentsDao,
    db.auditLogDao,
    ref.watch(attachmentStoreProvider),
  );
});

/// The [AttachmentRepository] on the app database.
final attachmentRepositoryProvider = Provider<AttachmentRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DriftAttachmentRepository(
    db.attachmentsDao,
    ref.watch(attachmentWriterProvider),
  );
});

/// Copies picked files into a form session's staging directory.
final attachmentStagingProvider = Provider<AttachmentStaging>(
  (ref) => AttachmentStaging(ref.watch(attachmentStoreProvider)),
);

/// The camera, gallery and file pickers for attachments.
final attachmentPickerProvider = Provider<AttachmentPicker>(
  (ref) => const PlatformAttachmentPicker(),
);

/// Opens PDF and other attachments with the phone's own app.
final fileOpenerProvider = Provider<FileOpener>(
  (ref) => const PlatformFileOpener(),
);

/// The native "save as" and free-space channel of `MainActivity.kt`.
final nativeFilesProvider = Provider<NativeFiles>(
  (ref) => const MethodChannelNativeFiles(),
);

/// The [OwnerRepository] on the app database.
final ownerRepositoryProvider = Provider<OwnerRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DriftOwnerRepository(db.ownersDao, db.auditLogDao);
});

/// The [VehicleRepository] on the app database.
final vehicleRepositoryProvider = Provider<VehicleRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DriftVehicleRepository(
    db.vehiclesDao,
    db.mileageReadingsDao,
    db.trashDao,
    db.auditLogDao,
    attachmentFiles: ref.watch(attachmentStoreProvider),
  );
});

/// The [LogEntryRepository] on the app database.
final logEntryRepositoryProvider = Provider<LogEntryRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DriftLogEntryRepository(
    db.logEntriesDao,
    db.auditLogDao,
    attachments: ref.watch(attachmentWriterProvider),
  );
});

/// The [MileageReadingRepository] on the app database.
final mileageReadingRepositoryProvider =
    Provider<MileageReadingRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DriftMileageReadingRepository(db.mileageReadingsDao, db.auditLogDao);
});

/// The [SettingsRepository] on the app database.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DriftSettingsRepository(db.settingsDao);
});

/// The [BackupService] on the app database. The import opens new
/// connections on the same file with [AppDatabase.new].
final backupServiceProvider = Provider<BackupService>((ref) {
  final nativeFiles = ref.watch(nativeFilesProvider);
  return BackupService(
    database: ref.watch(appDatabaseProvider),
    openDatabase: AppDatabase.new,
    appVersion: appVersion,
    freeBytes: nativeFiles.freeBytes,
  );
});

/// The system dialog that opens backup packages.
final backupFilePickerProvider = Provider<BackupFilePicker>(
  (ref) => const PlatformBackupFilePicker(),
);

/// Asset holding the make / model catalogue (see `tool/`).
const String vehicleCatalogAsset = 'assets/catalog/vehicle_catalog.json';

/// Asset holding the country names (see `tool/`).
const String countryNamesAsset = 'assets/countries/country_names.json';

/// The bundled make / model catalogue, loaded once on first use and kept
/// for the life of the app. Tests override it with a small fixture.
final vehicleCatalogProvider = FutureProvider<VehicleCatalog>(
  (ref) async =>
      VehicleCatalog.fromJson(await rootBundle.loadString(vehicleCatalogAsset)),
);

/// The bundled country names, loaded once on first use and kept for the
/// life of the app. Tests override it with a small fixture.
final countryNamesProvider = FutureProvider<CountryNames>(
  (ref) async =>
      CountryNames.fromJson(await rootBundle.loadString(countryNamesAsset)),
);
