import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../data/models/reminder_status.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/app_chip.dart';
import '../../../shared/widgets/list_row.dart';
import '../../../shared/widgets/list_sections.dart';
import '../../../shared/widgets/state_line.dart';
import '../../settings/controllers/settings_controller.dart';
import '../controllers/reminder_list_controller.dart';
import 'reminder_texts.dart';

/// One reminder row (`Docs/08_recordatorios.md`), a `ListRow`: the kind
/// icon in the circle, the title, the status in its colour with its icon
/// and the due axes ("Overdue · 3 days ago", "Up to date · in 12,000 km ·
/// 10 months"), on Home the vehicle, and trailing the chips "Custom" (with
/// the warning icon when laxer than the reference) and "Postponed". Opens
/// the reminder.
class ReminderTile extends ConsumerWidget {
  /// Creates the row for [view]; [showVehicle] adds the vehicle line.
  const ReminderTile({super.key, required this.view, this.showVehicle = false});

  /// The reminder and its computed state.
  final ReminderView view;

  /// Whether the vehicle's make, model and plate are shown (Home list).
  final bool showVehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = unitFormatterOf(context, ref);
    final theme = Theme.of(context);
    final reminder = view.reminder;
    final vehicle = view.vehicle;
    final status = view.due.status;
    final style = reminderStatusStyle(status, theme);
    return ListRow(
      onTap: () => context.push(AppRoutes.reminder(vehicle.id, reminder.id)),
      leading: Icon(
        reminder.kind.icon,
        semanticLabel: reminder.kind.label(l10n),
      ),
      title: reminder.title,
      secondLine: StateLine(
        icon: style.icon,
        color: style.color,
        text: joinParts(l10n, [
          status.label(l10n),
          rowDueText(reminder, view.due, view.lead, l10n, units),
        ]),
      ),
      thirdLine: showVehicle ? vehicleLine(vehicle, l10n) : null,
      trailing: [
        if (reminder.overrideActive)
          AppChip(
            label: l10n.reminderChipCustom,
            icon: view.due.laxerThanReference
                ? Icons.warning_amber_outlined
                : null,
            iconLabel: l10n.reminderChipLaxer,
          ),
        if (reminder.isSnoozed) AppChip(label: l10n.reminderChipSnoozed),
      ],
    );
  }
}

/// The reminders of [views] grouped Overdue / Due soon / Up to date, in
/// their order (most urgent first), and, with [foldCompleted], the
/// completed ones folded at the bottom ("Completed (n)"): a
/// `ListSections` of `ReminderTile`s.
class ReminderSections extends StatelessWidget {
  /// Creates the grouped list.
  const ReminderSections({
    super.key,
    required this.views,
    this.showVehicle = false,
    this.foldCompleted = false,
  });

  /// Every reminder to show, sorted by urgency.
  final List<ReminderView> views;

  /// Whether each row names its vehicle (Home list).
  final bool showVehicle;

  /// Whether completed reminders are listed, folded (the vehicle tab).
  final bool foldCompleted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    List<ReminderView> of(ReminderStatus status) => [
          for (final view in views)
            if (view.due.status == status) view,
        ];
    final completed = of(ReminderStatus.completed);
    return ListSections<ReminderView>(
      sections: [
        for (final (status, title) in [
          (ReminderStatus.overdue, l10n.reminderSectionOverdue),
          (ReminderStatus.dueSoon, l10n.reminderSectionDueSoon),
          (ReminderStatus.ok, l10n.reminderSectionOk),
        ])
          ListSection(title: title, items: of(status)),
      ],
      folded: foldCompleted
          ? ListSection(
              title: l10n.reminderSectionCompleted(completed.length),
              items: completed,
            )
          : null,
      row: (view) => ReminderTile(view: view, showVehicle: showVehicle),
    );
  }
}
