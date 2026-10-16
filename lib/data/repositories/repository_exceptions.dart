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
