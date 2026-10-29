import 'package:drift/drift.dart';

import '../../models/setting_key.dart';
import '../app_database.dart';
import '../settings_table.dart';

part 'settings_dao.g.dart';

/// Queries on the `settings` key / value table.
///
/// Values travel as text; the repository gives them their type.
@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  /// Creates the DAO on [db]. Obtain it through `AppDatabase.settingsDao`.
  SettingsDao(super.db);

  /// The query selecting the row of [key].
  SimpleSelectStatement<$SettingsTable, SettingRow> _byKey(SettingKey key) =>
      select(settings)..where((s) => s.key.equals(key.code));

  /// Returns the value of [key], or `null` when it was never written or was
  /// cleared.
  Future<String?> readValue(SettingKey key) async =>
      (await _byKey(key).getSingleOrNull())?.value;

  /// Emits the value of [key] now and after every change.
  Stream<String?> watchValue(SettingKey key) =>
      _byKey(key).watchSingleOrNull().map((row) => row?.value);

  /// Emits the values of [keys] now and after every change to any of them:
  /// a map with one entry per key, `null` for a key never written or
  /// cleared.
  Stream<Map<SettingKey, String?>> watchValues(Iterable<SettingKey> keys) {
    final wanted = keys.toList();
    final query = select(settings)
      ..where((s) => s.key.isIn([for (final key in wanted) key.code]));
    return query.watch().map((rows) {
      final byCode = {for (final row in rows) row.key: row.value};
      return {for (final key in wanted) key: byCode[key.code]};
    });
  }

  /// Writes [value] for [key], replacing any previous value, stamped with
  /// [now] (UTC).
  Future<void> writeValue(SettingKey key, String? value, DateTime now) =>
      into(settings).insertOnConflictUpdate(_row(key, value, now));

  /// Writes every entry of [values] in one transaction, each replacing its
  /// previous value and stamped with [now] (UTC): all or nothing.
  Future<void> writeValues(Map<SettingKey, String?> values, DateTime now) =>
      transaction(() async {
        for (final entry in values.entries) {
          await into(settings)
              .insertOnConflictUpdate(_row(entry.key, entry.value, now));
        }
      });

  /// The row of [key] holding [value], stamped with [now].
  SettingsCompanion _row(SettingKey key, String? value, DateTime now) =>
      SettingsCompanion.insert(
        key: key.code,
        value: Value(value),
        updatedAt: now,
      );
}
