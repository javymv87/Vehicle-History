import '../db/daos/settings_dao.dart';
import '../models/app_preferences.dart';
import '../models/setting_key.dart';
import '../models/units.dart';
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

  /// Emits the values of [keys] now and after every change to any of them,
  /// one entry per key (`null` when not set).
  Stream<Map<SettingKey, String?>> watchMany(Iterable<SettingKey> keys);

  /// Sets [key] to [value], replacing any previous value; `null` clears it.
  Future<void> write(SettingKey key, String? value);

  /// Sets every key of [values] in one transaction: all or nothing.
  Future<void> writeMany(Map<SettingKey, String?> values);
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
  Stream<Map<SettingKey, String?>> watchMany(Iterable<SettingKey> keys) =>
      _settings.watchValues(keys);

  @override
  Future<void> write(SettingKey key, String? value) =>
      _settings.writeValue(key, value, utcNow(_clock));

  @override
  Future<void> writeMany(Map<SettingKey, String?> values) =>
      _settings.writeValues(values, utcNow(_clock));
}

/// Typed accessors for the settings with a non-text value.
extension TypedSettings on SettingsRepository {
  /// Emits when the last backup package was exported, in UTC, or `null`
  /// before the first export.
  Stream<DateTime?> watchLastExportAt() =>
      watch(SettingKey.lastExportAt).map(_parseInstant);

  /// Records [at] (UTC) as the instant of the last export.
  Future<void> writeLastExportAt(DateTime at) =>
      write(SettingKey.lastExportAt, at.toUtc().toIso8601String());

  /// Emits the interface language now and after every change; an absent or
  /// unknown value is [AppLanguage.system]. A write to another key emits
  /// nothing.
  Stream<AppLanguage> watchLanguage() =>
      watch(SettingKey.language).map(AppLanguage.fromCode).distinct();

  /// Stores [language] as the interface language.
  Future<void> writeLanguage(AppLanguage language) =>
      write(SettingKey.language, language.code);

  /// Emits the light / dark mode now and after every change; an absent or
  /// unknown value is [AppThemeMode.system]. A write to another key emits
  /// nothing.
  Stream<AppThemeMode> watchThemeMode() =>
      watch(SettingKey.theme).map(AppThemeMode.fromCode).distinct();

  /// Stores [mode] as the light / dark mode.
  Future<void> writeThemeMode(AppThemeMode mode) =>
      write(SettingKey.theme, mode.code);

  /// Emits the five units now and after every change to any of them; an
  /// absent or unknown value is its SI default. A write to another key
  /// emits nothing.
  Stream<UnitPreferences> watchUnitPreferences() =>
      watchMany(SettingKey.unitKeys)
          .map(
            (values) => UnitPreferences.fromCodes(
              distance: values[SettingKey.unitDistance],
              volume: values[SettingKey.unitVolume],
              temperature: values[SettingKey.unitTemperature],
              pressure: values[SettingKey.unitPressure],
              consumption: values[SettingKey.unitConsumption],
            ),
          )
          .distinct();

  /// Stores all five units of [preferences] at once (a preset), in one
  /// transaction.
  Future<void> writeUnitPreferences(UnitPreferences preferences) => writeMany({
        SettingKey.unitDistance: preferences.distance.code,
        SettingKey.unitVolume: preferences.volume.code,
        SettingKey.unitTemperature: preferences.temperature.code,
        SettingKey.unitPressure: preferences.pressure.code,
        SettingKey.unitConsumption: preferences.consumption.code,
      });

  /// Stores [unit] as the unit of distance, touching no other unit.
  Future<void> writeDistanceUnit(DistanceUnit unit) =>
      write(SettingKey.unitDistance, unit.code);

  /// Stores [unit] as the unit of volume, touching no other unit (the
  /// consumption unit in particular).
  Future<void> writeVolumeUnit(VolumeUnit unit) =>
      write(SettingKey.unitVolume, unit.code);

  /// Stores [unit] as the unit of temperature.
  Future<void> writeTemperatureUnit(TemperatureUnit unit) =>
      write(SettingKey.unitTemperature, unit.code);

  /// Stores [unit] as the unit of pressure.
  Future<void> writePressureUnit(PressureUnit unit) =>
      write(SettingKey.unitPressure, unit.code);

  /// Stores [unit] as the unit of fuel consumption.
  Future<void> writeConsumptionUnit(ConsumptionUnit unit) =>
      write(SettingKey.unitConsumption, unit.code);

  /// Parses an instant stored as ISO-8601 text; an unreadable value counts
  /// as unset rather than failing the screen that shows it.
  static DateTime? _parseInstant(String? value) =>
      value == null ? null : DateTime.tryParse(value)?.toUtc();
}
