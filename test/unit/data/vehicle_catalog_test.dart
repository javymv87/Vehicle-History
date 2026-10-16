import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/catalog/search_text.dart';
import 'package:vehicle_history/data/catalog/vehicle_catalog.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';

import '../../support/catalog_fixtures.dart';

void main() {
  late VehicleCatalog catalog;

  setUp(() => catalog = vehicleCatalogFixture());

  List<String> names(Iterable<Object> items) => [
        for (final item in items)
          switch (item) {
            CatalogMake(:final name) => name,
            CatalogModel(:final name) => name,
            _ => throw ArgumentError(item),
          },
      ];

  group('foldForSearch', () {
    test('ignores case and accents', () {
      expect(foldForSearch('Doblò'), 'doblo');
      expect(foldForSearch('ŠKODA'), 'skoda');
      expect(foldForSearch('Citroën'), 'citroen');
      expect(foldForSearch('Turquía'), 'turquia');
      expect(foldForSearch('Curaçao'), 'curacao');
    });
  });

  group('by kind', () {
    test('each kind offers only its own makes and models', () {
      expect(names(catalog.makes(VehicleKind.van)), ['Fiat']);
      expect(
        names(catalog.models(VehicleKind.van, 'fiat')),
        ['Ducato', 'Doblò'],
      );
      expect(names(catalog.makes(VehicleKind.motorcycle)), ['Honda', 'Ducati']);
      expect(names(catalog.makes(VehicleKind.moped)), ['Piaggio']);
    });

    test('the same make has different models per kind', () {
      expect(
        names(catalog.models(VehicleKind.car, 'honda')),
        ['Civic', 'Jazz'],
      );
      expect(
        names(catalog.models(VehicleKind.motorcycle, 'honda')),
        ['CB500', 'SH125', 'SH150'],
      );
    });

    test('an unknown make has no models', () {
      expect(catalog.make(VehicleKind.car, 'zastava'), isNull);
      expect(catalog.models(VehicleKind.car, 'zastava'), isEmpty);
      expect(catalog.models(VehicleKind.van, 'honda'), isEmpty);
    });
  });

  group('order', () {
    test('ranked makes first by popularity, then the rest alphabetically', () {
      expect(
        names(catalog.makes(VehicleKind.car)),
        ['Fiat', 'Honda', 'Alfa Romeo', 'Škoda'],
      );
      expect(catalog.featuredCount(VehicleKind.car), 3);
    });

    test('only the top makes are featured; the others are alphabetical', () {
      // 25 ranked makes: the 20 most popular lead, the last 5 are sorted by
      // name whatever their popularity.
      final makes = [
        for (var i = 1; i <= 25; i++)
          CatalogMake(
            slug: 'm$i',
            name: 'Make ${String.fromCharCode(0x41 + i)}',
            popularity: i,
            models: const [],
          ),
      ];
      final big = VehicleCatalog(
        release: 'test',
        makesByKind: {VehicleKind.car: makes},
      );
      final ordered = big.makes(VehicleKind.car);
      expect(big.featuredCount(VehicleKind.car), 20);
      expect(
        [for (final m in ordered.take(20)) m.popularity],
        [for (var p = 25; p >= 6; p--) p],
      );
      expect(names(ordered.skip(20)), [
        'Make B',
        'Make C',
        'Make D',
        'Make E',
        'Make F',
      ]);
    });

    test('models by popularity decile, then alphabetically, unranked last', () {
      expect(names(catalog.models(VehicleKind.car, 'fiat')), [
        'Punto',
        'Panda',
        'Doblò',
        'Grande Punto',
        'Multipla',
        '500',
      ]);
    });
  });

  group('search', () {
    test('matches anywhere in the name, ignoring case and accents', () {
      expect(names(catalog.searchMakes(VehicleKind.car, 'SKO')), ['Škoda']);
      expect(names(catalog.searchMakes(VehicleKind.car, 'romeo')), [
        'Alfa Romeo',
      ]);
      expect(
        names(catalog.searchModels(VehicleKind.car, 'fiat', 'dobló')),
        ['Doblò'],
      );
      expect(
        names(catalog.searchModels(VehicleKind.car, 'fiat', 'dobl')),
        ['Doblò'],
      );
    });

    test('keeps the popularity order', () {
      expect(
        names(catalog.searchModels(VehicleKind.car, 'fiat', 'punto')),
        ['Punto', 'Grande Punto'],
      );
      expect(names(catalog.searchMakes(VehicleKind.car, 'a')), [
        'Fiat',
        'Honda',
        'Alfa Romeo',
        'Škoda',
      ]);
    });

    test('a blank query returns everything; no match returns nothing', () {
      expect(catalog.searchMakes(VehicleKind.car, '  '), hasLength(4));
      expect(catalog.searchMakes(VehicleKind.car, 'zastava'), isEmpty);
    });

    test('searches only the chosen kind', () {
      expect(catalog.searchMakes(VehicleKind.moped, 'fiat'), isEmpty);
      expect(
        names(catalog.searchModels(VehicleKind.motorcycle, 'honda', 'sh')),
        ['SH125', 'SH150'],
      );
    });
  });

  group('bundled asset', () {
    final asset = VehicleCatalog.fromJson(
      File('assets/catalog/vehicle_catalog.json').readAsStringSync(),
    );

    test('is the pinned VehiclesDB release', () {
      expect(asset.release, 'v2026.09.1');
    });

    test('contains the spot-check models', () {
      const spotCheck = {
        VehicleKind.car: {
          'fiat': ['punto', 'panda'],
          'toyota': ['yaris'],
          'volkswagen': ['golf'],
          'renault': ['clio'],
          'dacia': ['sandero'],
          'lancia': ['ypsilon'],
        },
        VehicleKind.van: {
          'fiat': ['ducato', 'doblo'],
        },
        VehicleKind.motorcycle: {
          'honda': ['sh125'],
          'piaggio': ['vespa', 'liberty'],
          'yamaha': ['mt-07'],
          'ducati': ['monster'],
        },
        VehicleKind.moped: {
          'piaggio': ['liberty'],
        },
      };
      for (final MapEntry(key: kind, value: makes) in spotCheck.entries) {
        for (final MapEntry(key: make, value: models) in makes.entries) {
          final slugs = {
            for (final model in asset.models(kind, make)) model.slug,
          };
          for (final model in models) {
            expect(slugs, contains(model), reason: '$kind $make $model');
          }
        }
      }
    });
  });
}
