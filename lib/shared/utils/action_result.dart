import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../../data/attachments/attachment_picker.dart';
import '../../data/backup/backup_exceptions.dart';
import '../../data/drive/drive_auth_service.dart';
import '../../data/drive/drive_backup_client.dart';
import '../../data/drive/drive_sync_service.dart';
import '../../data/models/audit_entry.dart';
import '../../data/repositories/repository_exceptions.dart';

/// Why a user action (save, delete, restore) failed, in terms the UI can
/// translate into a localised message.
///
/// Controllers never hand raw exceptions to widgets: they map them to one of
/// these values with [actionErrorOf].
enum ActionError {
  /// Another live vehicle already uses the plate.
  duplicatePlate,

  /// The owner still has live vehicles and was not deleted.
  ownerHasVehicles,

  /// The owner still has vehicles in the Trash and was not deleted.
  ownerHasTrashedVehicles,

  /// The owner involved is missing or deleted.
  ownerNotFound,

  /// The vehicle involved is missing or deleted.
  vehicleNotFound,

  /// The history entry involved is missing or deleted.
  entryNotFound,

  /// The odometer reading involved is missing or deleted.
  readingNotFound,

  /// The attachment involved is missing or deleted.
  attachmentNotFound,

  /// The file is larger than an attachment may be (25 MB).
  attachmentTooLarge,

  /// The user refused the camera permission.
  cameraDenied,

  /// The user refused access to the photos.
  photosDenied,

  /// The camera, gallery or file picker failed.
  pickFailed,

  /// A file could not be saved where the user chose.
  saveFailed,

  /// No installed app can open the attachment.
  openNoApp,

  /// The attachments could not be shared with another app.
  shareFailed,

  /// The file of the attachment is missing on the phone.
  attachmentFileMissing,

  /// The reading is not the last one, or is the initial one, and cannot be
  /// deleted.
  readingNotDeletable,

  /// The reading cannot be corrected: its vehicle has more than one.
  readingNotEditable,

  /// The deleted reading cannot come back: a more recent one exists.
  newerReadingExists,

  /// The data layer refused a value that the form let through.
  invalidInput,

  /// The file chosen for an import is not a Vehicle History backup.
  backupNotAPackage,

  /// The backup was written by a newer version of the app.
  backupFromNewerApp,

  /// The database inside the backup is damaged.
  backupCorrupt,

  /// The phone has not enough free space for the import.
  backupNoSpace,

  /// The backup could not be exported.
  exportFailed,

  /// The import failed; the previous data was put back.
  importFailed,

  /// The import failed and the previous data could not be reopened; it is
  /// kept in the `pre_import` copy.
  importRestoreFailed,

  /// Google Drive could not be reached.
  driveOffline,

  /// A Google Drive request failed.
  driveFailed,

  /// The Google account no longer authorises the app: link it again.
  driveNeedsRelink,

  /// The Google account could not be linked.
  driveLinkFailed,

  /// The Drive copy changed between the check and the action; nothing was
  /// replaced.
  driveCloudChanged,

  /// The Drive copy comes from a newer version of the app.
  driveCloudTooNew,

  /// Anything else, such as a disk or SQLite failure.
  unexpected,
}

/// Maps an exception thrown by a repository to an [ActionError].
///
/// Exceptions that are not a `RepositoryException` become
/// [ActionError.unexpected] and are reported to the debug console.
ActionError actionErrorOf(Object error, [StackTrace? stackTrace]) {
  return switch (error) {
    DuplicatePlateException() => ActionError.duplicatePlate,
    OwnerHasVehiclesException() => ActionError.ownerHasVehicles,
    OwnerHasTrashedVehiclesException() => ActionError.ownerHasTrashedVehicles,
    EntityNotFoundException(entityType: AuditEntityType.owner) =>
      ActionError.ownerNotFound,
    EntityNotFoundException(entityType: AuditEntityType.vehicle) =>
      ActionError.vehicleNotFound,
    EntityNotFoundException(entityType: AuditEntityType.logEntry) =>
      ActionError.entryNotFound,
    EntityNotFoundException(entityType: AuditEntityType.mileageReading) =>
      ActionError.readingNotFound,
    EntityNotFoundException(entityType: AuditEntityType.attachment) =>
      ActionError.attachmentNotFound,
    AttachmentTooLargeException() => ActionError.attachmentTooLarge,
    AttachmentPickException(failure: AttachmentPickFailure.cameraDenied) =>
      ActionError.cameraDenied,
    AttachmentPickException(failure: AttachmentPickFailure.photosDenied) =>
      ActionError.photosDenied,
    AttachmentPickException() => ActionError.pickFailed,
    PlatformException() => ActionError.saveFailed,
    MileageReadingRuleException(
      rule: MileageReadingRule.notLast || MileageReadingRule.initial,
    ) =>
      ActionError.readingNotDeletable,
    MileageReadingRuleException(rule: MileageReadingRule.notSoleReading) =>
      ActionError.readingNotEditable,
    MileageReadingRuleException(
      rule: MileageReadingRule.newerReadingExists,
    ) =>
      ActionError.newerReadingExists,
    InvalidFieldException() => ActionError.invalidInput,
    BackupRejectedException(
      reason: BackupRejection.newerSchema || BackupRejection.newerFormat,
    ) =>
      ActionError.backupFromNewerApp,
    BackupRejectedException(reason: BackupRejection.corruptDatabase) =>
      ActionError.backupCorrupt,
    BackupRejectedException(reason: BackupRejection.notEnoughSpace) =>
      ActionError.backupNoSpace,
    BackupRejectedException() => ActionError.backupNotAPackage,
    BackupImportFailedException() => ActionError.importFailed,
    BackupRestoreFailedException() => ActionError.importRestoreFailed,
    DriveAuthorizationRequiredException() => ActionError.driveNeedsRelink,
    DriveAuthException() => ActionError.driveLinkFailed,
    DriveRequestException(offline: true) => ActionError.driveOffline,
    DriveRequestException() => ActionError.driveFailed,
    DriveCloudChangedException() => ActionError.driveCloudChanged,
    DriveCloudTooNewException() => ActionError.driveCloudTooNew,
    _ => _unexpected(error, stackTrace),
  };
}

/// Reports an unexpected [error] and returns [ActionError.unexpected].
ActionError _unexpected(Object error, StackTrace? stackTrace) {
  debugPrint('Unexpected action error: $error\n${stackTrace ?? ''}');
  return ActionError.unexpected;
}

/// Outcome of a user action: either a value or an [ActionError].
sealed class ActionResult<T> {
  /// Base constructor for the two outcomes.
  const ActionResult();
}

/// The action succeeded and produced [value].
final class ActionSuccess<T> extends ActionResult<T> {
  /// Creates a successful outcome carrying [value].
  const ActionSuccess(this.value);

  /// What the action produced, such as the saved entity.
  final T value;
}

/// The action failed; nothing was written.
final class ActionFailure<T> extends ActionResult<T> {
  /// Creates a failed outcome for [error].
  const ActionFailure(this.error);

  /// Why the action failed.
  final ActionError error;
}

/// Runs [action] and wraps its outcome in an [ActionResult].
///
/// Only [Exception]s are turned into an [ActionFailure]; an [Error] is a
/// programming mistake and is rethrown.
Future<ActionResult<T>> runAction<T>(Future<T> Function() action) async {
  try {
    return ActionSuccess(await action());
  } on Exception catch (error, stackTrace) {
    return ActionFailure(actionErrorOf(error, stackTrace));
  }
}
