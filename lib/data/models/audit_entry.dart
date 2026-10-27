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

  /// The whole database, for operations that replace all of it, such as
  /// importing a backup package. Its entity id is
  /// [AuditEntry.databaseEntityId].
  database,

  /// An `Attachment`: a file of an entry, a vehicle or an owner (v7).
  attachment,
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

  /// The whole database was replaced by the one in a backup package.
  /// Written once, into the imported database, after the import succeeded;
  /// recorded with [AuditEntityType.database].
  import,

  /// The vehicle was archived (v8): it left the current vehicles, keeping
  /// its whole history read-only. The reading inserted with it has its own
  /// `create` row.
  archive,

  /// An archived vehicle was reactivated (v8): back among the current ones.
  reactivate,
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

  /// Entity id of the rows about the whole database
  /// ([AuditEntityType.database]): the name of the database file.
  static const String databaseEntityId = 'vehicle_history';

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
