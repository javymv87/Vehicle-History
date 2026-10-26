import 'dart:async';

import 'package:vehicle_history/data/attachments/attachment_picker.dart';
import 'package:vehicle_history/data/attachments/file_opener.dart';
import 'package:vehicle_history/data/backup/backup_exceptions.dart';
import 'package:vehicle_history/data/backup/backup_file_picker.dart';
import 'package:vehicle_history/data/backup/backup_service.dart';
import 'package:vehicle_history/data/drive/drive_models.dart';
import 'package:vehicle_history/data/models/backup_manifest.dart';
import 'package:vehicle_history/data/models/setting_key.dart';
import 'package:vehicle_history/data/platform/native_files.dart';
import 'package:vehicle_history/data/repositories/settings_repository.dart';

/// In-memory [SettingsRepository] for widget tests.
class FakeSettingsRepository implements SettingsRepository {
  /// The values, by key.
  final Map<SettingKey, String?> values = {};

  final StreamController<void> _changes = StreamController.broadcast();

  @override
  Future<String?> read(SettingKey key) async => values[key];

  @override
  Stream<String?> watch(SettingKey key) async* {
    yield values[key];
    await for (final _ in _changes.stream) {
      yield values[key];
    }
  }

  @override
  Future<void> write(SettingKey key, String? value) async {
    values[key] = value;
    _changes.add(null);
  }
}

/// [BackupFilePicker] whose dialog answers with a preset value.
class FakeBackupFilePicker implements BackupFilePicker {
  /// Whether the open dialog picks a file (`true`) or is cancelled.
  bool pickResult = false;

  /// Where the picked files were copied to.
  final List<String> copiedTo = [];

  @override
  Future<bool> pickPackage(String copyTo) async {
    if (pickResult) copiedTo.add(copyTo);
    return pickResult;
  }
}

/// [NativeFiles] whose "save as" answers with a preset value.
class FakeNativeFiles implements NativeFiles {
  /// What the save dialog answers.
  SaveFileOutcome saveResult = SaveFileOutcome.saved;

  /// When set, saving throws it.
  Exception? saveFailure;

  /// The saves asked for: source path and suggested name.
  final List<({String sourcePath, String suggestedName})> saves = [];

  /// What [freeBytes] answers.
  int? free;

  /// What the folder picker answers: `true` saves, `false` cancels.
  bool folderChosen = true;

  /// The files saved to a folder, one list per call.
  final List<List<NativeFile>> folderSaves = [];

  /// The files shared, one list per call.
  final List<List<NativeFile>> shares = [];

  @override
  Future<int?> saveFilesToFolder(List<NativeFile> files) async {
    if (!folderChosen) return null;
    folderSaves.add(files);
    return files.length;
  }

  @override
  Future<void> shareFiles(List<NativeFile> files) async => shares.add(files);

  @override
  Future<SaveFileOutcome> saveFile({
    required String sourcePath,
    required String suggestedName,
    required String mimeType,
  }) async {
    saves.add((sourcePath: sourcePath, suggestedName: suggestedName));
    final failure = saveFailure;
    if (failure != null) throw failure;
    return saveResult;
  }

  @override
  Future<int?> freeBytes(String path) async => free;
}

/// [AttachmentPicker] that returns preset files.
class FakeAttachmentPicker implements AttachmentPicker {
  /// What the next pick returns, by source; empty means cancelled.
  final Map<AttachmentSource, List<PickedFile>> files = {};

  /// When set, picking throws it.
  AttachmentPickException? failure;

  /// The sources asked for.
  final List<AttachmentSource> asked = [];

  @override
  Future<List<PickedFile>> pick(AttachmentSource source) async {
    asked.add(source);
    final error = failure;
    if (error != null) throw error;
    return files[source] ?? const [];
  }
}

/// A picked file named [name] with [bytes] as content; [onDeleteSource]
/// is told when the picker's own copy is deleted.
PickedFile pickedFile(
  String name,
  List<int> bytes, {
  String? mimeType,
  void Function()? onDeleteSource,
}) =>
    PickedFile(
      name: name,
      mimeType: mimeType,
      openRead: () => Stream.value(bytes),
      deleteSource: () async => onDeleteSource?.call(),
    );

/// [FileOpener] that records what it was asked to open.
class FakeFileOpener implements FileOpener {
  /// What opening answers.
  OpenFileOutcome outcome = OpenFileOutcome.opened;

  /// The paths opened.
  final List<String> opened = [];

  @override
  Future<OpenFileOutcome> open(String path, String mimeType) async {
    opened.add(path);
    return outcome;
  }
}

