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
/// navigation bar. Active vehicles, ordered by plate; when at least one
/// vehicle is archived, a single discreet "Archived (n)" row at the bottom
/// opens the archived list (`Docs/03_features.md`, "Archivo").
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
        data: (items) {
          final archivedCount =
              ref.watch(archivedVehiclesProvider).value?.length ?? 0;
          if (items.isEmpty && archivedCount == 0) {
            return MessageView(
              icon: Icons.directions_car_outlined,
              message: l10n.vehicleListEmpty,
            );
          }
          return ListView(
            // Room at the bottom so the last row clears the add button.
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.vehicleListEmpty,
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final item in items)
                VehicleTile(
                  item: item,
                  onTap: () => context.push(AppRoutes.vehicle(item.vehicle.id)),
                ),
              if (archivedCount > 0)
                _ArchivedRow(count: archivedCount, items: items.isNotEmpty),
            ],
          );
        },
      ),
    );
  }
}

/// The row at the bottom of the list that opens the archived vehicles,
/// the way a chat app shows "Archived chats" at the bottom.
class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({required this.count, required this.items});

  /// Number of archived vehicles, shown in the label.
  final int count;

  /// Whether rows precede it, so a divider separates it from them.
  final bool items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (items) const Divider(height: 1),
        ListTile(
          leading: Icon(
            Icons.archive_outlined,
            color: scheme.onSurfaceVariant,
            semanticLabel: l10n.archivedVehicleSemantics,
          ),
          title: Text(
            l10n.archivedVehiclesRow(count),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.archivedVehicles),
        ),
      ],
    );
  }
}
