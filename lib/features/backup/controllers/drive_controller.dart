import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/backup/backup_exceptions.dart';
import '../../../data/data_providers.dart';
import '../../../data/drive/drive_auth_service.dart';
import '../../../data/drive/drive_auto_backup.dart';
import '../../../data/drive/drive_backup_client.dart';
import '../../../data/drive/drive_models.dart';
import '../../../data/drive/drive_settings.dart';
import '../../../data/drive/drive_sync_service.dart';
import '../../../data/drive/sync_guard.dart';
import '../../../shared/utils/action_result.dart';

/// The linked Google account, `null` when none. Refreshes after link,
/// change and unlink, and after an import (which keeps it).
final driveAccountProvider = StreamProvider.autoDispose<DriveAccount?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchDriveAccount(),
);

/// When the last upload or restore with the linked account happened.
final driveLastSyncProvider =
    StreamProvider.autoDispose<({DateTime at, SyncDirection direction})?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchSyncPointSummary(),
);

/// Whether the automatic copy may use mobile data (default off).
final driveMobileDataProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref.watch(settingsRepositoryProvider).watchDriveMobileData(),
);

/// What the Drive section is busy with.
enum DriveTask {
  /// Reading the Drive metadata.
  checking,

  /// Linking an account.
  linking,

  /// Uploading a copy.
  uploading,

  /// Downloading the latest copy.
  downloading,

  /// Replacing the data with the downloaded copy.
  restoring,
}

/// The state of the Drive section and of the status line.
class DriveViewState {
  /// Creates the state.
  const DriveViewState({
    this.task,
    this.progress,
    this.status,
    this.failure,
    this.waitingForUnmetered = false,
  });

  /// What is running, `null` when idle.
  final DriveTask? task;

  /// Progress of an upload or download, 0 to 1, when known.
  final double? progress;

  /// The latest guard check, `null` before the first one or when Drive
  /// could not be read.
  final DriveStatus? status;

  /// Why the last automatic upload or check failed; shown until the next
  /// successful upload or start.
  final DriveFailure? failure;

  /// The automatic upload is due but waits for Wi-Fi.
  final bool waitingForUnmetered;

  /// A copy of this state with [task] and [progress] replaced.
  DriveViewState withTask(DriveTask? task, {double? progress}) =>
      DriveViewState(
        task: task,
        progress: progress,
        status: status,
        failure: failure,
        waitingForUnmetered: waitingForUnmetered,
      );
}

/// The latest Drive copy, downloaded and checked, waiting for the user's
/// confirmation (Restore from Drive).
typedef PreparedRestore = PreparedDownload;

/// The Drive copy (U20, `Docs/05_sync_and_storage.md`): the status line,
/// link, change account, unlink, Upload to Drive, Restore from Drive, the
/// mobile-data setting, and the one automatic action at start.
///
/// Kept alive: the startup run and a restore outlive any page, and the
/// restore closes the database while it runs. Every operation that touches
/// the backup files goes through the [backupLockProvider].
class DriveController extends Notifier<DriveViewState> {
  @override
  DriveViewState build() => const DriveViewState();

  /// Whether [runAtStartup] already ran in this app process: the database
  /// reopening after an import must not run it again.
  bool _startupDone = false;

  /// The one automatic action, once per app start, after the database is
  /// ready: check, and upload only for "only local changed" or "no cloud
  /// copy" (`runStartupAutoUpload`). Never shows a dialog, never throws.
  Future<void> runAtStartup() async {
    if (_startupDone) return;
    _startupDone = true;
    final service = ref.read(driveSyncServiceProvider);
    if (await service.linkedAccount() == null) {
      state = DriveViewState(status: await _checkQuietly());
      return;
    }
    state = state.withTask(DriveTask.checking);
    final outcome = await runStartupAutoUpload(
      service: service,
      network: ref.read(networkStateProvider),
      lock: ref.read(backupLockProvider),
    );
    state = DriveViewState(
      status: outcome.status,
      failure: outcome.failure,
      waitingForUnmetered: outcome.waitingForUnmetered,
    );
  }

  /// Reads the Drive metadata again for the status line (the Backup page
  /// does it when opened). Keeps the failure of the startup upload.
  Future<void> refresh() async {
    if (state.task != null) return;
    state = state.withTask(DriveTask.checking);
    try {
      final status = await ref.read(driveSyncServiceProvider).check();
      state = DriveViewState(
        status: status,
        failure:
            state.failure == DriveFailure.needsRelink ? null : state.failure,
        waitingForUnmetered:
            state.waitingForUnmetered && status.state == SyncState.localChanged,
      );
    } on Exception catch (error) {
      debugPrint('Drive check failed: $error');
      state = DriveViewState(
        status: state.status,
        failure: driveFailureOf(error),
      );
    }
  }

  /// Links an account in [mode] (also used by Change account, after its
  /// warning, with the linked account's mode).
  ///
  /// Succeeds with the account, or `null` if the user backed out (closed
  /// the picker or the browser). The last common point is reset; if the
  /// account holds no copy yet the first one is uploaded at once (nothing
  /// can be lost); an existing copy is never touched until the user
  /// chooses.
  Future<ActionResult<DriveAccount?>> link({
    DriveAuthMode mode = DriveAuthMode.system,
  }) async {
    state = state.withTask(DriveTask.linking);
    try {
      final account = await ref.read(driveSyncServiceProvider).link(mode: mode);
      state = const DriveViewState(task: DriveTask.checking);
      final status = await ref.read(driveSyncServiceProvider).check();
      state = DriveViewState(status: status);
      if (status.state == SyncState.noCloudCopy) {
        // A failed first upload is not a failed link: the status line says
        // so and the next start tries again.
        await upload(expected: status);
      }
      return ActionSuccess(account);
    } on DriveAuthException catch (error) {
      state = state.withTask(null);
      if (error.cancelled) return const ActionSuccess(null);
      return ActionFailure(actionErrorOf(error));
    } on Exception catch (error, stackTrace) {
      state = state.withTask(null);
      return ActionFailure(actionErrorOf(error, stackTrace));
    }
  }

