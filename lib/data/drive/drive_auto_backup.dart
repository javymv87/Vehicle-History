import 'package:flutter/foundation.dart' show debugPrint;

import '../backup/backup_lock.dart';
import '../platform/network_state.dart';
import 'drive_auth_service.dart';
import 'drive_backup_client.dart';
import 'drive_sync_service.dart';
import 'sync_guard.dart';

/// Why the last Drive action failed, as the status line words it.
enum DriveFailure {
  /// Drive could not be reached.
  offline,

  /// The account no longer authorises the app: link it again.
  needsRelink,

  /// Anything else (server error, refused request, disk).
  failed,
}

/// The [DriveFailure] an [error] of a Drive action stands for.
DriveFailure driveFailureOf(Object error) => switch (error) {
      DriveAuthorizationRequiredException() => DriveFailure.needsRelink,
      DriveRequestException(offline: true) => DriveFailure.offline,
      _ => DriveFailure.failed,
    };

/// What [runStartupAutoUpload] did.
class AutoUploadOutcome {
  /// Creates the outcome.
  const AutoUploadOutcome({
    this.status,
    this.uploaded = false,
    this.failure,
    this.waitingForUnmetered = false,
  });

  /// The guard's latest status, `null` when Drive could not be read.
  final DriveStatus? status;

  /// A new copy was uploaded.
  final bool uploaded;

  /// Why the check or the upload failed; tried again at the next start.
  final DriveFailure? failure;

  /// The upload was due but waits for an unmetered network (mobile data
  /// not allowed): tried again at the next start.
  final bool waitingForUnmetered;
}

/// Whether the guard allows an upload with no question asked: the copy it
/// replaces is contained in the local data, or there is none.
bool mayUploadAutomatically(SyncState state) =>
    state == SyncState.localChanged || state == SyncState.noCloudCopy;

/// The **only** automatic Drive action (`Docs/05_sync_and_storage.md`):
/// run once per app start, after the database is ready.
///
/// Reads the Drive metadata and runs the guard; only for
/// [SyncState.localChanged] and [SyncState.noCloudCopy] it uploads, in the
/// background, if the network allows it ([network], and mobile data only
/// when the user allowed it). [DriveSyncService.upload] reads the metadata
/// again right before sending: if the copy changed meanwhile nothing is
/// uploaded and the new check says what the user has to decide.
///
/// Never throws and never retries: a failure is reported in the outcome
/// and the next start tries again. The last common point only moves when
/// an upload is confirmed by Drive.
Future<AutoUploadOutcome> runStartupAutoUpload({
  required DriveSyncService service,
  required NetworkState network,
  required BackupLock lock,
}) async {
  final DriveStatus status;
  try {
    status = await service.check();
  } on Exception catch (error) {
    debugPrint('Drive check at start failed: $error');
    return AutoUploadOutcome(failure: driveFailureOf(error));
  }
  if (!mayUploadAutomatically(status.state)) {
    return AutoUploadOutcome(status: status);
  }

  try {
    final kind = await network.current();
    if (kind == NetworkKind.none) {
      return AutoUploadOutcome(status: status, failure: DriveFailure.offline);
    }
    if (kind == NetworkKind.metered && !await service.mobileDataAllowed()) {
      return AutoUploadOutcome(status: status, waitingForUnmetered: true);
    }
    final uploaded = await lock.tryRun(
      () => service.upload(expectedUploadId: status.latest?.uploadId),
    );
    if (uploaded == null) {
      // A manual backup operation is running; the next start tries again.
      return AutoUploadOutcome(status: status, failure: DriveFailure.failed);
    }
  } on DriveCloudChangedException {
    // Another phone uploaded since the check: nothing was replaced. The new
    // check tells the user where things stand ("both have changed").
    return _recheck(service, status, uploaded: false);
  } on Exception catch (error) {
    debugPrint('Automatic Drive upload failed: $error');
    return AutoUploadOutcome(status: status, failure: driveFailureOf(error));
  }
  return _recheck(service, status, uploaded: true);
}

/// Checks again after an upload attempt; keeps [previous] if that fails.
Future<AutoUploadOutcome> _recheck(
  DriveSyncService service,
  DriveStatus previous, {
  required bool uploaded,
}) async {
  try {
    return AutoUploadOutcome(status: await service.check(), uploaded: uploaded);
  } on Exception catch (error) {
    debugPrint('Drive check after the upload failed: $error');
    return AutoUploadOutcome(
      status: previous,
      uploaded: uploaded,
      failure: uploaded ? null : driveFailureOf(error),
    );
  }
}
