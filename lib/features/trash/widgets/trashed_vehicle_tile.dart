import 'package:flutter/material.dart';

import '../../../data/models/trashed_vehicle.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/vehicle_kind_icon.dart';

/// One row of the Trash (U17): kind icon, make and model, plate, owner, when
/// it was deleted, how long it has left, what it carries, and the two
/// actions, Restore and Delete permanently.
class TrashedVehicleTile extends StatelessWidget {
  /// Creates the row for [item]. [now] (UTC) is the instant the days left
  /// are counted from.
  const TrashedVehicleTile({
    super.key,
    required this.item,
    required this.now,
    required this.onRestore,
    required this.onPurge,
  });

  /// The vehicle in the Trash.
  final TrashedVehicle item;

  /// Current instant, in UTC.
  final DateTime now;

  /// Brings the vehicle back.
  final VoidCallback onRestore;

  /// Asks to remove the vehicle for good.
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final vehicle = item.vehicle;
    final makeAndModel = vehicle.makeAndModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: CircleAvatar(
            child: Icon(
              vehicle.kind.icon,
              semanticLabel: vehicle.kind.label(l10n),
            ),
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
              Text(item.owner.fullName),
              // A timestamp shown as the user's local day.
              Text(l10n.trashDeletedOn(item.deletedAt.toLocal())),
              Text(l10n.trashPurgeIn(item.daysUntilPurge(now))),
              Text(
                l10n.trashContents(
                  item.contents.entryCount,
                  item.contents.readingCount,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          // Stacks the buttons vertically when they do not fit side by
          // side (narrow screens, large text).
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: onPurge,
                icon: const Icon(Icons.delete_forever),
                label: Text(l10n.actionPurge),
              ),
              TextButton.icon(
                onPressed: onRestore,
                icon: const Icon(Icons.restore_from_trash),
                label: Text(l10n.actionRestore),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
