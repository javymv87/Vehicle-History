import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/backup/backup_exceptions.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/backup_manifest.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../shared/utils/action_result.dart';

/// When the last backup package was exported, in UTC, or `null` before the
/// first export (U20). Refreshes after every export and after an import.
final lastExportAtProvider = StreamProvider.autoDispose<DateTime?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchLastExportAt(),
);

/// What the Backup page is busy with.
enum BackupTask {
  /// Building and saving a package.
  exporting,

  /// Checking or importing a package.
  importing,
}

/// A package the user picked for an import, checked and ready to confirm.
typedef PickedPackage = ({Uint8List bytes, BackupManifest manifest});

/// The actions of the Backup page (U20): export, pick and check a package,
/// import it.
///
/// Its state is the task in progress (`null` when idle), which drives the
/// progress indicator and disables the buttons. Kept alive like the deletion
/// controllers: an import closes the database, and the page may be rebuilt
/// before the action ends.
class BackupController extends Notifier<BackupTask?> {
  @override
  BackupTask? build() => null;

  /// Builds the package and asks the user where to save it.
  ///
  /// Succeeds with `true` once saved (and `last_export_at` written), or
  /// `false` if the user cancelled the save dialog, which is not an error.
  Future<ActionResult<bool>> export() async {
    state = BackupTask.exporting;
    try {
      final package = await ref.read(backupServiceProvider).exportPackage();
      final saved = await ref
          .read(backupFilePickerProvider)
          .savePackage(package.fileName, package.bytes);
      if (saved) {
        await ref
            .read(settingsRepositoryProvider)
            .writeLastExportAt(package.manifest.exportedAt);
      }
      return ActionSuccess(saved);
    } on Exception catch (error, stackTrace) {
      debugPrint('Export failed: $error\n$stackTrace');
      return const ActionFailure(ActionError.exportFailed);
    } finally {
      state = null;
    }
  }

  /// Asks the user for a package and checks it, without touching the data.
  ///
  /// Succeeds with the package and its manifest, for the confirmation
  /// dialog, or with `null` if the user cancelled. Fails with the reason a
  /// package is refused, such as [ActionError.backupFromNewerApp].
  Future<ActionResult<PickedPackage?>> pickPackage() async {
    state = BackupTask.importing;
    try {
      final bytes = await ref.read(backupFilePickerProvider).pickPackage();
      if (bytes == null) return const ActionSuccess(null);
      final manifest =
          await ref.read(backupServiceProvider).inspectPackage(bytes);
      return ActionSuccess((bytes: bytes, manifest: manifest));
    } on Exception catch (error, stackTrace) {
      return ActionFailure(actionErrorOf(error, stackTrace));
    } finally {
      state = null;
    }
  }

  /// Replaces all the data with the package [bytes].
  ///
  /// Unless the package is refused before anything is touched, the import
  /// has closed the database: the database provider is invalidated, which
  /// opens a new connection on the (imported or restored) file and rebuilds
  /// every screen on it, and this waits until it is open.
  Future<ActionResult<BackupManifest>> importPackage(Uint8List bytes) async {
    state = BackupTask.importing;
    try {
      final manifest =
          await ref.read(backupServiceProvider).importPackage(bytes);
      await _reopenDatabase();
      return ActionSuccess(manifest);
    } on BackupRejectedException catch (error, stackTrace) {
      return ActionFailure(actionErrorOf(error, stackTrace));
    } on Exception catch (error, stackTrace) {
      await _reopenDatabase();
      return ActionFailure(actionErrorOf(error, stackTrace));
    } finally {
      state = null;
    }
  }

  /// Drops the closed connection and waits for the new one to be open. A
  /// failure to open shows the startup error screen, like at app start.
  Future<void> _reopenDatabase() async {
    ref.invalidate(appDatabaseProvider);
    try {
      await ref.read(databaseReadyProvider.future);
    } on Exception catch (error) {
      debugPrint('Reopening the database after an import failed: $error');
    }
  }
}

/// The app-wide [BackupController].
final backupControllerProvider =
    NotifierProvider<BackupController, BackupTask?>(BackupController.new);
