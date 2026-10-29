import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/app_preferences.dart';
import 'package:vehicle_history/data/models/setting_key.dart';
import 'package:vehicle_history/data/models/units.dart';
import 'package:vehicle_history/data/repositories/settings_repository.dart';

import 'test_support.dart';

/// The `settings` key / value table (schema v6).
void main() {
  late AppDatabase db;
  late FakeClock clock;
  late DriftSettingsRepository settings;

  setUp(() {
    db = openTestDatabase();
    clock = FakeClock(DateTime.utc(2026, 10, 20, 16, 30));
    settings = DriftSettingsRepository(db.settingsDao, clock: clock.call);
  });

  tearDown(() => db.close());

  /// The raw rows of the table, as `key=value@updated_at`.
  Future<List<String>> rows() async => [
        for (final r in await db
            .customSelect('SELECT key, value, updated_at FROM settings')
            .get())
          '${r.read<String>('key')}=${r.read<String?>('value')}'
              '@${r.read<String>('updated_at')}',
      ];

  test('an unset key reads as null', () async {
    expect(await settings.read(SettingKey.lastExportAt), isNull);
    expect(await settings.watch(SettingKey.lastExportAt).first, isNull);
  });

  test(
      'write stores the value under its code with a UTC timestamp, and a '
      'second write replaces it', () async {
    await settings.write(SettingKey.lastExportAt, 'a');
    clock.advance();
    await settings.write(SettingKey.lastExportAt, 'b');
    expect(await settings.read(SettingKey.lastExportAt), 'b');
    expect(await rows(), ['last_export_at=b@2026-10-20T16:31:00.000Z']);
  });

  test('writing null clears the value', () async {
    await settings.write(SettingKey.lastExportAt, 'a');
    await settings.write(SettingKey.lastExportAt, null);
    expect(await settings.read(SettingKey.lastExportAt), isNull);
  });

  test('watch emits after every write', () async {
    final values = settings.watch(SettingKey.lastExportAt);
    expect(values, emitsInOrder([null, 'x']));
    await pumpEventQueue();
    await settings.write(SettingKey.lastExportAt, 'x');
  });

  test('settings writes are not audited', () async {
    await settings.write(SettingKey.lastExportAt, 'a');
    final audit = await db.customSelect('SELECT * FROM audit_log').get();
    expect(audit, isEmpty);
  });

  test('last_export_at is a UTC instant as ISO-8601 text', () async {
    await settings.writeLastExportAt(DateTime.utc(2026, 10, 20, 18, 30));
    expect(
      await settings.read(SettingKey.lastExportAt),
      '2026-10-20T18:30:00.000Z',
    );
    expect(
      await settings.watchLastExportAt().first,
      DateTime.utc(2026, 10, 20, 18, 30),
    );
  });

  group('language and theme', () {
    test('absent rows read as system', () async {
      expect(await settings.watchLanguage().first, AppLanguage.system);
      expect(await settings.watchThemeMode().first, AppThemeMode.system);
    });

    test('are stored as their stable codes', () async {
      await settings.writeLanguage(AppLanguage.spanish);
      await settings.writeThemeMode(AppThemeMode.dark);
      expect(
        await rows(),
        unorderedEquals([
          'language=es@2026-10-20T16:30:00.000Z',
          'theme=dark@2026-10-20T16:30:00.000Z',
        ]),
      );
      expect(await settings.watchLanguage().first, AppLanguage.spanish);
      expect(await settings.watchThemeMode().first, AppThemeMode.dark);
    });

    test('emit every change', () async {
      final languages = settings.watchLanguage();
      final themes = settings.watchThemeMode();
      expectLater(
        languages,
        emitsInOrder([
          AppLanguage.system,
          AppLanguage.italian,
          AppLanguage.system,
        ]),
      );
      expectLater(
        themes,
        emitsInOrder([AppThemeMode.system, AppThemeMode.light]),
      );
      await pumpEventQueue();
      await settings.writeLanguage(AppLanguage.italian);
      await settings.writeThemeMode(AppThemeMode.light);
      await pumpEventQueue();
      await settings.writeLanguage(AppLanguage.system);
      await pumpEventQueue();
    });

    test('an unknown stored value reads as system', () async {
      await settings.write(SettingKey.language, 'klingon');
      await settings.write(SettingKey.theme, 'sepia');
      expect(await settings.watchLanguage().first, AppLanguage.system);
      expect(await settings.watchThemeMode().first, AppThemeMode.system);
    });
  });

  group('units', () {
    test('absent rows read as the SI defaults', () async {
      expect(
        await settings.watchUnitPreferences().first,
        UnitPreferences.defaults,
      );
    });

    test('a preset writes the five keys at once, as their codes', () async {
      await settings.writeUnitPreferences(UnitPreferences.imperial);
      expect(
        await rows(),
        unorderedEquals([
          'unit_distance=mi@2026-10-20T16:30:00.000Z',
          'unit_volume=gal_us@2026-10-20T16:30:00.000Z',
          'unit_temperature=f@2026-10-20T16:30:00.000Z',
          'unit_pressure=psi@2026-10-20T16:30:00.000Z',
          'unit_consumption=mpg_us@2026-10-20T16:30:00.000Z',
        ]),
      );
      expect(
        await settings.watchUnitPreferences().first,
        UnitPreferences.imperial,
      );
    });

    test('one unit writes its key alone and emits the new set', () async {
      final sets = settings.watchUnitPreferences();
      expectLater(
        sets,
        emitsInOrder([
          UnitPreferences.defaults,
          const UnitPreferences(distance: DistanceUnit.mile),
          const UnitPreferences(
            distance: DistanceUnit.mile,
            volume: VolumeUnit.gallonUk,
          ),
        ]),
      );
      await pumpEventQueue();
      await settings.writeDistanceUnit(DistanceUnit.mile);
      await pumpEventQueue();
      await settings.writeVolumeUnit(VolumeUnit.gallonUk);
      await pumpEventQueue();
      expect(await rows(), hasLength(2));
      // The consumption unit never follows the volume.
      expect(await settings.read(SettingKey.unitConsumption), isNull);
    });

    test('unknown stored values read as the SI unit', () async {
      await settings.write(SettingKey.unitDistance, 'furlong');
      await settings.write(SettingKey.unitPressure, 'psi');
      expect(
        await settings.watchUnitPreferences().first,
        const UnitPreferences(pressure: PressureUnit.psi),
      );
    });

    test('the unit keys travel with the data, like language and theme', () {
      for (final key in SettingKey.unitKeys) {
        expect(key.scope, SettingScope.shared, reason: key.code);
      }
    });
  });
}
