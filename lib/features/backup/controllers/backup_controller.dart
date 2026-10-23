import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/backup/backup_exceptions.dart';
import '../../../data/backup/backup_service.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/attachment.dart';
import '../../../data/models/backup_manifest.dart';
import '../../../data/platform/native_files.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../shared/utils/action_result.dart';

/// When the last backup package was exported, in UTC, or `null` before the
/// first export (U20). Refreshes after every export and after an import.
final lastExportAtProvider = StreamProvider.autoDispose<DateTime?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchLastExportAt(),
);

/// How many attachment files there are and how much space they take: what
/// the next package will carry (U27).
final attachmentTotalsProvider = StreamProvider.autoDispose<AttachmentTotals>(
  (ref) => ref.watch(attachmentRepositoryProvider).watchTotals(),
);

/// What the Backup page is busy with.
enum BackupTask {
  /// Building and saving a package.
  exporting,

  /// Checking or importing a package.
  importing,
}

/// A package the user picked for an import, copied to [path], checked and
/// described by [preview], ready to confirm.
typedef PickedPackage = ({String path, ImportPreview preview});

/// MIME type of a backup package, so the system dialog shows it as a zip.
const String _zipMimeType = 'application/zip';

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

  /// Builds the package as a temporary file and asks the user where to
  /// save it, through the native "save as" that copies it in chunks.
  ///
  /// Succeeds with `true` once saved, or `false` if the user cancelled the
  /// save dialog, which is not an error.
  ///
  /// The service writes `last_export_at` before copying the database, so
  /// the package carries it; unless the package is saved, the previous
  /// value is put back. The temporary file is deleted in any case.
  Future<ActionResult<bool>> export() async {
    state = BackupTask.exporting;
    try {
      final service = ref.read(backupServiceProvider);
      // One backup operation at a time: the Drive upload at start may run.
      final saved = await ref.read(backupLockProvider).run(() async {
        final package = await service.exportPackage();
        var saved = false;
        try {
          saved = await ref.read(nativeFilesProvider).saveFile(
                    sourcePath: package.path,
                    suggestedName: package.fileName,
                    mimeType: _zipMimeType,
                  ) ==
              SaveFileOutcome.saved;
        } finally {
          if (!saved) await service.discardExport(package);
          await service.deleteExport(package);
        }
        return saved;
      });
      return ActionSuccess(saved);
    } on Exception catch (error, stackTrace) {
      debugPrint('Export failed: $error\n$stackTrace');
      return const ActionFailure(ActionError.exportFailed);
    } finally {
      state = null;
    }
  }

  /// Asks the user for a package, copies it next to the database and
  /// checks it, without touching the data.
  ///
  /// Succeeds with the package and what it holds, for the confirmation
  /// dialog, or with `null` if the user cancelled. Fails with the reason a
  /// package is refused, such as [ActionError.backupFromNewerApp]; the copy
  /// is deleted then.
  Future<ActionResult<PickedPackage?>> pickPackage() async {
    state = BackupTask.importing;
    final service = ref.read(backupServiceProvider);
    try {
      final path = await service.pickedPackagePath();
      final picked = await ref.read(backupFilePickerProvider).pickPackage(path);
      if (!picked) {
        await service.deletePickedPackage();
        return const ActionSuccess(null);
      }
      final preview = await service.inspectPackage(path);
      return ActionSuccess((path: path, preview: preview));
    } on Exception catch (error, stackTrace) {
      await service.deletePickedPackage();
      return ActionFailure(actionErrorOf(error, stackTrace));
    } finally {
      state = null;
    }
  }

  /// Deletes the copy of a [package] the user decided not to import.
  Future<void> cancelImport(PickedPackage package) =>
      ref.read(backupServiceProvider).deletePickedPackage();

  /// Replaces all the data and attachment files with the picked [package].
  ///
  /// Unless the package is refused before anything is touched, the import
  /// has closed the database: the database provider is invalidated, which
  /// opens a new connection on the (imported or restored) file and rebuilds
  /// every screen on it, and this waits until it is open. The copy of the
  /// package is deleted in any case.
  Future<ActionResult<BackupManifest>> importPackage(
    PickedPackage package,
  ) async {
    state = BackupTask.importing;
    final service = ref.read(backupServiceProvider);
    try {
      final manifest = await ref
          .read(backupLockProvider)
          .run(() => service.importPackage(package.path));
      await _reopenDatabase();
      return ActionSuccess(manifest);
    } on BackupRejectedException catch (error, stackTrace) {
      return ActionFailure(actionErrorOf(error, stackTrace));
    } on Exception catch (error, stackTrace) {
      await _reopenDatabase();
      return ActionFailure(actionErrorOf(error, stackTrace));
    } finally {
      await service.deletePickedPackage();
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
