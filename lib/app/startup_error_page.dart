import 'package:flutter/material.dart';

import '../data/db/upgrade_safety.dart';
import '../l10n/app_localizations.dart';

/// Full-screen error shown instead of the app when the database cannot be
/// opened at startup.
///
/// It explains, in the user's language, that their data was not touched,
/// rather than letting the app crash. Nothing here retries or "repairs" the
/// file: a refused or failed upgrade must be left exactly as it is.
class StartupErrorPage extends StatelessWidget {
  /// Creates the page for the [error] that stopped the database opening.
  const StartupErrorPage({super.key, required this.error});

  /// The error thrown while opening the database.
  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // A file newer than the app is refused before anything is written. Any
    // other failure (a failed upgrade is rolled back, its pre-upgrade copy
    // kept) gets the general message.
    final message = error is DatabaseNewerThanAppException
        ? l10n.startupErrorNewerDatabase
        : l10n.startupErrorUpgradeFailed;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 56,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.startupErrorTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.startupErrorDetail('$error'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
