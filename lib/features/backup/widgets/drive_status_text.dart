import 'package:intl/intl.dart';

import '../../../data/drive/drive_auto_backup.dart';
import '../../../data/drive/sync_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../controllers/drive_controller.dart';

/// The status line of the Drive copy, in words (`Docs/03_features.md`,
/// U20): what the startup run or the last check found.
String driveStatusText(AppLocalizations l10n, DriveViewState view) {
  switch (view.task) {
    case DriveTask.checking || DriveTask.linking:
      return l10n.driveStatusChecking;
    case DriveTask.uploading:
      return l10n.driveStatusUploading;
    case DriveTask.downloading || DriveTask.restoring || null:
      break;
  }
  switch (view.failure) {
    case DriveFailure.needsRelink:
      return l10n.driveStatusNeedsRelink;
    case DriveFailure.offline:
      return l10n.driveStatusOffline;
    case DriveFailure.failed:
      return l10n.driveStatusUploadFailed;
    case null:
      break;
  }
  final status = view.status;
  if (status == null) return l10n.driveStatusChecking;
  return switch (status.state) {
    SyncState.noAccount => l10n.driveStatusNoAccount,
    SyncState.aligned => l10n.driveStatusUpToDate,
    SyncState.localChanged => view.waitingForUnmetered
        ? l10n.driveStatusWaitingWifi
        : l10n.driveStatusLocalChanged,
    SyncState.noCloudCopy => view.waitingForUnmetered
        ? l10n.driveStatusWaitingWifi
        : l10n.driveStatusNoCloudCopy,
    SyncState.cloudChanged => l10n.driveStatusCloudChanged,
    SyncState.diverged => l10n.driveStatusDiverged,
    SyncState.noCommonPoint => l10n.driveStatusNoCommonPoint,
    SyncState.cloudTooNew => l10n.driveStatusCloudTooNew,
  };
}

/// Whether the status asks for the user's attention: a decision only the
/// user can take, or a problem. Shown once at start as a discreet message.
bool driveNeedsAttention(DriveViewState view) {
  if (view.failure == DriveFailure.needsRelink) return true;
  return switch (view.status?.state) {
    SyncState.cloudChanged ||
    SyncState.diverged ||
    SyncState.noCommonPoint ||
    SyncState.cloudTooNew =>
      true,
    _ => false,
  };
}

/// [instant] as a day in the user's language, or "no data" for `null`.
String driveDateText(AppLocalizations l10n, DateTime? instant) =>
    instant == null
        ? l10n.driveNoDataDate
        : DateFormat.yMMMd(l10n.localeName).format(instant.toLocal());
