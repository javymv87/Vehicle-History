import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/status_colors.dart';
import '../../../data/models/reminder.dart';
import '../../../data/models/reminder_kind.dart';
import '../../../data/models/reminder_status.dart';
import '../../../data/repositories/repository_exceptions.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/unit_formatter.dart';

// The texts and visuals a reminder shows in several places (rows, detail,
// dialogs), built in one place from the computed state. Every distance goes
// through the unit formatter and every date through `intl`.

/// Icon of a [ReminderKindGroup], used for the kinds of the group.
extension ReminderKindGroupIcon on ReminderKindGroup {
  /// The icon of this group.
  IconData get icon => switch (this) {
        ReminderKindGroup.engine => Icons.oil_barrel_outlined,
        ReminderKindGroup.cooling => Icons.ac_unit,
        ReminderKindGroup.transmission => Icons.settings_outlined,
        ReminderKindGroup.brakes => Icons.disc_full_outlined,
        ReminderKindGroup.suspension => Icons.height,
        ReminderKindGroup.wheels => Icons.tire_repair,
        ReminderKindGroup.electrical => Icons.battery_charging_full,
        ReminderKindGroup.fuelExhaust => Icons.local_gas_station_outlined,
        ReminderKindGroup.gasSystem => Icons.propane_tank_outlined,
        ReminderKindGroup.highVoltage => Icons.electric_bolt,
        ReminderKindGroup.legal => Icons.gavel,
        ReminderKindGroup.general => Icons.build_outlined,
      };
}

/// Icon of a [ReminderKind]: the one of its group.
extension ReminderKindIcon on ReminderKind {
  /// The icon of this kind.
  IconData get icon => group.icon;
}

/// Colour and icon of a [ReminderStatus] (`Docs/07_design_and_theming.md`:
/// colour only for the state, always with an icon and a text): overdue red,
/// due soon amber, ok green, completed muted.
({Color color, IconData icon}) reminderStatusStyle(
  ReminderStatus status,
  ThemeData theme,
) {
  final colors = theme.extension<StatusColors>()!;
  return switch (status) {
    ReminderStatus.overdue => (
        color: colors.overdue,
        icon: Icons.error_outline
      ),
    ReminderStatus.dueSoon => (color: colors.dueSoon, icon: Icons.schedule),
    ReminderStatus.ok => (color: colors.ok, icon: Icons.check_circle_outline),
    ReminderStatus.completed => (
        color: theme.colorScheme.onSurfaceVariant,
        icon: Icons.task_alt,
      ),
  };
}

/// [text] with a capital first letter in the language of [l10n].
String _sentence(String text, AppLocalizations l10n) =>
    toBeginningOfSentenceCase(text, l10n.localeName);

/// Joins the non-empty [parts] of one line with the separator of [l10n].
String joinParts(AppLocalizations l10n, Iterable<String> parts) =>
    parts.where((part) => part.isNotEmpty).join(l10n.partsSeparator);

/// The due text of the date axis of [due]: "due 12 Mar 2027", "due today"
/// or "overdue by 3 days"; `null` without a date axis.
String? dueDateText(ReminderDue due, AppLocalizations l10n) {
  final date = due.effectiveDate;
  final days = due.remainingDays;
  if (date == null || days == null) return null;
  if (days < 0) return l10n.reminderOverdueDays(-days);
  if (days == 0) return l10n.reminderDueToday;
  return l10n.reminderDueOn(date.toLocalDateTime());
}

/// The due text of the km axis of [due]: "in 850 km" or "overdue by
/// 120 km"; `null` without a km axis.
String? dueDistanceText(
  ReminderDue due,
  AppLocalizations l10n,
  UnitFormatter units,
) {
  final remaining = due.remainingKm;
  if (remaining == null) return null;
  return remaining <= 0
      ? l10n.reminderOverdueDistance(units.distance.format(-remaining))
      : l10n.reminderDueInDistance(units.distance.format(remaining));
}

