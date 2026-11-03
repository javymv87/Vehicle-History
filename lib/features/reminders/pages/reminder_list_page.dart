import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_menu_button.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../controllers/reminder_list_controller.dart';
import '../widgets/reminder_tile.dart';

/// The Reminders destination of Home (`Docs/08_recordatorios.md`): the open
/// reminders of every active vehicle, grouped Overdue / Due soon / Up to
/// date, most urgent first. No add button: a reminder belongs to a vehicle
/// and is created from the vehicle's Reminders tab, which the empty text
/// says.
class ReminderListPage extends ConsumerWidget {
  /// Creates the page.
  const ReminderListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.remindersTitle),
        actions: const [AppMenuButton()],
      ),
      body: AsyncValueView(
        value: ref.watch(activeRemindersProvider),
        data: (views) => views.isEmpty
            ? MessageView(
                icon: Icons.notifications_none,
                message: l10n.remindersEmpty,
              )
            : ReminderSections(views: views, showVehicle: true),
      ),
    );
  }
}
