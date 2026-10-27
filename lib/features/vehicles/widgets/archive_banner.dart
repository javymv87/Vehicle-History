import 'package:flutter/material.dart';

import '../../../data/models/archive_reason.dart';
import '../../../data/models/vehicle.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';

/// The fixed grey banner under the app bar of an archived vehicle
/// (`Docs/03_features.md`, "Archivo"): the archive icon, "Archived on
/// 12 Mar 2026 · Sold · 184,300 km" (km left out when none), the note on
/// a second line when present, and the "Reactivate" button.
///
/// Grey, never a status colour: archived is a state, not a warning. The
/// icon and the text carry the meaning, the colour only groups them.
class ArchiveBanner extends StatelessWidget {
  /// Creates the banner of the archived [vehicle]; [onReactivate] runs the
  /// reactivation, with no confirmation.
  const ArchiveBanner({
    super.key,
    required this.vehicle,
    required this.onReactivate,
  });

  /// The archived vehicle. Must have `isArchived`.
  final Vehicle vehicle;

  /// Called when "Reactivate" is tapped.
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final day = vehicle.archivedAt!.toLocalDateTime();
    final reason = (vehicle.archiveReason ?? ArchiveReason.none).label(l10n);
    final km = vehicle.archivedKm;
    final summary = km == null
        ? l10n.archiveBanner(day, reason)
        : l10n.archiveBannerWithKm(day, reason, km);
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.archive_outlined,
              color: scheme.onSurfaceVariant,
              semanticLabel: l10n.archivedVehicleSemantics,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (vehicle.archiveNote case final note?)
                    Text(
                      note,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onReactivate,
              child: Text(l10n.reactivateAction),
            ),
          ],
        ),
      ),
    );
  }
}
