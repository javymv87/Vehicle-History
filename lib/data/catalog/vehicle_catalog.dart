import 'dart:convert';

import '../models/vehicle_kind.dart';
import 'search_text.dart';

/// A model of the bundled catalogue, such as Fiat Punto.
class CatalogModel {
  /// Creates a catalogue model.
  const CatalogModel({required this.slug, required this.name, this.decile});

  /// Stable VehiclesDB id within its make, e.g. `punto`.
  final String slug;

  /// Name shown to the user, e.g. "Punto".
  final String name;

  /// VehiclesDB global popularity decile: 1 is the most popular tenth of
  /// models of its kind, 10 the least. `null` when VehiclesDB has no count.
  final int? decile;

  @override
  String toString() => 'CatalogModel($slug)';
}

/// A make of the bundled catalogue, with its models of one vehicle kind.
class CatalogMake {
  /// Creates a catalogue make.
  const CatalogMake({
    required this.slug,
    required this.name,
    this.popularity = 0,
    required this.models,
  });

  /// Stable VehiclesDB id, e.g. `fiat`.
  final String slug;

  /// Name shown to the user, e.g. "Fiat".
  final String name;

  /// Popularity score computed when the asset is built (higher is more
  /// popular, 0 when none of its models is ranked). Only compared with other
  /// makes of the same kind.
  final int popularity;

  /// The make's models of this kind, most popular first, then alphabetical.
  final List<CatalogModel> models;

  @override
  String toString() => 'CatalogMake($slug)';
}

/// The bundled make / model catalogue (VehiclesDB, CC BY 4.0), per vehicle
/// kind, with case- and accent-insensitive search.
///
/// Pure Dart: it is built from the asset's JSON text, so tests can feed it a
/// small fixture. The app never goes online for it.
class VehicleCatalog {
  /// Creates the catalogue from unordered [makesByKind]; the lists are put in
  /// display order here.
  VehicleCatalog({
    required this.release,
    required Map<VehicleKind, List<CatalogMake>> makesByKind,
  }) : _makes = {
          for (final kind in VehicleKind.values)
            kind: _inDisplayOrder(makesByKind[kind] ?? const []),
        };

  /// Parses the asset written by `tool/build_vehicle_catalog.dart`.
  factory VehicleCatalog.fromJson(String json) {
    final root = jsonDecode(json) as Map<String, dynamic>;
    final kinds = root['kinds'] as Map<String, dynamic>;
    return VehicleCatalog(
      release: root['release'] as String,
      makesByKind: {
        for (final kind in VehicleKind.values)
          kind: [
            for (final make in (kinds[_kindCode(kind)] as List? ?? const [])
                .cast<Map<String, dynamic>>())
              CatalogMake(
                slug: make['slug'] as String,
                name: make['name'] as String,
                popularity: make['popularity'] as int? ?? 0,
                models: [
                  for (final model in (make['models'] as List).cast<List>())
                    CatalogModel(
                      slug: model[0] as String,
                      name: model[1] as String,
                      decile: model.length > 2 ? model[2] as int : null,
                    ),
                ],
              ),
          ],
      },
    );
  }

  /// How many of the most popular makes are listed first; the others
  /// follow in alphabetical order.
  static const int featuredMakeCount = 20;

  /// The VehiclesDB release the asset was built from, e.g. `v2026.09.1`.
  final String release;

  /// Makes per kind, in display order.
  final Map<VehicleKind, List<CatalogMake>> _makes;

  /// The makes of [kind] in display order: the [featuredMakeCount] most
  /// popular first, then the rest alphabetically.
  List<CatalogMake> makes(VehicleKind kind) => _makes[kind]!;

  /// How many makes at the start of [makes] are listed because of their
  /// popularity; the ones after them are in alphabetical order.
  int featuredCount(VehicleKind kind) => _makes[kind]!
      .take(featuredMakeCount)
      .takeWhile((make) => make.popularity > 0)
      .length;

  /// The make of [kind] with [slug], or `null` when the catalogue has none.
  CatalogMake? make(VehicleKind kind, String slug) {
    for (final make in _makes[kind]!) {
      if (make.slug == slug) return make;
    }
    return null;
  }

  /// The makes of [kind] whose name contains [query], in display order.
  List<CatalogMake> searchMakes(VehicleKind kind, String query) =>
      searchByName(_makes[kind]!, (m) => m.name, query);

  /// The models of the make with [makeSlug] of [kind], in display order;
  /// empty when the make is not in the catalogue.
  List<CatalogModel> models(VehicleKind kind, String makeSlug) =>
      make(kind, makeSlug)?.models ?? const [];

  /// The models of the make with [makeSlug] whose name contains [query].
  List<CatalogModel> searchModels(
    VehicleKind kind,
    String makeSlug,
    String query,
  ) =>
      searchByName(models(kind, makeSlug), (m) => m.name, query);

  /// VehiclesDB code of [kind] (the same as the database code).
  static String _kindCode(VehicleKind kind) => switch (kind) {
        VehicleKind.car => 'car',
        VehicleKind.van => 'van',
        VehicleKind.motorcycle => 'motorcycle',
        VehicleKind.moped => 'moped',
      };

  /// Orders [makes] for display, and the models of each make.
  static List<CatalogMake> _inDisplayOrder(List<CatalogMake> makes) {
    int byName(String a, String b) =>
        foldForSearch(a).compareTo(foldForSearch(b));

    final byPopularity = [
      for (final make in makes)
        if (make.popularity > 0) make,
    ]..sort((a, b) {
        final order = b.popularity.compareTo(a.popularity);
        return order != 0 ? order : byName(a.name, b.name);
      });
    final featured = byPopularity.take(featuredMakeCount).toList();
    final featuredSlugs = {for (final make in featured) make.slug};
    final rest = [
      for (final make in makes)
        if (!featuredSlugs.contains(make.slug)) make,
    ]..sort((a, b) => byName(a.name, b.name));

    return List.unmodifiable([
      for (final make in [...featured, ...rest])
        CatalogMake(
          slug: make.slug,
          name: make.name,
          popularity: make.popularity,
          models: List.unmodifiable(
            List.of(make.models)
              ..sort((a, b) {
                // Ranked models first, the most popular decile first.
                final order = (a.decile ?? 11).compareTo(b.decile ?? 11);
                return order != 0 ? order : byName(a.name, b.name);
              }),
          ),
        ),
    ]);
  }
}
