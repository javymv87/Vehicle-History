import '../models/audit_entry.dart';
import '../models/reminder_kind.dart';

/// Base type of every error a repository throws on purpose.
///
/// Repositories translate invalid input and rule violations into these typed
/// errors, so callers never see raw SQLite exceptions.
sealed class RepositoryException implements Exception {
  /// Creates the base exception.
  const RepositoryException();
}

/// The targeted entity does not exist, or has been deleted.
class EntityNotFoundException extends RepositoryException {
  /// Creates the exception for the entity of [entityType] with [entityId].
  const EntityNotFoundException(this.entityType, this.entityId);

  /// Kind of the missing entity.
  final AuditEntityType entityType;

  /// Id that was looked up.
  final String entityId;

  @override
  String toString() =>
      'EntityNotFoundException(${entityType.name}, id: $entityId)';
}

/// A required field is blank, or a value is outside its allowed range.
class InvalidFieldException extends RepositoryException {
  /// Creates the exception for [field] with an English, developer-facing
  /// [reason]. The UI shows its own localised message.
  const InvalidFieldException(this.field, this.reason);

  /// [reason] of a date after today, for a reading or an entry type that
  /// does not accept future dates.
  static const String inFuture = 'must not be in the future';

  /// [reason] of a reading dated before the last reading of its vehicle.
  static const String beforeLastReading = 'must not be before the last reading';

  /// [reason] of a reading with fewer km than the last reading of its
  /// vehicle: the odometer never goes backwards.
  static const String belowLastReading = 'must not be below the last reading';

  /// [reason] of an entry closing a reminder dated before the reminder's
  /// anchor day: the anchor never moves backwards.
  static const String beforeAnchor = 'must not be before the last time done';

  /// [reason] of an entry closing a reminder with fewer km than the
  /// reminder's anchor km.
  static const String belowAnchor = 'must not be below the last time done';

  /// [reason] of a snooze that does not postpone: on its axis it is not
  /// later than the due value of the applied criterion.
  static const String notLater = 'must be later than the current due value';

  /// [reason] of a missing value the rule needs, such as the km of an
  /// entry closing a reminder with a km interval.
  static const String required = 'required';

  /// Name of the offending field, as in the domain model (e.g. `plate`).
  final String field;

  /// Why the value was refused.
  final String reason;

  @override
  String toString() => 'InvalidFieldException($field: $reason)';
}

/// Another live vehicle already uses this plate.
class DuplicatePlateException extends RepositoryException {
  /// Creates the exception for the normalised [plate].
  const DuplicatePlateException(this.plate);

  /// The plate, already trimmed and upper-cased.
  final String plate;

  @override
  String toString() => 'DuplicatePlateException($plate)';
}

/// The owner still has live vehicles and cannot be deleted.
class OwnerHasVehiclesException extends RepositoryException {
  /// Creates the exception for the owner with [ownerId].
  const OwnerHasVehiclesException(this.ownerId, this.vehicleCount);

  /// Id of the owner that was not deleted.
  final String ownerId;

  /// Number of live vehicles still linked to the owner.
  final int vehicleCount;

  @override
  String toString() =>
      'OwnerHasVehiclesException(id: $ownerId, vehicles: $vehicleCount)';
}

/// The owner has no live vehicles but still has vehicles in the Trash, and
/// cannot be deleted: restoring one of them would need the owner.
class OwnerHasTrashedVehiclesException extends RepositoryException {
  /// Creates the exception for the owner with [ownerId].
  const OwnerHasTrashedVehiclesException(this.ownerId, this.vehicleCount);

  /// Id of the owner that was not deleted.
  final String ownerId;

  /// Number of soft-deleted vehicles still linked to the owner.
  final int vehicleCount;

  @override
  String toString() =>
      'OwnerHasTrashedVehiclesException(id: $ownerId, vehicles: '
      '$vehicleCount)';
}

/// The vehicle is archived, so it and everything that belongs to it (its
/// entries, readings and attachments) are read-only until it is reactivated
/// (`Docs/02_data_model.md`, "Archivo"). Nothing was written.
class VehicleArchivedException extends RepositoryException {
  /// Creates the exception for the refused write on the entity of
  /// [entityType] with [entityId]: the vehicle itself, or what belongs to
  /// it.
  const VehicleArchivedException(this.entityType, this.entityId);

  /// Kind of the entity the write targeted.
  final AuditEntityType entityType;

  /// Id of the entity the write targeted.
  final String entityId;

