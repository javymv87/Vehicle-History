import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

/// Application entry point.
///
/// Mounts the root [VehicleHistoryApp] inside the single [ProviderScope] of
/// the app.
void main() {
  runApp(const ProviderScope(child: VehicleHistoryApp()));
}
