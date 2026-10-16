// Builds the bundled country-name table from a pinned Unicode CLDR release.
//
// Usage (from the repository root):
//
//   fvm dart run tool/build_country_names.dart [cldr-json-tag]
//
// Downloads the territory names in English, Spanish and Italian plus the
// ISO code mappings from `unicode-org/cldr-json`, and writes, under
// `assets/countries/`:
//
// - `country_names.json`: every ISO 3166-1 alpha-2 code with its name in
//   each app language;
// - `LICENSE.md`: the Unicode License v3 notice the data is used under.
//
// The output is committed, so builds are offline and reproducible.
import 'dart:convert';
import 'dart:io';

/// The CLDR release the committed asset was built from.
const String defaultRelease = '48.2.3';

/// App languages, as CLDR locale ids.
const List<String> languages = ['en', 'es', 'it'];

/// Folder the asset and its notice are written to.
const String outputDir = 'assets/countries';

Future<void> main(List<String> args) async {
  final release = args.isEmpty ? defaultRelease : args.single;
  final base =
      'https://raw.githubusercontent.com/unicode-org/cldr-json/$release';

  final client = HttpClient();
  try {
    final mappings = jsonDecode(
      await _download(
        client,
        '$base/cldr-json/cldr-core/supplemental/codeMappings.json',
      ),
    ) as Map<String, dynamic>;
    final territories = {
      for (final language in languages)
        language: await _territories(client, base, language),
    };
    // Withdrawn codes (AN, CS, YU, …) keep their mapping but have no
    // display name any more: only current territories are kept.
    final codes = _isoAlpha2Codes(
      (mappings['supplemental'] as Map)['codeMappings'] as Map<String, dynamic>,
    ).where(territories['en']!.containsKey).toList();

    final names = <String, Map<String, String>>{};
    for (final language in languages) {
      names[language] = {
        for (final code in codes)
          code: territories[language]![code] as String? ??
              (throw StateError('No $language name for $code')),
      };
    }
    final license = await _download(client, '$base/LICENSE');

    Directory(outputDir).createSync(recursive: true);
    const encoder = JsonEncoder.withIndent(' ');
    final output = {
      'source': 'Unicode CLDR',
      'release': release,
      'names': names,
    };
    File('$outputDir/country_names.json').writeAsStringSync(
      '${encoder.convert(output)}\n',
    );
    File('$outputDir/LICENSE.md').writeAsStringSync(license);
    stdout.writeln(
      'Wrote ${codes.length} countries to $outputDir/country_names.json '
      'from CLDR $release.',
    );
  } finally {
    client.close();
  }
}

/// The ISO 3166-1 alpha-2 codes among CLDR's code mappings, sorted.
///
/// ISO 3166-1 entries are the two-letter codes that also have an ISO numeric
/// and alpha-3 code; the user-assigned ranges (AA, QM–QZ, XA–XZ, ZZ) and the
/// exceptionally reserved unions (EU, EZ, UN) are left out.
List<String> _isoAlpha2Codes(Map<String, dynamic> mappings) {
  bool userAssigned(String code) =>
      code == 'AA' ||
      code == 'ZZ' ||
      const {'EU', 'EZ', 'UN'}.contains(code) ||
      (code.startsWith('Q') && code.compareTo('QM') >= 0) ||
      code.startsWith('X');
  return [
    for (final MapEntry(:key, :value) in mappings.entries)
      if (RegExp(r'^[A-Z]{2}$').hasMatch(key) &&
          (value as Map).containsKey('_numeric') &&
          value.containsKey('_alpha3') &&
          !userAssigned(key))
        key,
  ]..sort();
}

/// The CLDR territory display names in [language], by code.
Future<Map<String, dynamic>> _territories(
  HttpClient client,
  String base,
  String language,
) async {
  final json = jsonDecode(
    await _download(
      client,
      '$base/cldr-json/cldr-localenames-full/main/$language/territories.json',
    ),
  ) as Map<String, dynamic>;
  return (((json['main'] as Map)[language] as Map)['localeDisplayNames']
      as Map)['territories'] as Map<String, dynamic>;
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
