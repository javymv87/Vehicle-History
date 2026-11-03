import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/backup/controllers/drive_controller.dart';
import '../../features/backup/widgets/drive_banner.dart';
import '../../features/reminders/controllers/reminder_list_controller.dart';
import '../../l10n/app_localizations.dart';
import 'app_routes.dart';

/// The home frame: the navigation bar with Vehicles, Reminders and Owners,
/// the "add" button of the list currently shown, and on top the Drive
/// banner when another phone uploaded a newer copy ([DriveBanner]).
///
/// The add button lives here rather than in each list, so the "Undo"
/// snackbar, which is shown on this scaffold, pushes it up instead of
/// covering it. The Reminders list has none: a reminder belongs to a
/// vehicle and is created from its page. The Reminders destination shows a
/// badge with the overdue and due-soon reminders of the active vehicles.
class HomeShell extends ConsumerWidget {
  /// Wraps the [navigationShell] of the three list branches.
  const HomeShell({super.key, required this.navigationShell});

  /// Index of the vehicles branch.
  static const int vehiclesBranch = 0;

  /// Index of the reminders branch.
  static const int remindersBranch = 1;

  /// Index of the owners branch.
  static const int ownersBranch = 2;

  /// The branch navigator built by `StatefulShellRoute`.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final badge = ref.watch(reminderBadgeCountProvider);
    final (String path, String label)? add =
        switch (navigationShell.currentIndex) {
      vehiclesBranch => (AppRoutes.newVehicle, l10n.addVehicle),
      ownersBranch => (AppRoutes.newOwner, l10n.addOwner),
      _ => null,
    };
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
      floatingActionButton: add == null
          ? null
          : FloatingActionButton.extended(
              // A distinct hero tag per branch, so switching tabs never
              // animates one button into the other.
              heroTag: add.$1,
              onPressed: () => context.push(add.$1),
              icon: const Icon(Icons.add),
              label: Text(add.$2),
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
            // No badge at 0.
            icon: Badge.count(
              count: badge,
              isLabelVisible: badge > 0,
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge.count(
              count: badge,
              isLabelVisible: badge > 0,
              child: const Icon(Icons.notifications),
            ),
            label: l10n.remindersTitle,
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
