import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/app_preferences.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/feedback.dart';
import '../controllers/settings_controller.dart';
import '../widgets/choice_dialog.dart';

/// The Settings page (U21): the interface language and the light / dark
/// mode, each a tile with the current value that opens a radio-button
/// dialog. Opened from the overflow menu of the home lists.
///
/// A choice is stored at once and the whole app follows it, this page
/// included, without a restart.
class SettingsPage extends ConsumerWidget {
  /// Creates the Settings page.
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Not read yet, or unreadable: both count as "System".
    final language =
        ref.watch(languageSettingProvider).value ?? AppLanguage.system;
    final themeMode =
        ref.watch(themeSettingProvider).value ?? AppThemeMode.system;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l10n.settingsLanguage),
            subtitle: Text(language.label(l10n)),
            onTap: () => _chooseLanguage(context, ref, language),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(l10n.settingsTheme),
            subtitle: Text(themeMode.label(l10n)),
            onTap: () => _chooseThemeMode(context, ref, themeMode),
          ),
        ],
      ),
    );
  }

  /// Lets the user pick the interface language and stores it.
  Future<void> _chooseLanguage(
    BuildContext context,
    WidgetRef ref,
    AppLanguage current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(settingsControllerProvider.notifier);
    final chosen = await showChoiceDialog(
      context: context,
      title: l10n.settingsLanguage,
      options: AppLanguage.values,
      selected: current,
      labelOf: (language) => language.label(l10n),
    );
    if (chosen == null || chosen == current) return;
    _reportFailure(messenger, l10n, await controller.setLanguage(chosen));
  }

  /// Lets the user pick the light / dark mode and stores it.
  Future<void> _chooseThemeMode(
    BuildContext context,
    WidgetRef ref,
    AppThemeMode current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(settingsControllerProvider.notifier);
    final chosen = await showChoiceDialog(
      context: context,
      title: l10n.settingsTheme,
      options: AppThemeMode.values,
      selected: current,
      labelOf: (mode) => mode.label(l10n),
    );
    if (chosen == null || chosen == current) return;
    _reportFailure(messenger, l10n, await controller.setThemeMode(chosen));
  }

  /// Shows the error of a failed write. A successful one needs no message:
  /// the change itself is visible at once.
  void _reportFailure(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
    ActionResult<void> result,
  ) {
    if (result case ActionFailure(:final error)) {
      showErrorSnackBar(messenger, error.message(l10n));
    }
  }
}
