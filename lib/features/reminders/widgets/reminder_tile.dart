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

/// One reminder row (`Docs/08_recordatorios.md`): the kind icon in a
/// 40 dp circle, the title, the status in its colour with its icon and the
/// due axes ("Overdue · 3 days ago", "Up to date · in 12,000 km ·
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
    final muted = theme.colorScheme.onSurfaceVariant;
    final reminder = view.reminder;
    final vehicle = view.vehicle;
    final status = view.due.status;
    final style = reminderStatusStyle(status, theme);
    return InkWell(
      onTap: () => context.push(AppRoutes.reminder(vehicle.id, reminder.id)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
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
                    Text(reminder.title, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(style.icon, size: 16, color: style.color),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            joinParts(l10n, [
                              status.label(l10n),
                              rowDueText(
                                reminder,
                                view.due,
                                view.lead,
                                l10n,
                                units,
                              ),
                            ]),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: style.color),
                          ),
                        ),
                      ],
                    ),
                    if (showVehicle)
                      Text(
                        vehicle.displayNameWithPlate(l10n),
                        style:
                            theme.textTheme.bodyMedium?.copyWith(color: muted),
                      ),
                  ],
                ),
              ),
              if (reminder.overrideActive || reminder.isSnoozed) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (reminder.overrideActive)
                      ReminderChip(
                        label: l10n.reminderChipCustom,
                        icon: view.due.laxerThanReference
                            ? Icons.warning_amber_outlined
                            : null,
                        iconLabel: l10n.reminderChipLaxer,
                      ),
                    if (reminder.overrideActive && reminder.isSnoozed)
                      const SizedBox(height: 4),
                    if (reminder.isSnoozed)
                      ReminderChip(label: l10n.reminderChipSnoozed),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small chip of a reminder ("Custom", "Postponed", "Less strict") with
/// an optional leading [icon] described by [iconLabel], tinted with
/// [color] when given.
class ReminderChip extends StatelessWidget {
  /// Creates the chip.
  const ReminderChip({
    super.key,
    required this.label,
    this.icon,
    this.iconLabel,
    this.color,
  });

  /// The text of the chip.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// What [icon] means, for screen readers.
  final String? iconLabel;

  /// The tint of the chip; the theme's neutral one when `null`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = this.icon;
    final color = this.color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: this.color == null
            ? theme.colorScheme.surfaceContainerHighest
            : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color, semanticLabel: iconLabel),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
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
    // No dividers: 4 dp between rows.
    Widget tile(ReminderView view) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: ReminderTile(view: view, showVehicle: showVehicle),
        );
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
            for (final view in group) tile(view),
          ],
        if (foldCompleted && completed.isNotEmpty)
          ExpansionTile(
            title: Text(l10n.reminderSectionCompleted(completed.length)),
            shape: const Border(),
            collapsedShape: const Border(),
            children: [for (final view in completed) tile(view)],
          ),
      ],
    );
  }
}
