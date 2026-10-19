import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/shared/utils/money.dart';

void main() {
  group('tryParseEuroCents', () {
    test('reads the comma of Italian and Spanish', () {
      expect(tryParseEuroCents('12,5'), 1250);
      expect(tryParseEuroCents('12,50'), 1250);
      expect(tryParseEuroCents('0,05'), 5);
    });

    test('reads the point of English', () {
      expect(tryParseEuroCents('12.50'), 1250);
      expect(tryParseEuroCents('12.5'), 1250);
    });

    test('reads whole euros, with or without a trailing separator', () {
      expect(tryParseEuroCents('12'), 1200);
      expect(tryParseEuroCents('12,'), 1200);
      expect(tryParseEuroCents('0'), 0);
      expect(tryParseEuroCents(' 7 '), 700);
    });

    test('refuses three decimals', () {
      expect(tryParseEuroCents('12,505'), isNull);
      expect(tryParseEuroCents('1.234'), isNull);
    });

    test('refuses negatives and signs', () {
      expect(tryParseEuroCents('-5'), isNull);
      expect(tryParseEuroCents('-0,50'), isNull);
      expect(tryParseEuroCents('+5'), isNull);
    });

    test('refuses thousands separators, letters and blanks', () {
      expect(tryParseEuroCents('1.234,56'), isNull);
      expect(tryParseEuroCents('1,234.56'), isNull);
      expect(tryParseEuroCents('12 €'), isNull);
      expect(tryParseEuroCents('abc'), isNull);
      expect(tryParseEuroCents(''), isNull);
      expect(tryParseEuroCents(',5'), isNull);
    });

    test('refuses amounts beyond the maximum without overflowing', () {
      expect(tryParseEuroCents('999999999,99'), maxCostCents);
      expect(tryParseEuroCents('1000000000'), isNull);
      expect(tryParseEuroCents('9' * 40), isNull);
    });
  });

  group('formatting', () {
    test('formatEuroCents follows the locale', () {
      // intl uses a non-breaking space before the euro sign.
      String plain(String s) => s.replaceAll('\u00A0', ' ');
      expect(plain(formatEuroCents(123456, 'it')), '1.234,56 €');
      expect(plain(formatEuroCents(123456, 'es')), '1.234,56 €');
      expect(formatEuroCents(123456, 'en'), '€1,234.56');
      expect(plain(formatEuroCents(5, 'it')), '0,05 €');
    });

    test('euroCentsInputText parses back to the same amount', () {
      for (final cents in [0, 5, 1250, 123456, maxCostCents]) {
        for (final locale in ['it', 'es', 'en']) {
          final text = euroCentsInputText(cents, locale);
          expect(tryParseEuroCents(text), cents, reason: '$locale: $text');
        }
      }
      expect(euroCentsInputText(1250, 'es'), '12,50');
      expect(euroCentsInputText(1250, 'en'), '12.50');
    });
  });
}
