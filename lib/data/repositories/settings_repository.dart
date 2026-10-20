import '../db/daos/settings_dao.dart';
import '../models/setting_key.dart';
import 'repository_support.dart';

/// Access to the app settings (`settings` table), one text value per
/// [SettingKey].
///
/// Settings are not user data: writes are not audited and there is no soft
/// delete. Writing `null` clears a value.
abstract interface class SettingsRepository {
  /// Returns the value of [key], or `null` when it is not set.
  Future<String?> read(SettingKey key);

  /// Emits the value of [key] now and after every change.
  Stream<String?> watch(SettingKey key);

  /// Sets [key] to [value], replacing any previous value; `null` clears it.
  Future<void> write(SettingKey key, String? value);
}

/// [SettingsRepository] backed by the local Drift database.
class DriftSettingsRepository implements SettingsRepository {
  /// Creates the repository on [_settings], stamping writes with [_clock].
  DriftSettingsRepository(this._settings, {UtcClock clock = systemUtcClock})
      : _clock = clock;

  /// Settings queries.
  final SettingsDao _settings;

  /// Source of the `updated_at` instants.
  final UtcClock _clock;

  @override
  Future<String?> read(SettingKey key) => _settings.readValue(key);

  @override
  Stream<String?> watch(SettingKey key) => _settings.watchValue(key);

  @override
  Future<void> write(SettingKey key, String? value) =>
      _settings.writeValue(key, value, utcNow(_clock));
}

/// Typed accessors for the settings with a non-text value.
extension TypedSettings on SettingsRepository {
  /// Emits when the last backup package was exported, in UTC, or `null`
  /// before the first export.
  Stream<DateTime?> watchLastExportAt() =>
      watch(SettingKey.lastExportAt).map(_parseInstant);

  /// Records [at] (UTC) as the instant of the last successful export.
  Future<void> writeLastExportAt(DateTime at) =>
      write(SettingKey.lastExportAt, at.toUtc().toIso8601String());

  /// Parses an instant stored as ISO-8601 text; an unreadable value counts
  /// as unset rather than failing the screen that shows it.
  static DateTime? _parseInstant(String? value) =>
      value == null ? null : DateTime.tryParse(value)?.toUtc();
}
