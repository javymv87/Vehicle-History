import 'package:drift/drift.dart';

/// The `settings` table: app-wide preferences and bookkeeping values, one row
/// per key, not linked to any vehicle (`Docs/02_data_model.md`).
///
/// A plain key / value store. Rows have no soft-delete flag and are not
/// audited: a setting is not user data, and overwriting it loses nothing the
/// user cannot set again. Keys are the codes of `SettingKey`. Added in schema
/// v6.
@DataClassName('SettingRow')
class Settings extends Table {
  /// Stable code of the setting, such as `last_export_at`.
  TextColumn get key => text()();

  /// Value of the setting as text; `null` when it was cleared. Each key
  /// documents its own format (an instant is ISO-8601 UTC text).
  TextColumn get value => text().nullable()();

  /// When the value was last written, in UTC.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