  /// Unlinks the account; the copies stay in its Drive.
  ///
  /// Succeeds with `false` when the link is gone but Google could not be
  /// told to revoke the access (mode 2 offline), for the long message.
  Future<ActionResult<bool>> unlink() async {
    try {
      final revoked = await ref.read(driveSyncServiceProvider).unlink();
      state = DriveViewState(status: await _checkQuietly());
      return ActionSuccess(revoked);
    } on Exception catch (error, stackTrace) {
      return ActionFailure(actionErrorOf(error, stackTrace));
    }
  }

  /// Stores whether the automatic copy may use mobile data.
  Future<void> setMobileData({required bool allowed}) => ref
      .read(settingsRepositoryProvider)
      .writeDriveMobileData(allowed: allowed);

  /// Uploads a new copy now. [expected] is the status the user's decision
  /// was based on (the confirmation showed its dates): if the Drive copy is
  /// another one by now, nothing is uploaded ([ActionError.driveCloudChanged]).
  Future<ActionResult<void>> upload({DriveStatus? expected}) async {
    final basis = expected ?? state.status;
    state = state.withTask(DriveTask.uploading, progress: 0);
    try {
      await ref.read(backupLockProvider).run(
            () => ref.read(driveSyncServiceProvider).upload(
                  expectedUploadId: basis?.latest?.uploadId,
                  transfer: DriveTransfer(onProgress: _onProgress),
                ),
          );
      final status = await _checkQuietly();
      state = DriveViewState(status: status);
      return const ActionSuccess(null);
    } on Exception catch (error, stackTrace) {
      // A copy that changed or is too new is a state, not a failure: the
      // new check shows it. Anything else is "the last upload failed".
      final stateNotFailure = error is DriveCloudChangedException ||
          error is DriveCloudTooNewException;
      final previous = state;
      final status = await _checkQuietly();
      state = DriveViewState(
        status: status ?? previous.status,
        failure: stateNotFailure ? previous.failure : driveFailureOf(error),
      );
      return ActionFailure(actionErrorOf(error, stackTrace));
    }
  }

  /// Downloads the latest copy and checks it, without touching the data.
  /// Succeeds with what it holds, for the confirmation dialog.
  Future<ActionResult<PreparedRestore>> prepareRestore() async {
    state = state.withTask(DriveTask.downloading, progress: 0);
    try {
      final prepared = await ref.read(backupLockProvider).run(
            () => ref.read(driveSyncServiceProvider).prepareRestore(
                  transfer: DriveTransfer(onProgress: _onProgress),
                ),
          );
      return ActionSuccess(prepared);
    } on Exception catch (error, stackTrace) {
      return ActionFailure(actionErrorOf(error, stackTrace));
    } finally {
      state = state.withTask(null);
    }
  }

  /// Deletes a downloaded copy the user decided not to restore.
  Future<void> discardRestore() =>
      ref.read(driveSyncServiceProvider).discardDownload();

  /// Replaces all the data and attachment files with [prepared], through
  /// the import safety net, then records the common point on the new
  /// connection.
  ///
  /// Unless the copy is refused before anything is touched, the import has
  /// closed the database: it is reopened (the whole app rebuilds on the new
  /// connection) before this returns.
  Future<ActionResult<void>> restore(PreparedRestore prepared) async {
    state = state.withTask(DriveTask.restoring);
    final lock = ref.read(backupLockProvider);
    try {
      await lock.run(
        () => ref.read(driveSyncServiceProvider).importDownload(prepared),
      );
      await _reopenDatabase();
      await ref.read(driveSyncServiceProvider).recordDownload(prepared);
      state = DriveViewState(status: await _checkQuietly());
      return const ActionSuccess(null);
    } on BackupRejectedException catch (error, stackTrace) {
      state = state.withTask(null);
      return ActionFailure(actionErrorOf(error, stackTrace));
    } on Exception catch (error, stackTrace) {
      await _reopenDatabase();
      state = DriveViewState(status: await _checkQuietly());
      return ActionFailure(actionErrorOf(error, stackTrace));
    }
  }

  /// Reports the progress of a transfer.
  void _onProgress(int done, int total) {
    final task = state.task;
    if (task == null || total <= 0) return;
    state = state.withTask(task, progress: (done / total).clamp(0, 1));
  }

  /// A guard check, or `null` when Drive cannot be read.
  Future<DriveStatus?> _checkQuietly() async {
    try {
      return await ref.read(driveSyncServiceProvider).check();
    } on Exception catch (error) {
      debugPrint('Drive check failed: $error');
      return null;
    }
  }

  /// Drops the closed connection and waits for the new one to be open, as
  /// after a manual import.
  Future<void> _reopenDatabase() async {
    ref.invalidate(appDatabaseProvider);
    try {
      await ref.read(databaseReadyProvider.future);
    } on Exception catch (error) {
      debugPrint('Reopening the database after a restore failed: $error');
    }
  }
}

/// The app-wide [DriveController].
final driveControllerProvider =
    NotifierProvider<DriveController, DriveViewState>(DriveController.new);
