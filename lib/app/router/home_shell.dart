import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/backup/controllers/drive_controller.dart';
import '../../features/backup/widgets/drive_banner.dart';
import '../../l10n/app_localizations.dart';
import 'app_routes.dart';

/// The home frame: the navigation bar with Vehicles and Owners, the "add"
/// button of the list currently shown, and on top the Drive banner when
/// another phone uploaded a newer copy ([DriveBanner]).
///
/// The add button lives here rather than in each list, so the "Undo"
/// snackbar, which is shown on this scaffold, pushes it up instead of
/// covering it.
class HomeShell extends StatelessWidget {
  /// Wraps the [navigationShell] of the two list branches.
  const HomeShell({super.key, required this.navigationShell});

  /// Index of the vehicles branch.
  static const int vehiclesBranch = 0;

  /// The branch navigator built by `StatefulShellRoute`.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onVehicles = navigationShell.currentIndex == vehiclesBranch;
    return Scaffold(
      body: Column(
        children: [
          const DriveBanner(),
          // The banner takes the status bar area when shown; the list's own
          // app bar then needs no top padding.
          Expanded(
            child: Consumer(
              builder: (context, ref, child) => MediaQuery.removePadding(
                context: context,
                removeTop: driveShowsBanner(ref.watch(driveControllerProvider)),
                child: child!,
              ),
              child: navigationShell,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // A distinct hero tag per branch, so switching tabs never animates
        // one button into the other.
        heroTag: onVehicles ? AppRoutes.newVehicle : AppRoutes.newOwner,
        onPressed: () => context.push(
          onVehicles ? AppRoutes.newVehicle : AppRoutes.newOwner,
        ),
        icon: const Icon(Icons.add),
        label: Text(onVehicles ? l10n.addVehicle : l10n.addOwner),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        // Tapping the current tab again returns to its first page.
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.directions_car_outlined),
            selectedIcon: const Icon(Icons.directions_car),
            label: l10n.vehiclesTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people),
            label: l10n.ownersTitle,
          ),
        ],
      ),
    );
  }
}