  @override
  String toString() =>
      'VehicleArchivedException(${entityType.name}, id: $entityId)';
}

/// The vehicle's fuel type cannot change to one that does not allow the
/// fuel of some of its refuels (`Docs/02_data_model.md`, "Repostaje"): the
/// user must delete those refuels first. Nothing was written.
class VehicleFuelTypeConflictException extends RepositoryException {
  /// Creates the exception for the vehicle [vehicleId], which has
  /// [refuelCount] refuels of a fuel the new type does not allow.
  const VehicleFuelTypeConflictException(this.vehicleId, this.refuelCount);

  /// Id of the vehicle whose update was refused.
  final String vehicleId;

  /// How many live refuels have a fuel the new type does not allow.
  final int refuelCount;

  @override
  String toString() => 'VehicleFuelTypeConflictException(id: $vehicleId, '
      'refuels: $refuelCount)';
}

/// A file is larger than an attachment may be (`maxAttachmentBytes`,
/// 25 MB). Nothing was stored.
class AttachmentTooLargeException extends RepositoryException {
  /// Creates the exception for a file of at least [sizeBytes] bytes.
  const AttachmentTooLargeException(this.sizeBytes);

  /// Size of the file, or how much of it was read before giving up.
  final int sizeBytes;

  @override
  String toString() => 'AttachmentTooLargeException($sizeBytes bytes)';
}

/// Why a mileage reading cannot be deleted, edited or restored.
enum MileageReadingRule {
  /// Only the last reading of a vehicle can be deleted.
  notLast,

  /// The initial reading (the oldest) is never deleted: every vehicle keeps
  /// at least one reading.
  initial,

  /// A reading can be corrected only while it is the only one of its
  /// vehicle.
  notSoleReading,

  /// A deleted reading comes back only if it would again be the last one; a
  /// more recent reading was added in the meantime.
  newerReadingExists,
}

/// A mileage reading operation was refused by one of the series rules of
/// `Docs/04_maintenance_logic.md`. Nothing was written.
class MileageReadingRuleException extends RepositoryException {
  /// Creates the exception for the reading with [readingId], refused by
  /// [rule].
  const MileageReadingRuleException(this.readingId, this.rule);

  /// Id of the reading the operation targeted.
  final String readingId;

  /// The rule that refused the operation.
  final MileageReadingRule rule;

  @override
  String toString() =>
      'MileageReadingRuleException(id: $readingId, rule: ${rule.name})';
}

/// A live, open reminder of the same kind already exists on the vehicle
/// (`Docs/04_maintenance_logic.md`: an assigned type does not appear again
/// for the same vehicle). Nothing was written.
class ReminderKindAlreadyUsedException extends RepositoryException {
  /// Creates the exception for [kind] on the vehicle [vehicleId].
  const ReminderKindAlreadyUsedException(this.vehicleId, this.kind);

  /// Vehicle that already has a reminder of [kind].
  final String vehicleId;

  /// The kind in use.
  final ReminderKind kind;

  @override
  String toString() =>
      'ReminderKindAlreadyUsedException(vehicle: $vehicleId, ${kind.code})';
}

/// Why a reminder operation was refused (`Docs/08_recordatorios.md`).
enum ReminderRule {
  /// A one-shot reminder has no criterion to override.
  oneShot,

  /// A completed one-shot reminder is read-only; it can only be deleted.
  completed,

  /// The closing entry belongs to another vehicle.
  entryOfOtherVehicle,

  /// The closing entry's type cannot close a reminder of this kind
  /// (`ReminderKind.closingEntryTypes`).
  entryTypeCannotClose,

  /// "Restore reference" on a reminder whose criterion is not overridden.
  notOverridden,

  /// "Remove postponement" on a reminder that is not postponed.
  notSnoozed,

  /// A change of kind, or between recurring and one-shot, of a reminder an
  /// entry has already closed: its history belongs to that kind, so a new
  /// reminder is created instead.
  alreadyClosed,
}

/// A reminder operation was refused by one of the rules of
/// `Docs/08_recordatorios.md`. Nothing was written.
class ReminderRuleException extends RepositoryException {
  /// Creates the exception for the reminder with [reminderId], refused by
  /// [rule].
  const ReminderRuleException(this.reminderId, this.rule);

  /// Id of the reminder the operation targeted.
  final String reminderId;

  /// The rule that refused the operation.
  final ReminderRule rule;

  @override
  String toString() =>
      'ReminderRuleException(id: $reminderId, rule: ${rule.name})';
}