/// A manifest for widget tests: 2 vehicles, 41 entries, 7 readings, last
/// modified on 18 October 2026.
final BackupManifest sampleManifest = BackupManifest(
  formatVersion: 1,
  schemaVersion: 6,
  appVersion: '0.6.0+6',
  exportedAt: DateTime.utc(2026, 10, 20, 16, 30),
  counts: const BackupCounts(
    owners: 1,
    vehicles: 2,
    logEntries: 41,
    mileageReadings: 7,
  ),
  lastModifiedAt: DateTime.utc(2026, 10, 18, 12),
);

/// What [FakeBackupService] reports for a package: [sampleManifest], 3
/// attachments of 3.5 MB, 1 file missing.
final ImportPreview samplePreview = ImportPreview(
  manifest: sampleManifest,
  attachmentCount: 3,
  attachmentBytes: 3670016,
  missingFiles: 1,
);

/// [BackupService] that does no file work: it exports [sampleManifest] and
/// accepts or rejects packages as configured.
class FakeBackupService implements BackupService {
  /// Creates the service on [settings], where the export writes
  /// `last_export_at`.
  FakeBackupService(this.settings);

  /// The settings the export writes to.
  final SettingsRepository settings;

  /// When set, inspecting or importing a package throws it.
  Exception? rejectWith;

  /// When set, importing a valid package throws it.
  Exception? importFailure;

  /// How many imports went through.
  int imports = 0;

  @override
  Future<ExportedPackage> exportPackage() async {
    // Like the real service: `last_export_at` is written before the copy.
    final previous = await settings.read(SettingKey.lastExportAt);
    await settings.writeLastExportAt(sampleManifest.exportedAt);
    exports++;
    return ExportedPackage(
      fileName: 'vehicle-history-20261020-1830.zip',
      path: '/fake/package.zip.tmp',
      manifest: sampleManifest,
      previousLastExportAt: previous,
    );
  }

  /// How many packages were exported, and how many of their temporary
  /// files deleted.
  int exports = 0;

  /// How many temporary packages were deleted.
  int deletedExports = 0;

  /// How many picked copies were deleted.
  int deletedPicks = 0;

  @override
  Future<void> deleteExport(ExportedPackage package) async => deletedExports++;

  @override
  Future<String> pickedPackagePath() async => '/fake/picked.zip.tmp';

  @override
  Future<void> deletePickedPackage() async => deletedPicks++;

  @override
  Future<void> discardExport(ExportedPackage package) =>
      settings.write(SettingKey.lastExportAt, package.previousLastExportAt);

  @override
  Future<ImportPreview> inspectPackage(String packagePath) async {
    final rejection = rejectWith;
    if (rejection != null) throw rejection;
    return samplePreview;
  }

  @override
  Future<BackupManifest> importPackage(String packagePath) async {
    final rejection = rejectWith ?? importFailure;
    if (rejection != null) throw rejection;
    imports++;
    // Like the real import: the data become the package's, the phone's
    // own settings stay and the last common point with Drive is cleared.
    local = localAfterImport;
    for (final key in SettingKey.values) {
      if (key.scope == SettingScope.syncPoint) {
        await settings.write(key, null);
      }
    }
    return sampleManifest;
  }

  /// The local data as the Drive guard sees them.
  LocalSyncState local = emptyLocal;

  /// What [local] becomes after an import.
  LocalSyncState localAfterImport = sampleLocal;

  /// When set, building a Drive package throws it.
  Exception? buildFailure;

  /// How many Drive packages were built, and deleted.
  int driveBuilds = 0;

  /// How many Drive packages were deleted.
  int driveDeletes = 0;

  /// How many downloaded packages were deleted.
  int downloadDeletes = 0;

  @override
  Future<LocalSyncState> localSyncState() async => local;

  @override
  Future<DrivePackage> buildDrivePackage() async {
    final failure = buildFailure;
    if (failure != null) throw failure;
    driveBuilds++;
    return DrivePackage(
      fileName: 'vehicle-history-20261020-1830.zip',
      path: '/fake/drive_package.zip.tmp',
      manifest: sampleManifest,
      local: local,
    );
  }

  @override
  Future<void> deleteDrivePackage() async => driveDeletes++;

  @override
  Future<String> downloadedPackagePath() async => '/fake/downloaded.zip.tmp';

  @override
  Future<void> deleteDownloadedPackage() async => downloadDeletes++;
}

/// The local state of an empty database.
const LocalSyncState emptyLocal = LocalSyncState(
  stamp: null,
  counts: BackupCounts(
    owners: 0,
    vehicles: 0,
    logEntries: 0,
    mileageReadings: 0,
  ),
);

/// A local state with data, last changed on 18 October 2026 at noon.
final LocalSyncState sampleLocal = LocalSyncState(
  stamp: DateTime.utc(2026, 10, 18, 12),
  counts: const BackupCounts(
    owners: 1,
    vehicles: 1,
    logEntries: 3,
    mileageReadings: 1,
  ),
);

/// A rejection for a file that is not a package.
const BackupRejectedException notAPackage =
    BackupRejectedException(BackupRejection.notAZip);
