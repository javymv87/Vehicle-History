import 'dart:async';
import 'dart:typed_data';

import 'package:vehicle_history/data/backup/backup_exceptions.dart';
import 'package:vehicle_history/data/backup/backup_file_picker.dart';
import 'package:vehicle_history/data/backup/backup_service.dart';
import 'package:vehicle_history/data/models/backup_manifest.dart';
import 'package:vehicle_history/data/models/setting_key.dart';
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

/// [BackupFilePicker] whose dialogs answer with preset values.
class FakeBackupFilePicker implements BackupFilePicker {
  /// Whether the save dialog saves (`true`) or is cancelled.
  bool saveResult = true;

  /// What the open dialog returns; `null` means cancelled.
  Uint8List? pickResult;

  /// Names of the files the save dialog was asked to save.
  final List<String> savedNames = [];

  @override
  Future<bool> savePackage(String fileName, Uint8List bytes) async {
    savedNames.add(fileName);
    return saveResult;
  }

  @override
  Future<Uint8List?> pickPackage() async => pickResult;
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
    return ExportedPackage(
      fileName: 'vehicle-history-20261020-1830.zip',
      bytes: Uint8List.fromList([1, 2, 3]),
      manifest: sampleManifest,
      previousLastExportAt: previous,
    );
  }

  @override
  Future<void> discardExport(ExportedPackage package) =>
      settings.write(SettingKey.lastExportAt, package.previousLastExportAt);

  @override
  Future<BackupManifest> inspectPackage(Uint8List bytes) async {
    final rejection = rejectWith;
    if (rejection != null) throw rejection;
    return sampleManifest;
  }

  @override
  Future<BackupManifest> importPackage(Uint8List bytes) async {
    final rejection = rejectWith ?? importFailure;
    if (rejection != null) throw rejection;
    imports++;
    return sampleManifest;
  }
}

/// A rejection for a file that is not a package.
const BackupRejectedException notAPackage =
    BackupRejectedException(BackupRejection.notAZip);
