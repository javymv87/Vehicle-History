import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/vehicle_kind_icon.dart';
import '../../settings/controllers/settings_controller.dart';
import '../controllers/vehicle_list_controller.dart';

/// One row of the vehicle list: kind icon, make and model, plate, nickname,
/// owner, current km and fuel, and on the archived list ([showArchive]) a
/// chip with the archive reason, month and final km.
///
/// A vehicle without make and model (created at schema v1) shows its plate
/// as the main line instead.
class VehicleTile extends ConsumerWidget {
  /// Creates the row for [item], calling [onTap] when tapped.
  const VehicleTile({
    super.key,
    required this.item,
    required this.onTap,
    this.showArchive = false,
  });

  /// The vehicle shown, with its owner.
  final VehicleWithOwner item;

  /// Opens the vehicle detail.
  final VoidCallback onTap;

  /// Whether to show the archive chip of an archived vehicle.
  final bool showArchive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = unitFormatterOf(context, ref);
    final theme = Theme.of(context);
    final vehicle = item.vehicle;
    final makeAndModel = vehicle.makeAndModel;
    final archiveChip =
        showArchive ? vehicle.archiveChipLabel(l10n, units) : null;
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
              units.distance.format(vehicle.currentOdometerKm),
              vehicle.fuelType.label(l10n),
            ),
          ),
          if (archiveChip != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Chip(
                avatar: const Icon(Icons.archive_outlined, size: 18),
                label: Text(archiveChip),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
