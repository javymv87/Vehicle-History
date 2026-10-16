import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licences of the bundled reference data to Flutter's licence
/// registry, so they appear on the licence page opened from "About".
///
/// - The make / model catalogue comes from VehiclesDB under CC BY 4.0, which
///   requires visible credit; its `ATTRIBUTION.md` also carries the notices
///   of the official registers it is built from.
/// - The country names come from Unicode CLDR under the Unicode License v3.
///
/// The texts are read from the bundled assets only when the licence page
/// asks for them.
void registerDataLicenses() {
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/catalog/LICENSE.md');
    final attribution =
        await rootBundle.loadString('assets/catalog/ATTRIBUTION.md');
    yield LicenseEntryWithLineBreaks(
      const ['VehiclesDB'],
      '$license\n\n$attribution',
    );
    yield LicenseEntryWithLineBreaks(
      const ['Unicode CLDR'],
      await rootBundle.loadString('assets/countries/LICENSE.md'),
    );
  });
}
