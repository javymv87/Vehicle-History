import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/data_providers.dart';
import '../l10n/app_localizations.dart';
import 'locale_resolution.dart';
import 'router/app_router.dart';
import 'startup_error_page.dart';
import 'theme/app_theme.dart';

/// Root widget of the Vehicle History application.
///
/// Wires the Material 3 light and dark themes, the IT / ES / EN localisation
/// and the router into a single [MaterialApp]. Until the database is open
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
    return MaterialApp.router(
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
