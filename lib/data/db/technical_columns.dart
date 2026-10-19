import 'package:drift/drift.dart';

/// Technical columns shared by every main table (`Docs/02_data_model.md`).
///
/// Mixed into a table class instead of being repeated, so the shape of `id`,
/// the timestamps and the soft-delete flag can never drift between tables.
/// The audit log does not use it: it is append-only and has no soft delete.
mixin TechnicalColumns on Table {
  /// Device-generated UUID v4, the primary key.
  TextColumn get id => text()();

  /// Creation instant, in UTC.
  DateTimeColumn get createdAt => dateTime()();

  /// Last modification instant, in UTC.
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft-delete flag. Deleted rows stay on disk but are hidden from reads.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// When the row was soft-deleted, in UTC; `null` while it is live.
  ///
  /// Added in schema v5 for the Trash and its 30-day cleanup. Always set
  /// together with [deleted] and cleared together with it on restore.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
