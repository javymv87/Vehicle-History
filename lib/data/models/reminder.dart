import 'calendar_date.dart';
import 'copy_with_sentinel.dart';
import 'reminder_kind.dart';
import 'vehicle.dart';

/// Who wrote a reminder.
enum ReminderSource {
  /// Typed by the owner in the app.
  manual('manual'),

  /// Written into an exported package by the loading procedure of
  /// `Docs/08_recordatorios.md`, from the manufacturer's manual.
  generated('generated');

  const ReminderSource(this.code);

  /// Text stored in `reminders.source`.
  final String code;

  /// The source stored as [code], or `null` when the code is unknown.
  static ReminderSource? fromCode(String code) {
    for (final source in values) {
      if (source.code == code) return source;
    }
    return null;
  }
}

/// What a [ReminderChange] records.
enum ReminderChangeType {
  /// The reminder was created; the first change of every reminder.
  create('create'),

  /// The owner edited it from its form (reference criterion, anchor,
  /// title…).
  edit('edit'),

  /// The applied criterion was set or changed, with a reason. Named so in
  /// Dart because `override` is the name of the annotation.
  applyOverride('override'),

  /// The override was removed: the reference criterion applies again.
  restoreReference('restoreReference'),

  /// This occurrence was postponed, with a reason.
  snooze('snooze'),

  /// The postponement was removed.
  unsnooze('unsnooze'),

  /// A recurring reminder was closed by an entry: its anchor moved.
  close('close'),

  /// A one-shot reminder was closed by an entry: it is completed.
  complete('complete');

  const ReminderChangeType(this.code);

  /// Text stored in `reminder_changes.change_type`.
  final String code;

