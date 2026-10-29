import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/models/units.dart';
import 'package:vehicle_history/l10n/app_localizations.dart';
import 'package:vehicle_history/shared/utils/unit_formatter.dart';

/// The unit formatter: every quantity in both directions, round-trip
/// exactness as the user sees it, locale-aware parsing and the friendly
/// thresholds.
void main() {
  UnitFormatter formatter(
    UnitPreferences preferences, [
    String language = 'en',
  ]) =>
      UnitFormatter(
        preferences: preferences,
        l10n: lookupAppLocalizations(Locale(language)),
      );

  final international = formatter(UnitPreferences.international);
  final imperial = formatter(UnitPreferences.imperial);

  group('distance', () {
    test('formats stored km in the chosen unit, no decimals', () {
      expect(international.distance.format(184300), '184,300 km');
      expect(international.distance.formatValue(184300), '184,300');
      expect(international.distance.symbol, 'km');
      expect(imperial.distance.format(160.9344), '100 mi');
      expect(imperial.distance.format(184300), '114,519 mi');
      expect(imperial.distance.symbol, 'mi');
      expect(
        formatter(UnitPreferences.international, 'es').distance.format(184300),
        '184.300 km',
      );
    });

    test('parses what the user types in the chosen unit into km', () {
      expect(international.distance.parse('184300'), 184300);
      expect(imperial.distance.parse('100'), closeTo(160.9344, 1e-9));
      expect(imperial.distance.parse(' 100 '), closeTo(160.9344, 1e-9));
      expect(international.distance.parse('0'), 0);
    });

    test('typing 100 mi shows 100 mi after the round trip', () {
      final km = imperial.distance.parse('100')!;
      expect(imperial.distance.format(km), '100 mi');
      expect(imperial.distance.inputText(km), '100');
      // The same value in km, decimals hidden.
      expect(international.distance.format(km), '161 km');
    });

    test('inputText gives the editable text without grouping', () {
      expect(international.distance.inputText(184300), '184300');
      expect(imperial.distance.inputText(184300), '114519');
    });

    test('re-typing a shown value gives the stored value back', () {
      // 184 301 km shows as 114519 mi, which alone would parse to less.
      expect(imperial.distance.inputText(184301), '114519');
      expect(imperial.distance.parse('114519'), lessThan(184301));
      expect(imperial.distance.parse('114519', sameAs: 184301), 184301);
      expect(imperial.distance.parse(' 114519 ', sameAs: 184301), 184301);
      // Anything else parses as typed.
      expect(imperial.distance.parse('114520', sameAs: 184301), isNot(184301));
      expect(international.distance.parse('100', sameAs: 100), 100);
    });

    test('refuses negatives, signs, letters, blanks and huge numbers', () {
      for (final text in ['', ' ', '-1', '+1', '1e3', '12 345', '1,234,5']) {
        expect(international.distance.parse(text), isNull, reason: text);
      }
      expect(international.distance.parse('1234567890123'), isNull);
      expect(international.distance.parse('123456789012'), 123456789012);
    });
  });

  group('volume', () {
    test('two decimals, both gallons', () {
      expect(international.volume.format(47.3176473), '47.32 L');
      expect(imperial.volume.format(47.3176473), '12.5 gal');
      expect(imperial.volume.parse('12.5'), closeTo(47.3176473, 1e-6));
      final uk = formatter(
        UnitPreferences.international.copyWith(volume: VolumeUnit.gallonUk),
      );
      expect(uk.volume.format(45.4609), '10 imp gal');
      expect(uk.volume.parse('10'), closeTo(45.4609, 1e-9));
    });

    test('12.5 gal US round-trips', () {
      final litres = imperial.volume.parse('12.5')!;
      expect(imperial.volume.formatValue(litres), '12.5');
      expect(imperial.volume.inputText(litres), '12.5');
      // Stored with three decimals (step 12): the formatter keeps them.
      expect(international.volume.formatValue(47.318), '47.32');
      expect(international.volume.parse('47.318'), 47.318);
    });
  });

  group('temperature', () {
    test('one decimal, negatives allowed', () {
      expect(international.temperature.format(-20.5), '-20.5 °C');
      expect(international.temperature.format(21), '21 °C');
      expect(imperial.temperature.format(100), '212 °F');
      expect(imperial.temperature.parse('-5'), closeTo(-20.5556, 1e-4));
      expect(international.temperature.parse('-5,5'), -5.5);
    });

    test('-5 °F round-trips', () {
      final celsius = imperial.temperature.parse('-5')!;
      expect(imperial.temperature.format(celsius), '-5 °F');
      expect(imperial.temperature.inputText(celsius), '-5');
    });

    test('a value that rounds to zero never shows a minus', () {
      expect(international.temperature.format(-0.04), '0 °C');
      expect(international.distance.format(-0.4), '0 km');
    });
  });

  group('pressure', () {
    test('one decimal in bar, none in psi', () {
      expect(international.pressure.format(2.4), '2.4 bar');
      expect(international.pressure.format(2.41316511), '2.4 bar');
      expect(imperial.pressure.format(2.41316511), '35 psi');
      expect(imperial.pressure.format(1), '15 psi');
    });

    test('35 psi round-trips', () {
      final bar = imperial.pressure.parse('35')!;
      expect(bar, closeTo(2.41317, 1e-5));
      expect(imperial.pressure.format(bar), '35 psi');
      expect(imperial.pressure.inputText(bar), '35');
    });
  });

  group('consumption', () {
    test('one decimal in every unit', () {
      expect(international.consumption.format(7.2), '7.2 L/100 km');
      expect(imperial.consumption.format(7.2), '32.7 mpg');
      final kmPerLitre = formatter(
        UnitPreferences.international
            .copyWith(consumption: ConsumptionUnit.kmPerLitre),
      );
      expect(kmPerLitre.consumption.format(8), '12.5 km/L');
      final uk = formatter(
        UnitPreferences.imperial.copyWith(consumption: ConsumptionUnit.mpgUk),
      );
      expect(uk.consumption.format(7.2), '39.2 mpg (imp)');
    });

    test('7.2 L/100 km ↔ 32.7 mpg US round-trips at display precision', () {
      final si = imperial.consumption.parse('32.7')!;
      expect(si, closeTo(7.193, 0.001));
      expect(imperial.consumption.format(si), '32.7 mpg');
      expect(international.consumption.formatValue(si), '7.2');
      expect(international.consumption.parse('7.2'), 7.2);
      expect(imperial.consumption.formatValue(7.2), '32.7');
    });

    test('0 has no reciprocal and is refused', () {
      expect(imperial.consumption.parse('0'), isNull);
      expect(international.consumption.parse('0'), 0);
    });
  });

  group('locale', () {
    test('formats with the separators of the interface language', () {
      final spanish = formatter(UnitPreferences.imperial, 'es');
      final italian = formatter(UnitPreferences.international, 'it');
      expect(spanish.distance.format(184300), '114.519 mi');
      expect(spanish.volume.format(47.3176473), '12,5 gal');
      expect(italian.consumption.format(7.25), '7,3 L/100 km');
      expect(italian.volume.inputText(47.318), '47,32');
    });

    test('parses either decimal separator whatever the language', () {
      final spanish = formatter(UnitPreferences.international, 'es');
      expect(spanish.volume.parse('12,5'), 12.5);
      expect(spanish.volume.parse('12.5'), 12.5);
      expect(international.volume.parse('12,5'), 12.5);
      // No thousands separator: three decimals, never 1234.
      expect(spanish.volume.parse('1.234'), 1.234);
      expect(spanish.volume.parse('1.234,5'), isNull);
    });
  });

  test('the big-jump threshold reads as a round figure per unit', () {
    expect(international.bigOdometerJumpThreshold, '50,000 km');
    expect(imperial.bigOdometerJumpThreshold, '30,000 mi');
    expect(
      formatter(UnitPreferences.imperial, 'it').bigOdometerJumpThreshold,
      '30.000 mi',
    );
  });
}
