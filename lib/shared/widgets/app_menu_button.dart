import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../l10n/app_localizations.dart';

/// The overflow menu of the home lists' app bars: "Trash" (vehicle list
/// only, with the number of vehicles in it) and "About", which shows the
/// credits and the licences of the bundled data.
class AppMenuButton extends StatelessWidget {
  /// Creates the menu button. A non-null [trashCount] adds the "Trash"
  /// entry.
  const AppMenuButton({super.key, this.trashCount});

  /// Number of vehicles in the Trash, shown when above 0 (U17); `null`
  /// leaves the entry out.
  final int? trashCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final trashCount = this.trashCount;
    return PopupMenuButton<VoidCallback>(
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        if (trashCount != null)
          PopupMenuItem(
            value: () => context.push(AppRoutes.trash),
            child: Text(l10n.trashMenuItem(trashCount)),
          ),
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
