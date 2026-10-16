import '../db/daos/audit_log_dao.dart';
import '../models/audit_entry.dart';

/// Read-only access to the audit log.
///
/// Entries are written by the other repositories, inside the transaction of
/// the change they record; this interface never writes.
abstract interface class AuditLogRepository {
  /// Returns the audit entries of one entity, oldest first.
  Future<List<AuditEntry>> getForEntity(
    AuditEntityType entityType,
    String entityId,
  );
}

/// [AuditLogRepository] backed by the local Drift database.
class DriftAuditLogRepository implements AuditLogRepository {
  /// Creates the repository on [_audit].
  const DriftAuditLogRepository(this._audit);

  /// Audit log queries.
  final AuditLogDao _audit;

  @override
  Future<List<AuditEntry>> getForEntity(
    AuditEntityType entityType,
    String entityId,
  ) =>
      _audit.getForEntity(entityType, entityId);
}
