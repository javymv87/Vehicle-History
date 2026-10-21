import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/app_preferences.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../shared/utils/action_result.dart';

/// The interface language stored in Settings.
///
/// Read only once the database is open: until then (app start) it has no
/// value and the app shows the device language, so no wrong language flashes
/// after the splash. While the database is being reopened after an import it
/// keeps its previous value, then follows the imported `settings` row: this
/// provider depends on [appDatabaseProvider] through the repository and
/// [databaseReadyProvider], so it rebuilds on the new connection.
///
/// A failed read is logged and leaves it without a value, which the app
/// treats as [AppLanguage.system].
final languageSettingProvider = StreamProvider<AppLanguage>((ref) {
  if (ref.watch(databaseReadyProvider) is! AsyncData) {
    return const Stream.empty();
  }
  return ref
      .watch(settingsRepositoryProvider)
      .watchLanguage()
      .handleError(_logReadFailure);
});

/// The light / dark mode stored in Settings, read like
/// [languageSettingProvider] and with the same fallback to
/// [AppThemeMode.system].
final themeSettingProvider = StreamProvider<AppThemeMode>((ref) {
  if (ref.watch(databaseReadyProvider) is! AsyncData) {
    return const Stream.empty();
  }
  return ref
      .watch(settingsRepositoryProvider)
      .watchThemeMode()
      .handleError(_logReadFailure);
});

/// The `MaterialApp.locale`: `null` (the device language) for
/// [AppLanguage.system] and until the setting is read.
final appLocaleProvider = Provider<Locale?>((ref) {
  final code = ref.watch(languageSettingProvider).value?.languageCode;
  return code == null ? null : Locale(code);
});

/// The `MaterialApp.themeMode`: [ThemeMode.system] for
/// [AppThemeMode.system] and until the setting is read.
final appThemeModeProvider = Provider<ThemeMode>(
  (ref) => switch (ref.watch(themeSettingProvider).value) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system || null => ThemeMode.system,
  },
);

/// Reports a settings read that failed; the setting then counts as
/// `system`.
void _logReadFailure(Object error, StackTrace stackTrace) =>
    debugPrint('Reading a setting failed, using system: $error\n$stackTrace');

/// The actions of the Settings page (U21): store the language and the
/// light / dark mode. The app follows the new value at once through the
/// providers above, which watch the stored rows.
class SettingsController extends Notifier<void> {
  @override
  void build() {}

  /// Stores [language] as the interface language.
  Future<ActionResult<void>> setLanguage(AppLanguage language) => runAction(
        () => ref.read(settingsRepositoryProvider).writeLanguage(language),
      );

  /// Stores [mode] as the light / dark mode.
  Future<ActionResult<void>> setThemeMode(AppThemeMode mode) => runAction(
        () => ref.read(settingsRepositoryProvider).writeThemeMode(mode),
      );
}

/// The [SettingsController] of the Settings page. Kept alive: the page
/// reads it before opening a dialog and uses it after the dialog closes,
/// with nothing watching it in between.
final settingsControllerProvider =
    NotifierProvider<SettingsController, void>(SettingsController.new);
