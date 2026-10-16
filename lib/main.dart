import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/data_licenses.dart';

/// Application entry point.
///
/// Registers the licences of the bundled data, then mounts the root
/// [VehicleHistoryApp] inside the single [ProviderScope] of the app.
void main() {
  registerDataLicenses();
  runApp(const ProviderScope(child: VehicleHistoryApp()));
}
