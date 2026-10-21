import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/data_providers.dart';
import '../features/settings/controllers/settings_controller.dart';
import '../l10n/app_localizations.dart';
import 'locale_resolution.dart';
import 'router/app_router.dart';
import 'startup_error_page.dart';
import 'theme/app_theme.dart';

/// Root widget of the Vehicle History application.
///
/// Wires the Material 3 light and dark themes, the IT / ES / EN localisation
/// and the router into a single [MaterialApp]. The language and the light /
/// dark mode chosen in Settings apply at once; until the database is open
/// they follow the device. Until the database is open
/// (and any migration has run) it shows a progress indicator; if opening
/// fails, it shows [StartupErrorPage] instead of any screen that would read
/// data.
class VehicleHistoryApp extends ConsumerWidget {
  /// Creates the root application widget.
  const VehicleHistoryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final databaseReady = ref.watch(databaseReadyProvider);
    final locale = ref.watch(appLocaleProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // The language chosen in Settings; `null` follows the device.
      locale: locale,
      // Match by language code and fall back to English for any other
      // device language.
      localeListResolutionCallback: resolveAppLocale,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      // The builder sits below the localisations and the theme, so the
      // startup states are localised and themed like any other page.
      builder: (context, child) => switch (databaseReady) {
        AsyncData() => child ?? const SizedBox.shrink(),
        AsyncError(:final error) => StartupErrorPage(error: error),
        _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
      },
    );
  }
}
