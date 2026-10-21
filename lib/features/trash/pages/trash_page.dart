import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/trashed_vehicle.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/feedback.dart';
import '../controllers/trash_controller.dart';
import '../widgets/trashed_vehicle_tile.dart';

/// The Trash (U17): the deleted vehicles, each with Restore and Delete
/// permanently, and "Empty Trash" in the app bar. Opened from the overflow
/// menu of the vehicle list.
///
/// A vehicle stays here for 30 days after its deletion; the cleanup at app
/// start then removes it for good.
class TrashPage extends ConsumerWidget {
  /// Creates the Trash page.
  const TrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final trashed = ref.watch(trashedVehiclesProvider);
    final count = trashed.value?.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.trashTitle),
        actions: [
          if (count > 0)
            // An icon, not a text button: the label does not fit the app
            // bar of a narrow phone with large text.
            IconButton(
              tooltip: l10n.actionEmptyTrash,
              color: Theme.of(context).colorScheme.error,
              icon: const Icon(Icons.delete_sweep),
              onPressed: () => _emptyTrash(context, ref, count),
            ),
        ],
      ),
      body: AsyncValueView(
        value: trashed,
        data: (items) => items.isEmpty
            ? MessageView(icon: Icons.delete_outline, message: l10n.trashEmpty)
            : _TrashList(items: items),
      ),
    );
  }

  /// Empties the Trash after a confirmation with the number of vehicles.
  Future<void> _emptyTrash(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(trashControllerProvider.notifier);
    final confirmed = await confirmAction(
      context,
      title: l10n.emptyTrashTitle,
      message: l10n.emptyTrashMessage(count),
      confirmLabel: l10n.actionEmptyTrash,
      destructive: true,
    );
    if (!confirmed) return;
    switch (await controller.purgeAll()) {
      case ActionSuccess():
        showSavedSnackBar(messenger, l10n.trashEmptied);
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }
}

/// The list of vehicles in the Trash.
class _TrashList extends ConsumerWidget {
  const _TrashList({required this.items});

  final List<TrashedVehicle> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read once per build: the days left change only from one day to the
    // next, and the list rebuilds after every change anyway.
    final now = DateTime.now().toUtc();
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return TrashedVehicleTile(
          item: item,
          now: now,
          onRestore: () => _restore(context, ref, item),
          onPurge: () => _purge(context, ref, item),
        );
      },
    );
  }

  /// Restores [item] (U18): "Vehicle restored", or the plate / owner error.
  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    TrashedVehicle item,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(trashControllerProvider.notifier)
        .restore(item.vehicle.id);
    switch (result) {
      case ActionSuccess():
        showSavedSnackBar(messenger, l10n.vehicleRestored);
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  /// Removes [item] for good after a destructive confirmation.
  Future<void> _purge(
    BuildContext context,
    WidgetRef ref,
    TrashedVehicle item,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(trashControllerProvider.notifier);
    final confirmed = await confirmAction(
      context,
      title: l10n.purgeVehicleTitle(item.vehicle.displayNameWithPlate(l10n)),
      message: item.contents.attachmentCount == 0
          ? l10n.purgeVehicleMessage(
              item.contents.entryCount,
              item.contents.readingCount,
            )
          : l10n.purgeVehicleMessageWithAttachments(
              item.contents.entryCount,
              item.contents.readingCount,
              item.contents.attachmentCount,
            ),
      confirmLabel: l10n.actionPurge,
      destructive: true,
    );
    if (!confirmed) return;
    switch (await controller.purge(item.vehicle.id)) {
      case ActionSuccess():
        showSavedSnackBar(messenger, l10n.vehiclePurged);
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }
}
