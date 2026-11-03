import 'calendar_date.dart';
import 'reminder.dart';

/// How long before a due date or km a reminder starts warning: the global
/// setting (`reminder_lead_days`, `reminder_lead_km`), overridable per
/// reminder.
class ReminderLead {
  /// Creates the lead; the defaults are those of a fresh install.
  const ReminderLead({this.days = defaultDays, this.km = defaultKm});

  /// Reads the two stored settings; a missing or unreadable value (negative,
  /// not a number, written by a newer app) is its default.
  factory ReminderLead.fromCodes({String? days, String? km}) {
    final parsedDays = int.tryParse(days ?? '');
    final parsedKm = double.tryParse(km ?? '');
    return ReminderLead(
      days: parsedDays == null || parsedDays < 0 ? defaultDays : parsedDays,
      km: parsedKm == null || parsedKm < 0 || !parsedKm.isFinite
          ? defaultKm
          : parsedKm,
    );
  }

  /// Default warning in days.
  static const int defaultDays = 30;

  /// Default warning in km.
  static const double defaultKm = 1000;

  /// Days of warning before a due date.
  final int days;

  /// Km of warning before a due km (SI).
  final double km;

  /// The text stored for [km]: a whole number without decimals, so the
  /// setting reads as it was typed in km.
  static String kmCode(double km) =>
      km == km.roundToDouble() ? km.round().toString() : km.toString();

  @override
  bool operator ==(Object other) =>
      other is ReminderLead && other.days == days && other.km == km;

  @override
  int get hashCode => Object.hash(days, km);

  @override
  String toString() => 'ReminderLead($days days, $km km)';
}

/// Where a reminder stands, as computed on every read. Never stored.
enum ReminderStatus {
  /// Past its date or km.
  overdue,

  /// Within its lead of the date or the km.
  dueSoon,

  /// Neither: nothing to do yet.
  ok,

  /// A one-shot reminder already closed: never listed as active.
  completed,
}

/// The computed state of a reminder (`Docs/08_recordatorios.md`): its
/// status, what falls due when, and what the reference would say.
class ReminderDue {
  /// Creates the state. Normally built by [evaluateReminder].
  const ReminderDue({
    required this.status,
    this.dueDate,
    this.dueKm,
    this.referenceDueDate,
    this.referenceDueKm,
    this.effectiveDate,
    this.effectiveKm,
    this.remainingDays,
    this.remainingKm,
    this.laxerThanReference = false,
  });

  /// Overdue, due soon, ok or completed.
  final ReminderStatus status;

  /// Due day by the criterion in use (the due date of a one-shot).
  final CalendarDate? dueDate;

  /// Due km by the criterion in use.
  final double? dueKm;

  /// Due day by the reference criterion, shown next to an override.
  final CalendarDate? referenceDueDate;

  /// Due km by the reference criterion, shown next to an override.
  final double? referenceDueKm;

  /// The day that decides the status: the snooze day, or [dueDate].
  final CalendarDate? effectiveDate;

  /// The km that decides the status: the snooze km, or [dueKm].
  final double? effectiveKm;

  /// Days from today to [effectiveDate]; negative once past.
  final int? remainingDays;

  /// Km from the current odometer to [effectiveKm]; negative once past.
  final double? remainingKm;

  /// The override is active and, on at least one axis of the reference,
  /// the applied criterion falls due later or is disabled: the discreet
  /// warning icon of the detail page and the "Custom" chip.
  final bool laxerThanReference;

  @override
  bool operator ==(Object other) =>
      other is ReminderDue &&
      other.status == status &&
      other.dueDate == dueDate &&
      other.dueKm == dueKm &&
      other.referenceDueDate == referenceDueDate &&
      other.referenceDueKm == referenceDueKm &&
      other.effectiveDate == effectiveDate &&
      other.effectiveKm == effectiveKm &&
      other.remainingDays == remainingDays &&
      other.remainingKm == remainingKm &&
      other.laxerThanReference == laxerThanReference;

  @override
  int get hashCode => Object.hash(
        status,
        dueDate,
        dueKm,
        referenceDueDate,
        referenceDueKm,
        effectiveDate,
        effectiveKm,
        remainingDays,
        remainingKm,
        laxerThanReference,
      );

  @override
  String toString() => 'ReminderDue(${status.name}, '
      'date: ${effectiveDate?.toIso8601String()}, km: $effectiveKm, '
      'days: $remainingDays, remainingKm: $remainingKm)';
}

