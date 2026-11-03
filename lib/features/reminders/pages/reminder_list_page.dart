import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_menu_button.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../controllers/reminder_list_controller.dart';
import '../widgets/reminder_tile.dart';

/// The Reminders destination of Home (`Docs/08_recordatorios.md`): an
/// agenda of the overdue and due-soon reminders of every active vehicle,
/// grouped Overdue / Due soon, most urgent first. Up-to-date reminders live
/// in each vehicle's Reminders tab; with nothing due the page says how many
/// are up to date, or where reminders are created. No add button: a
/// reminder belongs to a vehicle.
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
        value: ref.watch(reminderAgendaProvider),
        data: (agenda) => agenda.due.isEmpty
            ? MessageView(
                icon: Icons.notifications_none,
                message: l10n.reminderAgendaEmpty,
                detail: agenda.okCount > 0
                    ? l10n.reminderAgendaOkCount(agenda.okCount)
                    : l10n.reminderAgendaNone,
              )
            : ReminderSections(views: agenda.due, showVehicle: true),
      ),
    );
  }
}
