import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/models/app_preferences.dart';
import 'package:vehicle_history/data/models/setting_key.dart';

/// The codes of the `language` and `theme` settings: what is on disk must
/// never change with a Dart rename.
void main() {
  test('setting keys keep their codes', () {
    expect(SettingKey.language.code, 'language');
    expect(SettingKey.theme.code, 'theme');
  });

  test('languages keep their codes and round-trip', () {
    expect({
      for (final l in AppLanguage.values) l: l.code,
    }, {
      AppLanguage.system: 'system',
      AppLanguage.italian: 'it',
      AppLanguage.spanish: 'es',
      AppLanguage.english: 'en',
    });
    for (final language in AppLanguage.values) {
      expect(AppLanguage.fromCode(language.code), language);
    }
  });

  test('theme modes keep their codes and round-trip', () {
    expect({
      for (final m in AppThemeMode.values) m: m.code,
    }, {
      AppThemeMode.system: 'system',
      AppThemeMode.light: 'light',
      AppThemeMode.dark: 'dark',
    });
    for (final mode in AppThemeMode.values) {
      expect(AppThemeMode.fromCode(mode.code), mode);
    }
  });

  test('absent or unknown values are system', () {
    for (final code in [null, '', 'fr', 'IT', 'italian']) {
      expect(AppLanguage.fromCode(code), AppLanguage.system, reason: code);
    }
    for (final code in [null, '', 'sepia', 'Dark']) {
      expect(AppThemeMode.fromCode(code), AppThemeMode.system, reason: code);
    }
  });

  test('only system follows the device language', () {
    expect(AppLanguage.system.languageCode, isNull);
    expect(AppLanguage.italian.languageCode, 'it');
    expect(AppLanguage.spanish.languageCode, 'es');
    expect(AppLanguage.english.languageCode, 'en');
  });
}
