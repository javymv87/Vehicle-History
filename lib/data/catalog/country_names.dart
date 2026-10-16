import 'dart:convert';

import 'search_text.dart';

/// A country: its ISO 3166-1 alpha-2 code and its name in one language.
class Country {
  /// Creates a country entry.
  const Country({required this.code, required this.name});

  /// ISO 3166-1 alpha-2 code, upper case, e.g. `IT`.
  final String code;

  /// Name in the requested language, e.g. "Italia".
  final String name;

  @override
  String toString() => 'Country($code)';
}

/// Country names in the app languages, from the bundled Unicode CLDR table.
///
/// Used for the owner's nationality: it is stored as the ISO code, or as the
/// text typed by the user when no country fits. Pure Dart, so tests can feed
/// it a small fixture.
class CountryNames {
  /// Creates the table from names by language code, then by country code.
  CountryNames(Map<String, Map<String, String>> namesByLanguage)
      : _names = namesByLanguage,
        _sorted = {
          for (final MapEntry(key: language, value: names)
              in namesByLanguage.entries)
            language: List.unmodifiable(
              [
                for (final MapEntry(:key, :value) in names.entries)
                  Country(code: key, name: value),
              ]..sort(
                  (a, b) =>
                      foldForSearch(a.name).compareTo(foldForSearch(b.name)),
                ),
            ),
        };

  /// Parses the asset written by `tool/build_country_names.dart`.
  factory CountryNames.fromJson(String json) {
    final root = jsonDecode(json) as Map<String, dynamic>;
    final names = root['names'] as Map<String, dynamic>;
    return CountryNames({
      for (final MapEntry(:key, :value) in names.entries)
        key: (value as Map<String, dynamic>).cast<String, String>(),
    });
  }

  /// Language used when the requested one has no table.
  static const String fallbackLanguage = 'en';

  /// Names by language, then by code.
  final Map<String, Map<String, String>> _names;

  /// Countries by language, sorted by name.
  final Map<String, List<Country>> _sorted;

  /// The table of [languageCode], or the English one.
  String _language(String languageCode) =>
      _names.containsKey(languageCode) ? languageCode : fallbackLanguage;

  /// Every country, with names in [languageCode], sorted alphabetically.
  List<Country> countries(String languageCode) =>
      _sorted[_language(languageCode)]!;

  /// The countries whose name in [languageCode] contains [query], ignoring
  /// case and accents.
  List<Country> search(String query, String languageCode) =>
      searchByName(countries(languageCode), (c) => c.name, query);

  /// The name of the country with ISO [code] in [languageCode], or `null`
  /// when [code] is not a known code (codes are matched exactly, upper case).
  String? nameOf(String code, String languageCode) =>
      _names[_language(languageCode)]![code];

  /// How a stored nationality is shown: the localised country name when
  /// [stored] is a known code, otherwise the text exactly as typed.
  String displayNationality(String stored, String languageCode) =>
      nameOf(stored, languageCode) ?? stored;
}