  /// The type stored as [code], or `null` when the code is unknown.
  static ReminderChangeType? fromCode(String code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

/// The per-vehicle criterion the owner wants to be warned about
/// (`Docs/08_recordatorios.md`): a recurring maintenance or legal item, or
/// a one-shot deadline.
///
/// Two layers, never merged: the reference criterion (`ref*`, what the
/// manual says) and, while [overrideActive], the applied one (`applied*`),
/// set consciously with a reason. Its status is never stored: see
/// `evaluateReminder`.
///
/// Immutable snapshot. Created and changed only through
/// `ReminderRepository`.
class Reminder {
  /// Creates a reminder snapshot. Normally called by the repository only.
  const Reminder({
    required this.id,
    required this.vehicleId,
    required this.kind,
    required this.title,
    this.note,
    this.source = ReminderSource.manual,
    this.manualRef,
    this.refIntervalKm,
    this.refIntervalMonths,
    this.dueDate,
    this.lastDoneDate,
    this.lastDoneKm,
    this.lastEntryId,
    this.overrideActive = false,
    this.appliedIntervalKm,
    this.appliedIntervalMonths,
    this.overrideReason,
    this.overrideAt,
    this.leadDays,
    this.leadKm,
    this.snoozeUntilDate,
    this.snoozeUntilKm,
    this.snoozeReason,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Device-generated UUID v4.
  final String id;

  /// Id of the vehicle the reminder belongs to.
  final String vehicleId;

  /// What the reminder is about.
  final ReminderKind kind;

  /// Shown everywhere; the form prefills it with the kind's name.
  final String title;

  /// Free text: severe-use intervals, what the manual says…
  final String? note;

  /// Typed in the app or loaded from the manual.
  final ReminderSource source;

  /// Where in the manual it comes from, e.g. "p. 174".
  final String? manualRef;

  /// Reference interval in km (SI); `null` when there is no km axis.
  final double? refIntervalKm;

  /// Reference interval in months; `null` when there is no time axis.
  final int? refIntervalMonths;

  /// Due day of a one-shot reminder; `null` on a recurring one. A recurring
  /// reminder has at least one reference interval instead.
  final CalendarDate? dueDate;

  /// Anchor: day of the last intervention. Always set on a recurring
  /// reminder.
  final CalendarDate? lastDoneDate;

  /// Anchor: km of the last intervention; set whenever a km axis exists.
  final double? lastDoneKm;

  /// The entry that last closed it, for information: the anchor is a copy
  /// of its values, never derived from it.
  final String? lastEntryId;

  /// Whether the owner overrode the reference criterion.
  final bool overrideActive;

  /// Applied km interval while [overrideActive]; `null` then means the km
  /// axis is disabled.
  final double? appliedIntervalKm;

  /// Applied months interval while [overrideActive]; `null` then means the
  /// time axis is disabled.
  final int? appliedIntervalMonths;

  /// Why the owner overrode the reference.
  final String? overrideReason;

  /// When the override was set, in UTC.
  final DateTime? overrideAt;

  /// Days of warning before the due date; `null` uses the global setting.
  final int? leadDays;

  /// Km of warning before the due km; `null` uses the global setting.
  final double? leadKm;

  /// This occurrence postponed to this day.
  final CalendarDate? snoozeUntilDate;

  /// This occurrence postponed to this km.
  final double? snoozeUntilKm;

  /// Why it was postponed.
  final String? snoozeReason;

  /// When a one-shot reminder was closed, in UTC; `null` while open.
  final DateTime? completedAt;

  /// When the reminder was created, in UTC.
  final DateTime createdAt;

  /// When the reminder was last modified, in UTC.
  final DateTime updatedAt;

  /// Whether this is a one-shot deadline rather than a recurring item.
  bool get isOneShot => dueDate != null;

  /// Whether this one-shot reminder has been closed.
  bool get isCompleted => completedAt != null;

  /// Whether this occurrence is postponed on at least one axis.
  bool get isSnoozed => snoozeUntilDate != null || snoozeUntilKm != null;

  /// The km interval in use: the applied one while [overrideActive].
  double? get intervalKm => overrideActive ? appliedIntervalKm : refIntervalKm;

  /// The months interval in use: the applied one while [overrideActive].
  int? get intervalMonths =>
      overrideActive ? appliedIntervalMonths : refIntervalMonths;

  /// Whether it has a km interval, reference or applied, whether or not the
  /// override is active: closing it then needs the entry's km, since the
  /// table requires a km anchor whenever either interval exists.
  bool get usesKm => refIntervalKm != null || appliedIntervalKm != null;

  /// Returns a copy with the given fields replaced. Nullable fields can be
  /// cleared by passing `null` explicitly.
  Reminder copyWith({
    ReminderKind? kind,
    String? title,
    Object? note = unset,
    Object? manualRef = unset,
    Object? refIntervalKm = unset,
    Object? refIntervalMonths = unset,
    Object? dueDate = unset,
    Object? lastDoneDate = unset,
    Object? lastDoneKm = unset,
    Object? lastEntryId = unset,
    bool? overrideActive,
    Object? appliedIntervalKm = unset,
    Object? appliedIntervalMonths = unset,
    Object? overrideReason = unset,
    Object? overrideAt = unset,
    Object? leadDays = unset,
    Object? leadKm = unset,
    Object? snoozeUntilDate = unset,
    Object? snoozeUntilKm = unset,
    Object? snoozeReason = unset,
    Object? completedAt = unset,
    DateTime? updatedAt,
  }) {
    T? pick<T>(Object? value, T? current) =>
        identical(value, unset) ? current : value as T?;
    // A distance may be passed as a whole number (`leadKm: 500`).
    double? pickKm(Object? value, double? current) =>
        identical(value, unset) ? current : (value as num?)?.toDouble();
    return Reminder(
      id: id,
      vehicleId: vehicleId,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      note: pick(note, this.note),
      source: source,
      manualRef: pick(manualRef, this.manualRef),
      refIntervalKm: pickKm(refIntervalKm, this.refIntervalKm),
      refIntervalMonths: pick(refIntervalMonths, this.refIntervalMonths),
      dueDate: pick(dueDate, this.dueDate),
      lastDoneDate: pick(lastDoneDate, this.lastDoneDate),
      lastDoneKm: pickKm(lastDoneKm, this.lastDoneKm),
      lastEntryId: pick(lastEntryId, this.lastEntryId),
      overrideActive: overrideActive ?? this.overrideActive,
      appliedIntervalKm: pickKm(appliedIntervalKm, this.appliedIntervalKm),
      appliedIntervalMonths: pick(
        appliedIntervalMonths,
        this.appliedIntervalMonths,
      ),
      overrideReason: pick(overrideReason, this.overrideReason),
      overrideAt: pick(overrideAt, this.overrideAt),
      leadDays: pick(leadDays, this.leadDays),
      leadKm: pickKm(leadKm, this.leadKm),
      snoozeUntilDate: pick(snoozeUntilDate, this.snoozeUntilDate),
      snoozeUntilKm: pickKm(snoozeUntilKm, this.snoozeUntilKm),
      snoozeReason: pick(snoozeReason, this.snoozeReason),
      completedAt: pick(completedAt, this.completedAt),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Every field, in declaration order, for [==] and [hashCode].
  List<Object?> get _fields => [
        id,
        vehicleId,
        kind,
        title,
        note,
        source,
        manualRef,
        refIntervalKm,
        refIntervalMonths,
        dueDate,
        lastDoneDate,
        lastDoneKm,
        lastEntryId,
        overrideActive,
        appliedIntervalKm,
        appliedIntervalMonths,
        overrideReason,
        overrideAt,
        leadDays,
        leadKm,
        snoozeUntilDate,
        snoozeUntilKm,
        snoozeReason,
        completedAt,
        createdAt,
        updatedAt,
      ];

  @override
  bool operator ==(Object other) {
    if (other is! Reminder) return false;
    final mine = _fields;
    final theirs = other._fields;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_fields);

  @override
  String toString() => 'Reminder(id: $id, vehicleId: $vehicleId, '
      'kind: ${kind.code}, title: $title, refKm: $refIntervalKm, '
      'refMonths: $refIntervalMonths, due: ${dueDate?.toIso8601String()}, '
      'lastDone: ${lastDoneDate?.toIso8601String()} / $lastDoneKm, '
      'override: $overrideActive ($appliedIntervalKm, '
      '$appliedIntervalMonths), completedAt: $completedAt)';
}

/// The user-editable fields of a reminder, as the form sends them to
/// `ReminderRepository.create` and `update`.
///
/// The applied criterion, the snooze and the closing state are not here:
/// they have their own actions.
class ReminderDraft {
  /// Creates the draft.
  const ReminderDraft({
    required this.kind,
    required this.title,
    this.note,
    this.manualRef,
    this.refIntervalKm,
    this.refIntervalMonths,
    this.dueDate,
    this.lastDoneDate,
    this.lastDoneKm,
    this.leadDays,
    this.leadKm,
  });

  /// What the reminder is about.
  final ReminderKind kind;

  /// Title, trimmed by the repository; never blank.
  final String title;

  /// Free note.
  final String? note;

  /// Where in the manual it comes from.
  final String? manualRef;

  /// Reference km interval of a recurring reminder.
  final double? refIntervalKm;

  /// Reference months interval of a recurring reminder.
  final int? refIntervalMonths;

  /// Due day of a one-shot reminder.
  final CalendarDate? dueDate;

  /// Anchor day; required on a recurring reminder.
  final CalendarDate? lastDoneDate;

  /// Anchor km; required with a km interval.
  final double? lastDoneKm;

  /// Per-reminder lead in days; `null` uses the global setting.
  final int? leadDays;

  /// Per-reminder lead in km; `null` uses the global setting.
  final double? leadKm;
}

/// One row of a reminder's append-only history: what changed, when, why,
/// and the reminder's state right after the change (the state before is
/// the previous row).
class ReminderChange {
  /// Creates a change. Normally called by the repository only.
  const ReminderChange({
    required this.id,
    required this.reminderId,
    required this.changedAt,
    required this.type,
    this.reason,
    this.entryId,
    this.dueDate,
    this.lastDoneDate,
    this.lastDoneKm,
    this.refIntervalKm,
    this.refIntervalMonths,
    this.overrideActive = false,
    this.appliedIntervalKm,
    this.appliedIntervalMonths,
    this.snoozeUntilDate,
    this.snoozeUntilKm,
  });

  /// The change of [type] that left [reminder] as it is, at [at].
  factory ReminderChange.of(
    Reminder reminder, {
    required String id,
    required ReminderChangeType type,
    required DateTime at,
    String? reason,
    String? entryId,
  }) =>
      ReminderChange(
        id: id,
        reminderId: reminder.id,
        changedAt: at,
        type: type,
        reason: reason,
        entryId: entryId,
        dueDate: reminder.dueDate,
        lastDoneDate: reminder.lastDoneDate,
        lastDoneKm: reminder.lastDoneKm,
        refIntervalKm: reminder.refIntervalKm,
        refIntervalMonths: reminder.refIntervalMonths,
        overrideActive: reminder.overrideActive,
        appliedIntervalKm: reminder.appliedIntervalKm,
        appliedIntervalMonths: reminder.appliedIntervalMonths,
        snoozeUntilDate: reminder.snoozeUntilDate,
        snoozeUntilKm: reminder.snoozeUntilKm,
      );

  /// Device-generated UUID v4.
  final String id;

  /// The reminder it belongs to.
  final String reminderId;

  /// When it happened, in UTC.
  final DateTime changedAt;

  /// What happened.
  final ReminderChangeType type;

  /// The owner's words, for an override or a snooze.
  final String? reason;

  /// The entry of a close or a complete.
  final String? entryId;

  /// Snapshot: due day of a one-shot reminder.
  final CalendarDate? dueDate;

  /// Snapshot: anchor day.
  final CalendarDate? lastDoneDate;

  /// Snapshot: anchor km.
  final double? lastDoneKm;

  /// Snapshot: reference km interval.
  final double? refIntervalKm;

  /// Snapshot: reference months interval.
  final int? refIntervalMonths;

  /// Snapshot: whether the override was active.
  final bool overrideActive;

  /// Snapshot: applied km interval.
  final double? appliedIntervalKm;

  /// Snapshot: applied months interval.
  final int? appliedIntervalMonths;

  /// Snapshot: postponed to this day.
  final CalendarDate? snoozeUntilDate;

  /// Snapshot: postponed to this km.
  final double? snoozeUntilKm;

  @override
  bool operator ==(Object other) =>
      other is ReminderChange &&
      other.id == id &&
      other.reminderId == reminderId &&
      other.changedAt == changedAt &&
      other.type == type &&
      other.reason == reason &&
      other.entryId == entryId &&
      other.dueDate == dueDate &&
      other.lastDoneDate == lastDoneDate &&
      other.lastDoneKm == lastDoneKm &&
      other.refIntervalKm == refIntervalKm &&
      other.refIntervalMonths == refIntervalMonths &&
      other.overrideActive == overrideActive &&
      other.appliedIntervalKm == appliedIntervalKm &&
      other.appliedIntervalMonths == appliedIntervalMonths &&
      other.snoozeUntilDate == snoozeUntilDate &&
      other.snoozeUntilKm == snoozeUntilKm;

  @override
  int get hashCode => Object.hash(
        id,
        reminderId,
        changedAt,
        type,
        reason,
        entryId,
        dueDate,
        lastDoneDate,
        lastDoneKm,
        refIntervalKm,
        refIntervalMonths,
        overrideActive,
        appliedIntervalKm,
        appliedIntervalMonths,
        snoozeUntilDate,
        snoozeUntilKm,
      );

  @override
  String toString() => 'ReminderChange(${type.code}, $changedAt, '
      'reminder: $reminderId)';
}

/// A live, open reminder of an active vehicle, with that vehicle: a row of
/// the Reminders page of Home.
class ActiveReminder {
  /// Creates the pair.
  const ActiveReminder({required this.reminder, required this.vehicle});

  /// The reminder.
  final Reminder reminder;

  /// Its vehicle, for the make, model, plate and current odometer.
  final Vehicle vehicle;

  @override
  bool operator ==(Object other) =>
      other is ActiveReminder &&
      other.reminder == reminder &&
      other.vehicle == vehicle;

  @override
  int get hashCode => Object.hash(reminder, vehicle);
}
