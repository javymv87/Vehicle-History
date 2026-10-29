import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/models/setting_key.dart';
import 'package:vehicle_history/data/models/units.dart';

/// The units of measurement: stable codes, conversion factors in both
/// directions, the derived presets and the friendly thresholds.
void main() {
  group('codes', () {
    test('setting keys keep their codes', () {
      expect(
        [for (final key in SettingKey.unitKeys) key.code],
        [
          'unit_distance',
          'unit_volume',
          'unit_temperature',
          'unit_pressure',
          'unit_consumption',
        ],
      );
      for (final key in SettingKey.unitKeys) {
        expect(key.scope, SettingKey.language.scope, reason: key.code);
      }
    });

    test('units keep their codes and round-trip', () {
      expect(
        {for (final u in DistanceUnit.values) u: u.code},
        {DistanceUnit.kilometre: 'km', DistanceUnit.mile: 'mi'},
      );
      expect(
        {for (final u in VolumeUnit.values) u: u.code},
        {
          VolumeUnit.litre: 'l',
          VolumeUnit.gallonUs: 'gal_us',
          VolumeUnit.gallonUk: 'gal_uk',
        },
      );
      expect(
        {for (final u in TemperatureUnit.values) u: u.code},
        {TemperatureUnit.celsius: 'c', TemperatureUnit.fahrenheit: 'f'},
      );
      expect(
        {for (final u in PressureUnit.values) u: u.code},
        {PressureUnit.bar: 'bar', PressureUnit.psi: 'psi'},
      );
      expect(
        {for (final u in ConsumptionUnit.values) u: u.code},
        {
          ConsumptionUnit.litresPer100Km: 'l_100km',
          ConsumptionUnit.kmPerLitre: 'km_l',
          ConsumptionUnit.mpgUs: 'mpg_us',
          ConsumptionUnit.mpgUk: 'mpg_uk',
        },
      );
      for (final u in DistanceUnit.values) {
        expect(DistanceUnit.fromCode(u.code), u);
      }
      for (final u in VolumeUnit.values) {
        expect(VolumeUnit.fromCode(u.code), u);
      }
      for (final u in TemperatureUnit.values) {
        expect(TemperatureUnit.fromCode(u.code), u);
      }
      for (final u in PressureUnit.values) {
        expect(PressureUnit.fromCode(u.code), u);
      }
      for (final u in ConsumptionUnit.values) {
        expect(ConsumptionUnit.fromCode(u.code), u);
      }
    });

    test('absent or unknown codes are the SI unit', () {
      for (final code in [null, '', 'KM', 'miles', 'furlong']) {
        expect(DistanceUnit.fromCode(code), DistanceUnit.kilometre);
        expect(VolumeUnit.fromCode(code), VolumeUnit.litre);
        expect(TemperatureUnit.fromCode(code), TemperatureUnit.celsius);
        expect(PressureUnit.fromCode(code), PressureUnit.bar);
        expect(
          ConsumptionUnit.fromCode(code),
          ConsumptionUnit.litresPer100Km,
        );
      }
    });
  });

  group('conversions', () {
    test('SI units convert to themselves', () {
      for (final unit in <UnitConversion>[
        DistanceUnit.kilometre,
        VolumeUnit.litre,
        TemperatureUnit.celsius,
        PressureUnit.bar,
        ConsumptionUnit.litresPer100Km,
      ]) {
        expect(unit.toSI(12.5), 12.5, reason: unit.code);
        expect(unit.fromSI(12.5), 12.5, reason: unit.code);
      }
    });

    test('distance: 1 mi = 1.609344 km', () {
      expect(DistanceUnit.mile.toSI(100), closeTo(160.9344, 1e-9));
      expect(DistanceUnit.mile.fromSI(160.9344), closeTo(100, 1e-9));
      expect(DistanceUnit.mile.fromSI(50000), closeTo(31068.56, 0.01));
    });

    test('volume: US and imperial gallons', () {
      expect(VolumeUnit.gallonUs.toSI(12.5), closeTo(47.3176473, 1e-6));
      expect(VolumeUnit.gallonUs.fromSI(47.3176473), closeTo(12.5, 1e-9));
      expect(VolumeUnit.gallonUk.toSI(1), closeTo(4.54609, 1e-9));
      expect(VolumeUnit.gallonUk.fromSI(45.4609), closeTo(10, 1e-9));
    });

    test('temperature: °F = °C × 9/5 + 32', () {
      expect(TemperatureUnit.fahrenheit.fromSI(0), 32);
      expect(TemperatureUnit.fahrenheit.fromSI(100), 212);
      expect(TemperatureUnit.fahrenheit.toSI(-5), closeTo(-20.5556, 1e-4));
      expect(
        TemperatureUnit.fahrenheit.fromSI(-20.555555555),
        closeTo(-5, 1e-6),
      );
      expect(TemperatureUnit.fahrenheit.toSI(-40), -40);
    });

    test('pressure: 1 bar = 14.503773773 psi', () {
      expect(PressureUnit.psi.fromSI(1), closeTo(14.503773773, 1e-9));
      expect(PressureUnit.psi.toSI(35), closeTo(2.41317, 1e-5));
      expect(PressureUnit.psi.fromSI(2.41316511), closeTo(35, 1e-6));
    });

    test('consumption: reciprocals derived from the other factors', () {
      expect(ConsumptionUnit.kmPerLitre.fromSI(8), 12.5);
      expect(ConsumptionUnit.kmPerLitre.toSI(12.5), 8);
      // 7.2 L/100 km ≈ 32.7 mpg (US) and ≈ 39.2 mpg (imperial).
      expect(ConsumptionUnit.mpgUs.fromSI(7.2), closeTo(32.669, 0.001));
      expect(ConsumptionUnit.mpgUs.toSI(32.7), closeTo(7.193, 0.001));
      expect(ConsumptionUnit.mpgUk.fromSI(7.2), closeTo(39.233, 0.001));
      // The factors come from the distance and volume units, not typed by
      // hand: 100 × 3.785411784 / 1.609344.
      expect(ConsumptionUnit.mpgUs.fromSI(1), closeTo(235.214583, 1e-6));
      expect(ConsumptionUnit.mpgUk.fromSI(1), closeTo(282.480936, 1e-6));
      // 0 has no finite reciprocal; the formatter refuses it as input.
      expect(ConsumptionUnit.mpgUs.toSI(0), double.infinity);
      expect(ConsumptionUnit.litresPer100Km.toSI(0), 0);
    });

    test('consumption units know their volume', () {
      expect(ConsumptionUnit.litresPer100Km.volumeUnit, VolumeUnit.litre);
      expect(ConsumptionUnit.kmPerLitre.volumeUnit, VolumeUnit.litre);
      expect(ConsumptionUnit.mpgUs.volumeUnit, VolumeUnit.gallonUs);
      expect(ConsumptionUnit.mpgUk.volumeUnit, VolumeUnit.gallonUk);
    });
  });

  group('preferences and presets', () {
    test('defaults are the international preset', () {
      expect(UnitPreferences.defaults, UnitPreferences.international);
      expect(UnitPreferences.fromCodes(), UnitPreferences.international);
      expect(UnitPreferences.defaults.preset, UnitPreset.international);
      expect(UnitPreferences.imperial.preset, UnitPreset.imperial);
    });

    test('are read from the stored codes, unknown ones as defaults', () {
      expect(
        UnitPreferences.fromCodes(
          distance: 'mi',
          volume: 'gal_us',
          temperature: 'f',
          pressure: 'psi',
          consumption: 'mpg_us',
        ),
        UnitPreferences.imperial,
      );
      expect(
        UnitPreferences.fromCodes(distance: 'mi', volume: 'bogus'),
        const UnitPreferences(distance: DistanceUnit.mile),
      );
    });

    test('one unit away from a preset is custom, and back again', () {
      final miles =
          UnitPreferences.international.copyWith(distance: DistanceUnit.mile);
      expect(miles.preset, UnitPreset.custom);
      expect(
        miles.copyWith(distance: DistanceUnit.kilometre).preset,
        UnitPreset.international,
      );
      final imperialUk =
          UnitPreferences.imperial.copyWith(volume: VolumeUnit.gallonUk);
      expect(imperialUk.preset, UnitPreset.custom);
      expect(
        imperialUk.copyWith(volume: VolumeUnit.gallonUs).preset,
        UnitPreset.imperial,
      );
    });

    test('imperial units never include the UK ones', () {
      expect(UnitPreferences.imperial.volume, VolumeUnit.gallonUs);
      expect(UnitPreferences.imperial.consumption, ConsumptionUnit.mpgUs);
    });

    test('ofPreset gives the fixed sets and refuses custom', () {
      expect(
        UnitPreferences.ofPreset(UnitPreset.international),
        UnitPreferences.international,
      );
      expect(
        UnitPreferences.ofPreset(UnitPreset.imperial),
        UnitPreferences.imperial,
      );
      expect(
        () => UnitPreferences.ofPreset(UnitPreset.custom),
        throwsArgumentError,
      );
    });

    test('volume and consumption mismatch is only a hint', () {
      expect(UnitPreferences.defaults.volumeConsumptionMismatch, isFalse);
      expect(UnitPreferences.imperial.volumeConsumptionMismatch, isFalse);
      expect(
        UnitPreferences.defaults
            .copyWith(volume: VolumeUnit.gallonUs)
            .volumeConsumptionMismatch,
        isTrue,
      );
      expect(
        UnitPreferences.imperial
            .copyWith(consumption: ConsumptionUnit.mpgUk)
            .volumeConsumptionMismatch,
        isTrue,
      );
      expect(
        UnitPreferences.defaults
            .copyWith(consumption: ConsumptionUnit.kmPerLitre)
            .volumeConsumptionMismatch,
        isFalse,
      );
    });
  });

  test('the big-jump threshold has a friendly figure per distance unit', () {
    expect(friendlyBigOdometerJump(DistanceUnit.kilometre), 50000);
    expect(friendlyBigOdometerJump(DistanceUnit.mile), 30000);
  });
}
