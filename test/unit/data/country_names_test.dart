import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/catalog/country_names.dart';

import '../../support/catalog_fixtures.dart';

void main() {
  late CountryNames countries;

  setUp(() => countries = countryNamesFixture());

  List<String> codes(List<Country> list) => [for (final c in list) c.code];

  test('a known code shows the country name in the requested language', () {
    expect(countries.displayNationality('IT', 'it'), 'Italia');
    expect(countries.displayNationality('IT', 'en'), 'Italy');
    expect(countries.displayNationality('ES', 'es'), 'España');
    expect(countries.nameOf('CU', 'es'), 'Cuba');
  });

  test('free text is shown exactly as typed', () {
    expect(countries.displayNationality('Cubana', 'es'), 'Cubana');
    expect(countries.displayNationality('kosovara', 'it'), 'kosovara');
    // Codes are matched exactly: lower case is free text, not a code.
    expect(countries.displayNationality('it', 'it'), 'it');
    expect(countries.nameOf('XX', 'en'), isNull);
  });

  test('an unsupported language falls back to English', () {
    expect(countries.displayNationality('ES', 'de'), 'Spain');
    expect(codes(countries.search('spa', 'fr')), ['ES']);
  });

  test('countries are sorted by their name in each language', () {
    expect(codes(countries.countries('es')), ['CU', 'CW', 'ES', 'IT', 'TR']);
    expect(codes(countries.countries('it')), ['CU', 'CW', 'IT', 'ES', 'TR']);
  });

  test('search ignores case and accents and matches anywhere', () {
    expect(codes(countries.search('cub', 'es')), ['CU']);
    expect(codes(countries.search('CU', 'es')), ['CU', 'CW']);
    expect(codes(countries.search('turquia', 'es')), ['TR']);
    expect(codes(countries.search('curacao', 'it')), ['CW']);
    expect(codes(countries.search('ali', 'it')), ['IT']);
    expect(countries.search('zzz', 'en'), isEmpty);
  });

  test('the bundled asset has every ISO 3166-1 country in each language', () {
    final asset = CountryNames.fromJson(
      File('assets/countries/country_names.json').readAsStringSync(),
    );
    for (final language in ['en', 'es', 'it']) {
      expect(asset.countries(language), hasLength(249), reason: language);
    }
    expect(asset.nameOf('IT', 'it'), 'Italia');
    expect(asset.nameOf('CU', 'es'), 'Cuba');
    expect(asset.nameOf('EU', 'en'), isNull);
  });
}
