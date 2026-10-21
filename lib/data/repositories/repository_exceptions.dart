import '../models/audit_entry.dart';

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
