import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../data/models/mileage_reading.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/feedback.dart';
import '../../settings/controllers/settings_controller.dart';
import '../../vehicles/controllers/vehicle_archive_controller.dart';
import '../controllers/mileage_history_controller.dart';
import '../controllers/mileage_reading_deletion_controller.dart';

/// The Mileage tab of a vehicle (`Docs/03_features.md`, U12 and U14): its
/// odometer readings newest first, each with the km driven since the
/// previous one, the initial reading at the bottom. Tapping a reading opens
/// its actions; for an archived vehicle the rows have none.
class MileageHistoryView extends ConsumerWidget {
  /// Creates the readings list of the vehicle with [vehicleId].
  const MileageHistoryView({super.key, required this.vehicleId});

  /// Id of the vehicle whose readings are shown.
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readings = ref.watch(mileageReadingsProvider(vehicleId));
    final readOnly = ref.watch(vehicleReadOnlyProvider(vehicleId));
    return AsyncValueView(
      value: readings,
      data: (readings) => ListView.builder(
        // Room at the bottom so the FAB never covers the initial reading.
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: readings.length,
        itemBuilder: (context, index) => _ReadingTile(
          reading: readings[index],
          // Newest first: the previous reading is the next element.
          previous: index + 1 < readings.length ? readings[index + 1] : null,
          onTap: readOnly
              ? null
              : () => _showActions(context, ref, readings, index),
        ),
      ),
    );
  }

  /// Opens the bottom sheet of the reading at [index] in [readings] (U14):
  /// delete for the last reading, correct for the sole one, otherwise an
  /// explanation.
  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    List<MileageReading> readings,
    int index,
  ) async {
    final l10n = AppLocalizations.of(context);
    final units = readUnitFormatter(context, ref);
    final reading = readings[index];
    final isSole = readings.length == 1;
    final isLast = index == 0;
    final action = await showModalBottomSheet<_ReadingAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.speed),
                title: Text(units.distance.format(reading.km)),
                subtitle: Text(l10n.dateValue(reading.date.toLocalDateTime())),
              ),
              const Divider(),
              if (isSole)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: Text(l10n.readingCorrect),
                  onTap: () => Navigator.of(context).pop(_ReadingAction.edit),
                )
              else if (isLast)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(l10n.actionDelete),
                  onTap: () => Navigator.of(context).pop(_ReadingAction.delete),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(l10n.readingOnlyLastDeletable),
                ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case _ReadingAction.edit:
        await context.push(AppRoutes.editMileageReading(vehicleId, reading.id));
      case _ReadingAction.delete:
        await _delete(context, ref, reading);
      case null:
        break;
    }
  }

  /// Deletes the last [reading] after confirmation, then offers "Undo".
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MileageReading reading,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmDelete(
      context,
      title: l10n.deleteReadingTitle,
      message: l10n.deleteReadingMessage(
        readUnitFormatter(context, ref).distance.format(reading.km),
      ),
    );
    if (!confirmed || !context.mounted) return;
    // The controller outlives this tab; the snackbar holds it, not `ref`.
    final deletion =
        ref.read(mileageReadingDeletionControllerProvider.notifier);
    final result = await deletion.delete(reading.id);
    switch (result) {
      case ActionSuccess():
        showUndoSnackBar(
          messenger,
          l10n,
          l10n.readingDeleted,
          onUndo: () async {
            final undone = await deletion.undo(reading.id);
            if (undone case ActionFailure(:final error)) {
              showErrorSnackBar(messenger, error.message(l10n));
            }
          },
        );
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }
}

/// What the bottom sheet of a reading asked for.
enum _ReadingAction { edit, delete }

/// One reading row: km, day, and the difference with the [previous]
/// reading ("Initial reading" for the oldest).
class _ReadingTile extends ConsumerWidget {
  const _ReadingTile({
    required this.reading,
    required this.previous,
    required this.onTap,
  });

  final MileageReading reading;
  final MileageReading? previous;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = unitFormatterOf(context, ref);
    final previous = this.previous;
    final difference = previous == null
        ? l10n.initialReading
        : l10n.readingDifference(
            units.distance.format(reading.km - previous.km),
          );
    return ListTile(
      leading: const Icon(Icons.speed),
      title: Text(
        units.distance.format(reading.km),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        l10n.readingRowSubtitle(reading.date.toLocalDateTime(), difference),
      ),
      onTap: onTap,
    );
  }
}
