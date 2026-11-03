import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../data/models/reminder_status.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/section_header.dart';
import '../../settings/controllers/settings_controller.dart';
import '../controllers/reminder_list_controller.dart';
import 'reminder_texts.dart';

/// The status of a reminder in its colour, always with its icon and its
/// name (never the colour alone), followed by [detail] when given.
class ReminderStatusLine extends StatelessWidget {
  /// Creates the line for [status].
  const ReminderStatusLine({super.key, required this.status, this.detail});

  /// The status shown.
  final ReminderStatus status;

  /// What follows the status name, such as the due line.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final style = reminderStatusStyle(status, theme);
    final detail = this.detail;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(style.icon, size: 18, color: style.color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            detail == null || detail.isEmpty
                ? status.label(l10n)
                : joinParts(l10n, [status.label(l10n), detail]),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: style.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// One reminder row (`Docs/08_recordatorios.md`): kind icon, title, the
/// vehicle on the Home list, the status with the due line, and the chips
/// "Custom" (with the discreet warning when laxer than the reference) and
/// "Postponed". Opens the reminder.
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
    final muted = theme.colorScheme.onSurfaceVariant;
    final reminder = view.reminder;
    final vehicle = view.vehicle;
    return InkWell(
      onTap: () => context.push(AppRoutes.reminder(vehicle.id, reminder.id)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                child: Icon(
                  reminder.kind.icon,
                  semanticLabel: reminder.kind.label(l10n),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (showVehicle)
                      Text(
                        vehicle.displayNameWithPlate(l10n),
                        style:
                            theme.textTheme.bodyMedium?.copyWith(color: muted),
                      ),
                    const SizedBox(height: 2),
                    ReminderStatusLine(
                      status: view.due.status,
                      detail: reminderDueLine(reminder, view.due, l10n, units),
                    ),
                    if (reminder.overrideActive || reminder.isSnoozed)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (reminder.overrideActive)
                              _SmallChip(
                                label: l10n.reminderChipCustom,
                                icon: view.due.laxerThanReference
                                    ? Icons.warning_amber_outlined
                                    : null,
                                iconLabel: l10n.reminderLaxerWarning,
                              ),
                            if (reminder.isSnoozed)
                              _SmallChip(label: l10n.reminderChipSnoozed),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact chip with an optional leading [icon] described by
/// [iconLabel].
class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.label, this.icon, this.iconLabel});

  final String label;
  final IconData? icon;
  final String? iconLabel;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar:
          icon == null ? null : Icon(icon, size: 16, semanticLabel: iconLabel),
      label: Text(label),
    );
  }
}

/// The reminders of [views] grouped Overdue / Due soon / Up to date, in
/// their order (most urgent first), and, with [foldCompleted], the
/// completed ones folded at the bottom ("Completed (n)").
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
    return ListView(
      // Room at the bottom so the FAB never covers the last row.
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final (status, title) in [
          (ReminderStatus.overdue, l10n.reminderSectionOverdue),
          (ReminderStatus.dueSoon, l10n.reminderSectionDueSoon),
          (ReminderStatus.ok, l10n.reminderSectionOk),
        ])
          if (of(status) case final group when group.isNotEmpty) ...[
            SectionHeader(title: title),
            for (final view in group)
              ReminderTile(view: view, showVehicle: showVehicle),
          ],
        if (foldCompleted && completed.isNotEmpty)
          ExpansionTile(
            title: Text(l10n.reminderSectionCompleted(completed.length)),
            children: [
              for (final view in completed)
                ReminderTile(view: view, showVehicle: showVehicle),
            ],
          ),
      ],
    );
  }
}
