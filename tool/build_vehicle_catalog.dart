// Builds the bundled vehicle make / model catalogue from a pinned VehiclesDB
// release.
//
// Usage (from the repository root):
//
//   fvm dart run tool/build_vehicle_catalog.dart [release-tag]
//
// Downloads `vehicles.json`, `ATTRIBUTION.md` and the `LICENSE` of that
// release and writes, under `assets/catalog/`:
//
// - `vehicle_catalog.json`: per kind (car, van, motorcycle, moped), the makes
//   with their models, each with `slug` and `name`, plus the popularity data
//   the app sorts by;
// - `ATTRIBUTION.md` and `LICENSE.md`: the upstream credit and licence
//   notices, required by CC BY 4.0.
//
// The output is committed, so builds are offline and reproducible. To
// refresh the catalogue, run the script with a newer tag that is at least
// two weeks old and update [defaultRelease] (see CLAUDE.md).
import 'dart:convert';
import 'dart:io';

/// The VehiclesDB release the committed asset was built from.
const String defaultRelease = 'v2026.09.1';

/// Vehicle kinds the app manages, as VehiclesDB codes. Trucks and buses are
/// deliberately left out.
const List<String> kinds = ['car', 'van', 'motorcycle', 'moped'];

/// Folder the asset and its notices are written to.
const String outputDir = 'assets/catalog';

Future<void> main(List<String> args) async {
  final release = args.isEmpty ? defaultRelease : args.single;
  final base =
      'https://github.com/vehiclesdb/vehiclesdb/releases/download/$release';
  final raw =
      'https://raw.githubusercontent.com/vehiclesdb/vehiclesdb/$release';

  final client = HttpClient();
  try {
    final vehicles = await _download(client, '$base/vehicles.json');
    final attribution = await _download(client, '$base/ATTRIBUTION.md');
    final license = await _download(client, '$raw/LICENSE');

    final source = jsonDecode(vehicles) as Map<String, dynamic>;
    if (source['version'] != release.replaceFirst('v', '')) {
      final version = source['version'];
      throw StateError('Release $release contains version $version');
    }

    Directory(outputDir).createSync(recursive: true);
    final catalog = _project(source, release);
    File('$outputDir/vehicle_catalog.json').writeAsStringSync(catalog);
    File('$outputDir/ATTRIBUTION.md').writeAsStringSync(attribution);
    File('$outputDir/LICENSE.md').writeAsStringSync(license);

    stdout.writeln(
      'Wrote $outputDir/vehicle_catalog.json from VehiclesDB $release '
      '(${catalog.length} bytes).',
    );
  } finally {
    client.close();
  }
}

/// Downloads [url] as UTF-8 text, failing on any non-200 answer.
Future<String> _download(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
  }
  return response.transform(utf8.decoder).join();
}

/// Projects the upstream `vehicles.json` into the compact app asset.
///
/// Shape:
///
/// ```json
/// {"source": "VehiclesDB", "release": "v2026.09.1", "license": "CC-BY-4.0",
///  "kinds": {"car": [
///    {"slug": "fiat", "name": "Fiat", "popularity": 812,
///     "models": [["punto", "Punto", 2], ["multipla", "Multipla"]]}]}}
/// ```
///
/// A model is `[slug, name]` or `[slug, name, globalDecile]` (1 = most
/// popular tenth, absent when VehiclesDB has no count). A make's
/// `popularity` is the sum over its models of `(11 - decile)²`, so a make
/// with several very popular models ranks above one with a single hit; it is
/// absent when no model is ranked. The app does the sorting, so it is unit
/// tested there.
///
/// Every make is written on its own line, so refreshing the catalogue gives
/// a readable diff.
String _project(Map<String, dynamic> source, String release) {
  final byKind = <String, List<String>>{for (final k in kinds) k: []};
  for (final make in (source['makes'] as List).cast<Map<String, dynamic>>()) {
    for (final kind in kinds) {
      final models = [
        for (final model
            in (make['models'] as List).cast<Map<String, dynamic>>())
          if (model['kind'] == kind)
            [
              model['slug'] as String,
              model['name'] as String,
              if (model['global_decile'] case final int decile) decile,
            ],
      ];
      if (models.isEmpty) continue;
      var popularity = 0;
      for (final model in models) {
        if (model.length > 2) {
          final weight = 11 - (model[2] as int);
          popularity += weight * weight;
        }
      }
      byKind[kind]!.add(
        jsonEncode({
          'slug': make['slug'],
          'name': make['name'],
          if (popularity > 0) 'popularity': popularity,
          'models': models,
        }),
      );
    }
  }

  final buffer = StringBuffer()
    ..write('{"source":"VehiclesDB","release":${jsonEncode(release)},')
    ..write('"license":"CC-BY-4.0","kinds":{');
  for (final (index, kind) in kinds.indexed) {
    if (index > 0) buffer.write(',');
    buffer
      ..write('\n${jsonEncode(kind)}:[\n')
      ..write(byKind[kind]!.join(',\n'))
      ..write('\n]');
  }
  buffer.write('\n}}\n');
  return buffer.toString();
}
