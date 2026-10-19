/// Kind of entity an [AuditEntry] refers to.
enum AuditEntityType {
  /// An `Owner`.
  owner,

  /// A `Vehicle`.
  vehicle,

  /// A `LogEntry` of a vehicle's history.
  logEntry,

  /// A `MileageReading` of a vehicle's odometer history.
  mileageReading,
}

/// Kind of write an [AuditEntry] records.
enum AuditOperation {
  /// The entity was created.
  create,

  /// The entity was modified.
  update,

  /// The entity was (soft) deleted.
  delete,

  /// A soft-deleted entity was brought back, e.g. by "Undo" after a delete.
  restore,

  /// A soft-deleted entity was removed from disk for good: from the Trash,
  /// or by the 30-day cleanup at app start. Recorded for vehicles and
  /// owners only; the entries and readings removed with a vehicle get no
  /// row of their own.
  purge,
}

/// One row of the audit log: which entity was written, how, and when.
///
/// Written by the repositories in the same transaction as the change it
/// records, and never modified or deleted afterwards.
class AuditEntry {
  /// Creates an audit entry snapshot.
  const AuditEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.at,
  });

  /// Device-generated UUID v4 of the audit row itself.
  final String id;

  /// Kind of the audited entity.
  final AuditEntityType entityType;

  /// Id of the audited entity.
  final String entityId;

  /// What happened to the entity.
  final AuditOperation operation;

  /// When it happened, in UTC.
  final DateTime at;

  /// Returns a copy with the given fields replaced.
  AuditEntry copyWith({
    String? id,
    AuditEntityType? entityType,
    String? entityId,
    AuditOperation? operation,
    DateTime? at,
  }) {
    return AuditEntry(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      at: at ?? this.at,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AuditEntry &&
      other.id == id &&
      other.entityType == entityType &&
      other.entityId == entityId &&
      other.operation == operation &&
      other.at == at;

  @override
  int get hashCode => Object.hash(id, entityType, entityId, operation, at);

  @override
  String toString() => 'AuditEntry(id: $id, entityType: ${entityType.name}, '
      'entityId: $entityId, operation: ${operation.name}, at: $at)';
}
