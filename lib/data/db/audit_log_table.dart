import 'package:drift/drift.dart';

import 'converters.dart';

/// The `audit_log` table: one row per create, update, delete and restore.
///
/// Append-only. It has no soft-delete flag and no `updated_at`, because a row
/// is never changed once written. `entity_id` has no foreign key: it points
/// into different tables depending on `entity_type`.
@DataClassName('AuditLogRow')
@TableIndex(name: 'audit_log_entity', columns: {#entityType, #entityId})
class AuditLog extends Table {
  /// Device-generated UUID v4 of the audit row.
  TextColumn get id => text()();

  /// Kind of the audited entity (`owner`, `vehicle`, `logEntry`).
  TextColumn get entityType => text().map(const AuditEntityTypeConverter())();

  /// Id of the audited entity.
  TextColumn get entityId => text()();

  /// Operation performed (`create`, `update`, `delete`, `restore`, `purge`).
  ///
  /// Plain text with no CHECK constraint, so a new operation code needs no
  /// schema change; only [AuditOperationConverter] has to learn it.
  TextColumn get operation => text().map(const AuditOperationConverter())();

  /// When the operation happened, in UTC.
  DateTimeColumn get at => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
