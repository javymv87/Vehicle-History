import 'package:flutter/material.dart';

/// Application entry point.
///
/// Boots the Flutter engine and mounts the root [VehicleHistoryApp] widget.
void main() {
  runApp(const VehicleHistoryApp());
}

/// Root widget of the Vehicle History application.
///
/// This is an intentionally minimal scaffold whose only job, at this stage, is
/// to make the project compile and run. It wires up a single [MaterialApp] with
/// one empty screen.
///
/// Theming (a single-seed Material 3 palette), navigation/routing and
/// localisation (IT / ES / EN) are added in later, dedicated steps. No
/// user-facing strings are declared here on purpose: every visible string will
/// be externalised through `gen_l10n`, so none is hard-coded in the widget
/// tree.
class VehicleHistoryApp extends StatelessWidget {
  /// Creates the root application widget.
  const VehicleHistoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      // A single blank screen. Real routing, theme and localisation are added
      // in subsequent steps; for now this only proves the scaffold compiles.
      home: Scaffold(
        body: SizedBox.expand(),
      ),
    );
  }
}
