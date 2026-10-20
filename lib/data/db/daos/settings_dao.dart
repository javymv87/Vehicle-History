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

  /// Writes [value] for [key], replacing any previous value, stamped with
  /// [now] (UTC).
  Future<void> writeValue(SettingKey key, String? value, DateTime now) =>
      into(settings).insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: key.code,
          value: Value(value),
          updatedAt: now,
        ),
      );
}
