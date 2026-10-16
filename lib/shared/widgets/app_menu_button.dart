import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The overflow menu of the home lists' app bars. Today it holds only
/// "About", which shows the credits and the licences of the bundled data.
class AppMenuButton extends StatelessWidget {
  /// Creates the menu button.
  const AppMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<VoidCallback>(
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: () => showAppAboutDialog(context),
          child: Text(l10n.aboutAction),
        ),
      ],
    );
  }
}

/// Shows the About dialog with the data credits. Its "View licences" button
/// opens Flutter's licence page, which lists the notices registered by
/// `registerDataLicenses`.
void showAppAboutDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  showAboutDialog(
    context: context,
    applicationName: l10n.appTitle,
    applicationIcon: const Icon(Icons.directions_car, size: 48),
    children: [
      const SizedBox(height: 16),
      Text(l10n.aboutVehicleData),
      const SizedBox(height: 8),
      Text(l10n.aboutCountryData),
    ],
  );
}
