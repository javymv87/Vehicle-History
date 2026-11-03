import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../controllers/reminder_list_controller.dart';
import 'reminder_tile.dart';

/// The Reminders tab of a vehicle: its reminders grouped by status, most
/// urgent first, and its completed one-shot reminders folded at the
/// bottom. The same on an archived vehicle, whose page offers no add
/// button and whose reminders open read-only.
class VehicleRemindersView extends ConsumerWidget {
  /// Creates the tab for the vehicle with [vehicleId].
  const VehicleRemindersView({super.key, required this.vehicleId});

  /// Id of the vehicle whose reminders are shown.
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AsyncValueView(
      value: ref.watch(vehicleRemindersProvider(vehicleId)),
      data: (views) => views.isEmpty
          ? MessageView(
              icon: Icons.notifications_none,
              message: l10n.vehicleRemindersEmpty,
            )
          : ReminderSections(views: views, foldCompleted: true),
    );
  }
}
