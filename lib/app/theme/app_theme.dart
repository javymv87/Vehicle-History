import 'package:flutter/material.dart';

import 'status_colors.dart';

/// Builds the Material 3 themes of the app.
///
/// Both palettes are generated from a single [seedColor], as decided in
/// `Docs/07_design_and_theming.md`: changing the seed restyles the whole app.
abstract final class AppTheme {
  /// The single seed colour the light and dark palettes are generated from.
  ///
  /// Deep blue, chosen to fit the "vehicles / workshop" context without
  /// being intrusive.
  static const Color seedColor = Color(0xFF1F4E8C);

  /// The light theme.
  static final ThemeData light = _build(Brightness.light, StatusColors.light);

  /// The dark theme.
  static final ThemeData dark = _build(Brightness.dark, StatusColors.dark);

  /// Creates a Material 3 theme for [brightness] from [seedColor], carrying
  /// the matching [statusColors] as a theme extension.
  static ThemeData _build(Brightness brightness, StatusColors statusColors) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ),
      extensions: <ThemeExtension<dynamic>>[statusColors],
    );
  }
}
