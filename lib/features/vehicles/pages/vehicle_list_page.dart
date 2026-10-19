import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_menu_button.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../trash/controllers/trash_controller.dart';
import '../controllers/vehicle_list_controller.dart';
import '../widgets/vehicle_tile.dart';

/// The vehicle list: the home screen and first destination of the
/// navigation bar. Vehicles are ordered by plate.
///
/// The "add" button is the home shell's FAB, also when the list is empty:
/// the empty state shows only a message, never a second add button.
class VehicleListPage extends ConsumerWidget {
  /// Creates the vehicle list page.
  const VehicleListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.vehiclesTitle),
        actions: [AppMenuButton(trashCount: ref.watch(trashCountProvider))],
      ),
      body: AsyncValueView(
        value: ref.watch(vehicleListProvider),
        data: (items) => items.isEmpty
            ? MessageView(
                icon: Icons.directions_car_outlined,
                message: l10n.vehicleListEmpty,
              )
            : ListView.builder(
                // Room at the bottom so the last row clears the add button.
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return VehicleTile(
                    item: item,
                    onTap: () =>
                        context.push(AppRoutes.vehicle(item.vehicle.id)),
                  );
                },
              ),
      ),
    );
  }
}
