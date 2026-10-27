import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../controllers/vehicle_list_controller.dart';
import '../widgets/vehicle_tile.dart';

/// The archived vehicles (`Docs/03_features.md`, "Archivo"): the same rows
/// as the main list, each with its archive chip, most recently archived
/// first. Tapping one opens its page, read-only. Reached from the
/// "Archived (n)" row at the bottom of the vehicle list; no add button.
class ArchivedVehicleListPage extends ConsumerWidget {
  /// Creates the archived vehicles page.
  const ArchivedVehicleListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.archivedVehiclesTitle)),
      body: AsyncValueView(
        value: ref.watch(archivedVehicleListProvider),
        data: (items) => items.isEmpty
            ? MessageView(
                icon: Icons.archive_outlined,
                message: l10n.archivedListEmpty,
              )
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return VehicleTile(
                    item: item,
                    showArchive: true,
                    onTap: () =>
                        context.push(AppRoutes.vehicle(item.vehicle.id)),
                  );
                },
              ),
      ),
    );
  }
}
