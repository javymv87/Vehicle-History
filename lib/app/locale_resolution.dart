import 'dart:ui';

/// The locale used when none of the device locales is supported.
///
/// English, as decided in `Docs/06_settings_and_i18n.md`.
const Locale fallbackLocale = Locale('en');

/// Picks the app locale for the device's preferred [locales].
///
/// Each device locale is matched against [supportedLocales] by language code
/// only, so a regional variant such as `it_CH` resolves to `it`. Device
/// locales are tried in the user's order of preference; when none matches,
/// [fallbackLocale] is returned.
///
/// Intended for `MaterialApp.localeListResolutionCallback`.
Locale resolveAppLocale(
  List<Locale>? locales,
  Iterable<Locale> supportedLocales,
) {
  for (final locale in locales ?? const <Locale>[]) {
    for (final supported in supportedLocales) {
      if (supported.languageCode == locale.languageCode) {
        return supported;
      }
    }
  }
  return fallbackLocale;
}
