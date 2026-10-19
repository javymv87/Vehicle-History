import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/entries/pages/log_entry_detail_page.dart';
import '../../features/entries/pages/log_entry_form_page.dart';
import '../../features/mileage/pages/mileage_reading_form_page.dart';
import '../../features/owners/pages/owner_detail_page.dart';
import '../../features/owners/pages/owner_form_page.dart';
import '../../features/owners/pages/owner_list_page.dart';
import '../../features/trash/pages/trash_page.dart';
import '../../features/vehicles/controllers/vehicle_tab_controller.dart';
import '../../features/vehicles/pages/vehicle_detail_page.dart';
import '../../features/vehicles/pages/vehicle_form_page.dart';
import '../../features/vehicles/pages/vehicle_list_page.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/not_found_page.dart';
import 'app_routes.dart';
import 'home_shell.dart';

/// The app's single [GoRouter], created once per [ProviderScope].
final routerProvider = Provider<GoRouter>((ref) {
  final router = buildAppRouter();
  ref.onDispose(router.dispose);
  return router;
});

/// Builds the route table of the app, starting at [initialLocation].
///
/// The two lists live in a [StatefulShellRoute] under the navigation bar;
/// details and forms are top-level routes, so they are pushed full screen on
/// top of it. `/vehicles/new`, `/owners/new` and `entries/new` are declared
/// before the matching `:id` routes so that "new" is never read as an id.
/// The history entries and the odometer readings live under their vehicle
/// (`/vehicles/:id/entries/...`, `/vehicles/:id/mileage/...`), so pushing
/// one keeps the vehicle page below it. The vehicle page reads its tab from
/// the `tab` query parameter.
GoRouter buildAppRouter({String initialLocation = AppRoutes.vehicles}) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) =>
        state.uri.path == '/' ? AppRoutes.vehicles : null,
    errorBuilder: (context, state) =>
        NotFoundPage(message: AppLocalizations.of(context).pageNotFound),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.vehicles,
                builder: (context, state) => const VehicleListPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.owners,
                builder: (context, state) => const OwnerListPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.newVehicle,
        builder: (context, state) => const VehicleFormPage(),
      ),
      GoRoute(
        path: '${AppRoutes.vehicles}/:id',
        builder: (context, state) => VehicleDetailPage(
          vehicleId: state.pathParameters['id']!,
          initialTab: VehicleTab.fromQuery(state.uri.queryParameters['tab']),
        ),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                VehicleFormPage(vehicleId: state.pathParameters['id']),
          ),
          GoRoute(
            path: 'mileage/new',
            builder: (context, state) => MileageReadingFormPage(
              vehicleId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: 'mileage/:readingId/edit',
            builder: (context, state) => MileageReadingFormPage(
              vehicleId: state.pathParameters['id']!,
              readingId: state.pathParameters['readingId'],
            ),
          ),
          GoRoute(
            path: 'entries/new',
            builder: (context, state) =>
                LogEntryFormPage(vehicleId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'entries/:entryId',
            builder: (context, state) => LogEntryDetailPage(
              vehicleId: state.pathParameters['id']!,
              entryId: state.pathParameters['entryId']!,
            ),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => LogEntryFormPage(
                  vehicleId: state.pathParameters['id']!,
                  entryId: state.pathParameters['entryId'],
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.trash,
        builder: (context, state) => const TrashPage(),
      ),
      GoRoute(
        path: AppRoutes.newOwner,
        builder: (context, state) => const OwnerFormPage(),
      ),
      GoRoute(
        path: '${AppRoutes.owners}/:id',
        builder: (context, state) =>
            OwnerDetailPage(ownerId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                OwnerFormPage(ownerId: state.pathParameters['id']),
          ),
        ],
      ),
    ],
  );
}