/// Due day of [reminder] by the criterion in use, or by the reference one
/// when [reference]: the due date of a one-shot reminder, otherwise the
/// anchor day plus the months interval (`null` without a time axis).
CalendarDate? reminderDueDate(Reminder reminder, {bool reference = false}) {
  if (reminder.isOneShot) return reminder.dueDate;
  final months =
      reference ? reminder.refIntervalMonths : reminder.intervalMonths;
  final anchor = reminder.lastDoneDate;
  if (months == null || anchor == null) return null;
  return anchor.addMonths(months);
}

/// Due km of [reminder] by the criterion in use, or by the reference one
/// when [reference]: the anchor km plus the km interval (`null` without a
/// km axis, and always on a one-shot reminder).
double? reminderDueKm(Reminder reminder, {bool reference = false}) {
  if (reminder.isOneShot) return null;
  final interval = reference ? reminder.refIntervalKm : reminder.intervalKm;
  final anchor = reminder.lastDoneKm;
  if (interval == null || anchor == null) return null;
  return anchor + interval;
}

/// Computes where [reminder] stands on [today] with the vehicle's odometer
/// at [currentKm] (SI) and the global [lead] (`Docs/08_recordatorios.md`).
///
/// Pure: no clock, no I/O. Either axis alone decides ("the first of the two
/// to fall due wins", CLAUDE.md §5): overdue once the date is past or the
/// odometer reached the km; due soon within the lead on either axis. A
/// snooze replaces the due value of its axis. A completed one-shot is
/// [ReminderStatus.completed] whatever the dates.
ReminderDue evaluateReminder(
  Reminder reminder, {
  required CalendarDate today,
  required double currentKm,
  required ReminderLead lead,
}) {
  final dueDate = reminderDueDate(reminder);
  final dueKm = reminderDueKm(reminder);
  final effectiveDate = reminder.snoozeUntilDate ?? dueDate;
  final effectiveKm = reminder.snoozeUntilKm ?? dueKm;
  final remainingDays =
      effectiveDate == null ? null : today.daysUntil(effectiveDate);
  final remainingKm = effectiveKm == null ? null : effectiveKm - currentKm;
  final leadDays = reminder.leadDays ?? lead.days;
  final leadKm = reminder.leadKm ?? lead.km;

  final ReminderStatus status;
  if (reminder.isCompleted) {
    status = ReminderStatus.completed;
  } else if ((remainingDays != null && remainingDays < 0) ||
      (remainingKm != null && remainingKm <= 0)) {
    status = ReminderStatus.overdue;
  } else if ((remainingDays != null && remainingDays <= leadDays) ||
      (remainingKm != null && remainingKm <= leadKm)) {
    status = ReminderStatus.dueSoon;
  } else {
    status = ReminderStatus.ok;
  }

  return ReminderDue(
    status: status,
    dueDate: dueDate,
    dueKm: dueKm,
    referenceDueDate: reminderDueDate(reminder, reference: true),
    referenceDueKm: reminderDueKm(reminder, reference: true),
    effectiveDate: effectiveDate,
    effectiveKm: effectiveKm,
    remainingDays: remainingDays,
    remainingKm: remainingKm,
    laxerThanReference: isLaxerThanReference(reminder),
  );
}

/// Whether the override of [reminder] is active and, on an axis the
/// reference has, the applied interval is longer or the axis is disabled.
///
/// Both criteria share the anchor, so comparing the intervals is comparing
/// the due values. An axis the reference lacks and the override adds is
/// stricter, never laxer.
bool isLaxerThanReference(Reminder reminder) {
  if (!reminder.overrideActive) return false;
  bool laxer(num? reference, num? applied) =>
      reference != null && (applied == null || applied > reference);
  return laxer(reminder.refIntervalKm, reminder.appliedIntervalKm) ||
      laxer(reminder.refIntervalMonths, reminder.appliedIntervalMonths);
}

/// Orders computed states by urgency: overdue first, then due soon, then
/// ok, then completed; within a status by remaining days, then remaining
/// km, an axis that is missing sorting after one that is set.
int compareByUrgency(ReminderDue a, ReminderDue b) {
  final byStatus = a.status.index.compareTo(b.status.index);
  if (byStatus != 0) return byStatus;
  int compareNullable(num? x, num? y) {
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  }

  final byDays = compareNullable(a.remainingDays, b.remainingDays);
  if (byDays != 0) return byDays;
  return compareNullable(a.remainingKm, b.remainingKm);
}
