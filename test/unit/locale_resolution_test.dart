import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/locale_resolution.dart';
import 'package:vehicle_history/l10n/app_localizations.dart';

void main() {
  const supported = AppLocalizations.supportedLocales;

  /// Resolves a single device locale against the app's supported locales.
  Locale resolve(Locale device) => resolveAppLocale([device], supported);

  group('resolveAppLocale', () {
    test('supported languages resolve to themselves', () {
      expect(resolve(const Locale('it')), const Locale('it'));
      expect(resolve(const Locale('es')), const Locale('es'));
      expect(resolve(const Locale('en')), const Locale('en'));
    });

    test('regional variants match by language code', () {
      expect(resolve(const Locale('it', 'CH')), const Locale('it'));
      expect(resolve(const Locale('es', 'MX')), const Locale('es'));
      expect(resolve(const Locale('en', 'GB')), const Locale('en'));
    });

    test('an unsupported language falls back to English', () {
      expect(resolve(const Locale('de')), const Locale('en'));
    });

    test('the first supported device locale in preference order wins', () {
      expect(
        resolveAppLocale(
          const [Locale('de'), Locale('es'), Locale('it')],
          supported,
        ),
        const Locale('es'),
      );
    });

    test('a missing or empty device locale list falls back to English', () {
      expect(resolveAppLocale(null, supported), fallbackLocale);
      expect(resolveAppLocale(const [], supported), fallbackLocale);
    });
  });
}
