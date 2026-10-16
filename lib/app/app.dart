import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'locale_resolution.dart';
import 'placeholder_home_page.dart';
import 'theme/app_theme.dart';

/// Root widget of the Vehicle History application.
///
/// Wires the Material 3 light and dark themes and the IT / ES / EN
/// localisation into a single [MaterialApp]. Routing (`go_router`) and state
/// management (Riverpod) are introduced in a later step.
class VehicleHistoryApp extends StatelessWidget {
  /// Creates the root application widget.
  const VehicleHistoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Match by language code and fall back to English for any other
      // device language.
      localeListResolutionCallback: resolveAppLocale,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Follows the OS for now. The user override (System / Light / Dark)
      // belongs to the Settings feature and needs persisted settings, which
      // do not exist yet.
      themeMode: ThemeMode.system,
      home: const PlaceholderHomePage(),
    );
  }
}
