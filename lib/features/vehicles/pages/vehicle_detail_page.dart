import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/router/navigation.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/detail_field.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../controllers/vehicle_deletion_controller.dart';
import '../controllers/vehicle_detail_controller.dart';
import '../controllers/vehicle_list_controller.dart';

/// Detail of one vehicle. The vehicle id comes from the path; an unknown or
/// deleted id shows a not-found page.
class VehicleDetailPage extends ConsumerWidget {
  /// Creates the page for the vehicle with [vehicleId].
  const VehicleDetailPage({super.key, required this.vehicleId});

  /// Id of the vehicle, from the path.
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(vehicleDetailProvider(vehicleId));
    return detail.when(
      skipLoadingOnReload: true,
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(),
        body: MessageView(icon: Icons.error_outline, message: l10n.loadError),
      ),
      data: (item) => item == null
          ? NotFoundPage(message: l10n.vehicleNotFound)
          : _VehicleDetailView(item: item),
    );
  }
}

/// The loaded vehicle detail.
class _VehicleDetailView extends ConsumerWidget {
  const _VehicleDetailView({required this.item});

  final VehicleWithOwner item;

  /// Deletes the vehicle after confirmation, then offers "Undo".
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final vehicle = item.vehicle;
    final confirmed = await confirmDelete(
      context,
      title: l10n.deleteVehicleTitle,
      message: l10n.deleteVehicleMessage(vehicle.plate),
    );
    if (!confirmed || !context.mounted) return;

    // Read before popping: the controller outlives this page, the page's
    // `ref` does not.
    final deletion = ref.read(vehicleDeletionControllerProvider.notifier);
    final result = await deletion.delete(vehicle.id);
    if (!context.mounted) return;
    switch (result) {
      case ActionSuccess():
        context.popOrGo(AppRoutes.vehicles);
        showUndoSnackBar(
          messenger,
          l10n,
          l10n.vehicleDeleted,
          onUndo: () async {
            final undone = await deletion.undo(vehicle.id);
            if (undone case ActionFailure(:final error)) {
              showErrorSnackBar(messenger, error.message(l10n));
            }
          },
        );
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final vehicle = item.vehicle;
    final owner = item.owner;
    return Scaffold(
      appBar: AppBar(
        title: Text(vehicle.plate),
        actions: [
          IconButton(
            tooltip: l10n.actionEdit,
            icon: const Icon(Icons.edit),
            onPressed: () => context.push(AppRoutes.editVehicle(vehicle.id)),
          ),
          IconButton(
            tooltip: l10n.actionDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          DetailField(label: l10n.fieldPlate, value: vehicle.plate),
          if (vehicle.nickname case final nickname?)
            DetailField(label: l10n.fieldNickname, value: nickname),
          if (owner != null)
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(owner.fullName),
              subtitle: Text(l10n.fieldOwner),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.owner(owner.id)),
            ),
          DetailField(
            label: l10n.fieldFuelType,
            value: vehicle.fuelType.label(l10n),
          ),
          DetailField(
            label: l10n.fieldCurrentKm,
            value: l10n.kmValue(vehicle.currentOdometerKm),
            note: l10n.vehicleKmNote,
          ),
          if (vehicle.recommendedEngineOil case final oil?)
            DetailField(label: l10n.fieldRecommendedOil, value: oil),
          if (vehicle.manufacturerNotes case final notes?)
            DetailField(label: l10n.fieldManufacturerNotes, value: notes),
        ],
      ),
    );
  }
}
