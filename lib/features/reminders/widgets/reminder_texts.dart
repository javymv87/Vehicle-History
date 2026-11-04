import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/status_colors.dart';
import '../../../data/models/calendar_date.dart';
import '../../../data/models/reminder.dart';
import '../../../data/models/reminder_kind.dart';
import '../../../data/models/reminder_status.dart';
import '../../../data/models/vehicle.dart';
import '../../../data/repositories/repository_exceptions.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/unit_formatter.dart';
import '../../../shared/widgets/action_label.dart';

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

/// The action colour and icon of a [ReminderChangeType] in the history
/// (`Docs/07_design_and_theming.md`, "Colores de acción").
extension ReminderChangeTypeAction on ReminderChangeType {
  /// What the change means: decides its colour.
  ActionMeaning get meaning => switch (this) {
        ReminderChangeType.create => ActionMeaning.born,
        ReminderChangeType.close ||
        ReminderChangeType.complete =>
          ActionMeaning.fulfilled,
        ReminderChangeType.snooze ||
        ReminderChangeType.unsnooze =>
          ActionMeaning.deferred,
        ReminderChangeType.applyOverride ||
        ReminderChangeType.restoreReference ||
        ReminderChangeType.edit =>
          ActionMeaning.ruleChanged,
      };

  /// The icon of the change.
  IconData get icon => switch (this) {
        ReminderChangeType.create => Icons.add_circle_outline,
        ReminderChangeType.edit => Icons.edit_outlined,
        ReminderChangeType.applyOverride => Icons.tune,
        ReminderChangeType.restoreReference => Icons.settings_backup_restore,
        ReminderChangeType.snooze => Icons.snooze,
        ReminderChangeType.unsnooze => Icons.update,
        ReminderChangeType.close => Icons.check_circle_outline,
        ReminderChangeType.complete => Icons.task_alt,
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

/// The vehicle of a reminder as one line: "Fiat Punto · FS548KS", or the
/// plate alone without make and model.
String vehicleLine(Vehicle vehicle, AppLocalizations l10n) =>
    joinParts(l10n, [vehicle.makeAndModel ?? '', vehicle.plate]);

/// Where the postponement of [reminder] goes: "Postponed until 30 Nov
/// 2026", "… until 98,000 km", or both.
String snoozedUntilText(
  Reminder reminder,
  AppLocalizations l10n,
  UnitFormatter units,
) {
  final date = reminder.snoozeUntilDate?.toLocalDateTime();
  final km = reminder.snoozeUntilKm;
  final distance = km == null ? null : units.distance.format(km);
  return switch ((date, distance)) {
    (final DateTime date, final String distance) =>
      l10n.reminderSnoozedUntilBoth(date, distance),
    (final DateTime date, null) => l10n.reminderSnoozedUntilDate(date),
    (null, final String distance) =>
      l10n.reminderSnoozedUntilDistance(distance),
    (null, null) => '',
  };
}

/// An interval of [months]: whole years when a multiple of 12 ("2 years",
/// "1 year"), months otherwise ("18 months").
String periodText(int months, AppLocalizations l10n) => months % 12 == 0
    ? l10n.reminderPeriodYears(months ~/ 12)
    : l10n.reminderPeriodMonths(months);

/// A criterion as one line: "Every 15,000 km or 12 months", "Every
/// 15,000 km", "Every 2 years".
///
/// [disabledKm] / [disabledMonths] say an axis is turned off by an
/// override, shown as such instead of being left out: "Every 100,000 km ·
/// no time limit". With [sentence] false the line starts in lower case,
/// to follow a label ("Manufacturer: every …").
String criterionText({
  required double? km,
  required int? months,
  bool disabledKm = false,
  bool disabledMonths = false,
  bool sentence = true,
  required AppLocalizations l10n,
  required UnitFormatter units,
}) {
  final distance = km == null ? null : units.distance.format(km);
  final period = months == null ? null : periodText(months, l10n);
  final line = joinParts(l10n, [
    switch ((distance, period)) {
      (final String first, final String second) =>
        l10n.reminderEveryEither(first, second),
      (final String only, null) ||
      (null, final String only) =>
        l10n.reminderEvery(only),
      (null, null) => '',
    },
    if (km == null && disabledKm)
      l10n.reminderNoDistanceLimit(units.distance.symbol),
    if (months == null && disabledMonths) l10n.reminderNoTimeLimit,
  ]);
  return sentence ? _sentence(line, l10n) : line;
}

/// The two axes a reminder can fall due on.
enum DueAxis {
  /// The due day (months interval, one-shot date or snooze day).
  date,

  /// The due odometer (km interval or snooze km).
  distance,
}

/// The axes of [due] in the order a row names them: the one in the worse
/// state first; between two in the same state, the one nearer its due
/// value measured in its own warning ([lead], the reminder's own when set),
/// so a row reads the urgent axis first; the date on a tie.
List<DueAxis> dueAxesInOrder(
  Reminder reminder,
  ReminderDue due,
  ReminderLead lead,
) {
  final days = due.remainingDays;
  final km = due.remainingKm;
  final leadDays = reminder.leadDays ?? lead.days;
  final leadKm = reminder.leadKm ?? lead.km;
  // 0 overdue, 1 due soon, 2 ok, as the status of the axis alone.
  int rank(num remaining, num warning, {required bool reachedAtZero}) {
    if (remaining < 0 || (reachedAtZero && remaining == 0)) return 0;
    return remaining <= warning ? 1 : 2;
  }

  final axes = [
    if (days != null)
      (
        axis: DueAxis.date,
        rank: rank(days, leadDays, reachedAtZero: false),
        ratio: days / (leadDays == 0 ? 1 : leadDays),
      ),
    if (km != null)
      (
        axis: DueAxis.distance,
        rank: rank(km, leadKm, reachedAtZero: true),
        ratio: km / (leadKm == 0 ? 1 : leadKm),
      ),
  ];
  if (axes.length == 2) {
    final (a, b) = (axes[0], axes[1]);
    // The date, listed first, keeps its place on a tie.
    if (b.rank < a.rank || (b.rank == a.rank && b.ratio < a.ratio)) {
      return [b.axis, a.axis];
    }
  }
  return [for (final item in axes) item.axis];
}

/// Whole calendar months from [from] to [to] ([to] not before [from]),
/// rounded down: 3 Jan → 2 Mar is 1 month.
int wholeMonthsBetween(CalendarDate from, CalendarDate to) {
  var months = (to.year - from.year) * 12 + to.month - from.month;
  while (months > 0 && from.addMonths(months).isAfter(to)) {
    months--;
  }
  return months;
}

/// Days from which a time span reads in months instead of days.
const int monthsFromDays = 60;

/// How a time span to or past [due]'s day reads: whole months from
/// [monthsFromDays] days, days below.
({bool months, int value}) _span(ReminderDue due) {
  final date = due.effectiveDate!;
  final days = due.remainingDays!;
  final today = date.addDays(-days);
  final span = days.abs();
  if (span < monthsFromDays) return (months: false, value: span);
  return (
    months: true,
    value: days > 0
        ? wholeMonthsBetween(today, date)
        : wholeMonthsBetween(date, today),
  );
}

/// What is left on the date axis of [due], as the detail shows it: "12
/// days left", "4 months left", "3 days ago", "due today"; `null` without
/// a date axis.
String? remainingDateText(ReminderDue due, AppLocalizations l10n) {
  final days = due.remainingDays;
  if (days == null || due.effectiveDate == null) return null;
  if (days == 0) return l10n.reminderDueToday;
  final span = _span(due);
  if (days > 0) {
    return span.months
        ? l10n.reminderRemainingMonths(span.value)
        : l10n.reminderRemainingDays(span.value);
  }
  return span.months
      ? l10n.reminderAgoMonths(span.value)
      : l10n.reminderAgoDays(span.value);
}

/// What is left on the km axis of [due], as the detail shows it: "850 km
/// left", "1,200 km ago", "due today" when reached exactly; `null` without
/// a km axis.
String? remainingDistanceText(
  ReminderDue due,
  AppLocalizations l10n,
  UnitFormatter units,
) {
  final km = due.remainingKm;
  if (km == null) return null;
  if (km == 0) return l10n.reminderDueToday;
  return km > 0
      ? l10n.reminderRemainingDistance(units.distance.format(km))
      : l10n.reminderAgoDistance(units.distance.format(-km));
}

/// The due part of a row: each axis in [dueAxesInOrder] order, "in 850 km",
/// "3 days ago", "in 12,000 km · 10 months" (an axis after a future one
/// drops its "in"), or "due today". A completed one-shot reads its day.
String rowDueText(
  Reminder reminder,
  ReminderDue due,
  ReminderLead lead,
  AppLocalizations l10n,
  UnitFormatter units,
) {
  final completedAt = reminder.completedAt;
  if (completedAt != null) return l10n.dateValue(completedAt.toLocal());
  final parts = <String>[];
  var previousFuture = false;
  for (final axis in dueAxesInOrder(reminder, due, lead)) {
    final plain = previousFuture;
    switch (axis) {
      case DueAxis.date:
        final days = due.remainingDays!;
        if (days == 0) {
          parts.add(l10n.reminderDueToday);
          previousFuture = false;
          continue;
        }
        final span = _span(due);
        if (days < 0) {
          parts.add(
            span.months
                ? l10n.reminderAgoMonths(span.value)
                : l10n.reminderAgoDays(span.value),
          );
        } else if (plain) {
          parts.add(
            span.months
                ? l10n.reminderPeriodMonths(span.value)
                : l10n.reminderPeriodDays(span.value),
          );
        } else {
          parts.add(
            span.months
                ? l10n.reminderInMonths(span.value)
                : l10n.reminderInDays(span.value),
          );
        }
        previousFuture = days > 0;
      case DueAxis.distance:
        final km = due.remainingKm!;
        if (km == 0) {
          parts.add(l10n.reminderDueToday);
        } else if (km < 0) {
          parts.add(l10n.reminderAgoDistance(units.distance.format(-km)));
        } else {
          final distance = units.distance.format(km);
          parts.add(plain ? distance : l10n.reminderDueInDistance(distance));
        }
        previousFuture = km > 0;
    }
  }
  return joinParts(l10n, parts);
}

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

/// The rest of a "Done" / "Completed" line of the history: the day and km
/// of the closing entry ([day], [km], the anchor it copied), then, only when
/// the change was registered on another local day than [day], that day in
/// brackets: "3 Nov 2026 · 190,000 km (registered on Nov 5)". The year is
/// added to the registration day only when it differs from [day]'s. Without
/// [day] (the entry is gone), the registration day alone.
String closeLineText({
  required CalendarDate? day,
  required double? km,
  required DateTime registeredAt,
  required AppLocalizations l10n,
  required UnitFormatter units,
}) {
  final registered = calendarDateOf(registeredAt.toLocal());
  if (day == null) {
    return joinParts(l10n, [
      l10n.dateValue(registered.toLocalDateTime()),
      if (km != null) units.distance.format(km),
    ]);
  }
  final line = joinParts(l10n, [
    l10n.dateValue(day.toLocalDateTime()),
    if (km != null) units.distance.format(km),
  ]);
  if (registered == day) return line;
  final format = registered.year == day.year
      ? DateFormat.MMMd(l10n.localeName)
      : DateFormat.yMMMd(l10n.localeName);
  return '$line ${l10n.reminderRegisteredOn(
    format.format(registered.toLocalDateTime()),
  )}';
}

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
