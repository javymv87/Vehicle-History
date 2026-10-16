import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/vehicle_kind_icon.dart';
import '../controllers/vehicle_list_controller.dart';

/// One row of the vehicle list: kind icon, make and model, plate, nickname,
/// owner, current km and fuel.
///
/// A vehicle without make and model (created at schema v1) shows its plate
/// as the main line instead.
class VehicleTile extends StatelessWidget {
  /// Creates the row for [item], calling [onTap] when tapped.
  const VehicleTile({super.key, required this.item, required this.onTap});

  /// The vehicle shown, with its owner.
  final VehicleWithOwner item;

  /// Opens the vehicle detail.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final vehicle = item.vehicle;
    final makeAndModel = vehicle.makeAndModel;
    return ListTile(
      leading: CircleAvatar(
        child: Icon(vehicle.kind.icon, semanticLabel: vehicle.kind.label(l10n)),
      ),
      title: Text(
        makeAndModel ?? vehicle.plate,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (makeAndModel != null) Text(vehicle.plate),
          if (vehicle.nickname case final nickname?) Text(nickname),
          if (item.owner case final owner?) Text(owner.fullName),
          Text(
            l10n.vehicleSummary(
              vehicle.currentOdometerKm,
              vehicle.fuelType.label(l10n),
            ),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
