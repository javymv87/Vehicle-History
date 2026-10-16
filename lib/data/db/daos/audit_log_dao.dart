import 'package:drift/drift.dart';

import '../../models/audit_entry.dart';
import '../app_database.dart';
import '../audit_log_table.dart';
import '../row_mappers.dart';

part 'audit_log_dao.g.dart';

/// Queries on the append-only `audit_log` table.
///
/// Accepts and returns domain models only. There is deliberately no update or
/// delete method.
@DriftAccessor(tables: [AuditLog])
class AuditLogDao extends DatabaseAccessor<AppDatabase>
    with _$AuditLogDaoMixin {
  /// Creates the DAO on [db]. Obtain it through `AppDatabase.auditLogDao`.
  AuditLogDao(super.db);

  /// Appends [entry].
  ///
  /// Call it inside the transaction of the write it records, so both land or
  /// neither does.
  Future<void> insertEntry(AuditEntry entry) =>
      into(auditLog).insert(entry.toInsertCompanion());

  /// Returns the audit entries of one entity, oldest first.
  ///
  /// Entries with the same timestamp keep their insertion order.
  Future<List<AuditEntry>> getForEntity(
    AuditEntityType entityType,
    String entityId,
  ) async {
    final rows = await (select(auditLog)
          ..where(
            (a) =>
                a.entityType.equalsValue(entityType) &
                a.entityId.equals(entityId),
          )
          ..orderBy([
            (a) => OrderingTerm(expression: a.at),
            (a) => OrderingTerm(expression: a.rowId),
          ]))
        .get();
    return [for (final r in rows) r.toModel()];
  }
}