/// The due line of a row: both axes, or the completion day of a completed
/// one-shot reminder, e.g. "Due 12 Mar 2027 · in 1,250 km".
String reminderDueLine(
  Reminder reminder,
  ReminderDue due,
  AppLocalizations l10n,
  UnitFormatter units,
) {
  final completedAt = reminder.completedAt;
  if (completedAt != null) {
    return _sentence(l10n.reminderCompletedOn(completedAt.toLocal()), l10n);
  }
  return _sentence(
    joinParts(l10n, [
      dueDateText(due, l10n) ?? '',
      dueDistanceText(due, l10n, units) ?? '',
    ]),
    l10n,
  );
}

/// A criterion as one line, e.g. "Every 15,000 km · every 12 months".
///
/// [disabledKm] / [disabledMonths] say an axis is turned off by an
/// override (shown as such instead of being left out).
String criterionText({
  required double? km,
  required int? months,
  bool disabledKm = false,
  bool disabledMonths = false,
  required AppLocalizations l10n,
  required UnitFormatter units,
}) =>
    _sentence(
      joinParts(l10n, [
        if (km != null)
          l10n.reminderEveryDistance(units.distance.format(km))
        else if (disabledKm)
          l10n.reminderDistanceDisabled,
        if (months != null)
          l10n.reminderEveryMonths(months)
        else if (disabledMonths)
          l10n.reminderTimeDisabled,
      ]),
      l10n,
    );

/// The reference criterion of [reminder]: its intervals, or its due date
/// for a one-shot reminder.
String referenceCriterionText(
  Reminder reminder,
  AppLocalizations l10n,
  UnitFormatter units,
) {
  final dueDate = reminder.dueDate;
  if (dueDate != null) {
    return _sentence(l10n.reminderOneShotOn(dueDate.toLocalDateTime()), l10n);
  }
  return criterionText(
    km: reminder.refIntervalKm,
    months: reminder.refIntervalMonths,
    l10n: l10n,
    units: units,
  );
}

/// The applied criterion of an overridden [reminder]: an axis the
/// reference has and the override turns off is shown as off.
String appliedCriterionText(
  Reminder reminder,
  AppLocalizations l10n,
  UnitFormatter units,
) =>
    criterionText(
      km: reminder.appliedIntervalKm,
      months: reminder.appliedIntervalMonths,
      disabledKm: reminder.refIntervalKm != null,
      disabledMonths: reminder.refIntervalMonths != null,
      l10n: l10n,
      units: units,
    );

/// Where a snooze postpones to, e.g. "20 Jun 2027 · 98,000 km".
String snoozeTargetText(
  Reminder reminder,
  AppLocalizations l10n,
  UnitFormatter units,
) =>
    joinParts(l10n, [
      if (reminder.snoozeUntilDate case final date?)
        l10n.dateValue(date.toLocalDateTime()),
      if (reminder.snoozeUntilKm case final km?) units.distance.format(km),
    ]);

/// The localised message of a refusal of `ReminderCloser.checkEntry` for
/// [reminder], shown inline under the field of the entry form or the
/// mark-done dialog.
String closingErrorText(
  Object error,
  Reminder reminder,
  AppLocalizations l10n,
  UnitFormatter units,
) =>
    switch (error) {
      InvalidFieldException(
        field: 'km',
        reason: InvalidFieldException.required,
      ) =>
        l10n.validationClosingKmRequired,
      InvalidFieldException(
        field: 'km',
        reason: InvalidFieldException.belowAnchor,
      ) =>
        l10n.validationClosingBelowAnchor(
          units.distance.format(reminder.lastDoneKm ?? 0),
        ),
      InvalidFieldException(
        field: 'date',
        reason: InvalidFieldException.beforeAnchor,
      ) =>
        l10n.validationClosingBeforeAnchor(
          reminder.lastDoneDate!.toLocalDateTime(),
        ),
      InvalidFieldException(
        field: 'date',
        reason: InvalidFieldException.inFuture,
      ) =>
        l10n.validationClosingFuture,
      _ => l10n.errorReminderRule,
    };
