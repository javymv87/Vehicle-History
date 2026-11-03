import 'package:drift/drift.dart';

import 'converters.dart';
import 'log_entries_table.dart';
import 'technical_columns.dart';
import 'vehicles_table.dart';

/// The `reminders` table (schema v11): what the owner wants to be warned
/// about on a vehicle (`Docs/08_recordatorios.md`).
///
/// A recurring reminder has a reference interval (km and / or months) and an
/// anchor; a one-shot reminder has a due date instead. The applied criterion
/// (`applied_*`) only counts while `override_active`. Status is never
/// stored. Every constraint is a table constraint: the table was created
/// whole in v11, never altered.
///
/// The partial unique index keeps one live, open reminder per kind and
/// vehicle (`Docs/04_maintenance_logic.md`), except for the two "other"
/// kinds. The repository checks the same rule first; the index is the
/// safety net for writers outside the app (the loading procedure).
@DataClassName('ReminderRow')
@TableIndex(name: 'reminders_vehicle_deleted', columns: {#vehicleId, #deleted})
@TableIndex(name: 'reminders_vehicle_kind', columns: {#vehicleId, #kind})
@TableIndex.sql(
  'CREATE UNIQUE INDEX reminders_one_per_kind '
  'ON reminders (vehicle_id, kind) '
  'WHERE deleted = 0 AND completed_at IS NULL '
  "AND kind NOT IN ('other', 'other_document')",
)
class Reminders extends Table with TechnicalColumns {
  /// Vehicle the reminder belongs to.
  TextColumn get vehicleId =>
      text().references(Vehicles, #id, onDelete: KeyAction.restrict)();

  /// What it is about, as a `ReminderKind` code.
  TextColumn get kind => text().map(const ReminderKindConverter())();

  /// Title shown everywhere. Never blank.
  TextColumn get title => text()();

  /// Free note.
  TextColumn get note => text().nullable()();

  /// `manual` or `generated` (`ReminderSource`).
  TextColumn get source => text().map(const ReminderSourceConverter())();

  /// Where in the manual it comes from.
  TextColumn get manualRef => text().nullable()();

  /// Reference interval in km.
  RealColumn get refIntervalKm => real().nullable()();

  /// Reference interval in months.
  IntColumn get refIntervalMonths => integer().nullable()();

  /// Due day of a one-shot reminder, `yyyy-MM-dd`.
  TextColumn get dueDate =>
      text().map(const CalendarDateConverter()).nullable()();

  /// Anchor day: the last intervention, `yyyy-MM-dd`.
  TextColumn get lastDoneDate =>
      text().map(const CalendarDateConverter()).nullable()();

  /// Anchor km: the last intervention.
  RealColumn get lastDoneKm => real().nullable()();

  /// The entry that last closed it; cleared if that entry is removed from
  /// disk. Informative only: the anchor is a copy.
  TextColumn get lastEntryId => text()
      .nullable()
      .references(LogEntries, #id, onDelete: KeyAction.setNull)();

  /// Whether the applied criterion replaces the reference one.
  BoolColumn get overrideActive =>
      boolean().withDefault(const Constant(false))();

  /// Applied km interval; `NULL` with the override active = axis disabled.
  RealColumn get appliedIntervalKm => real().nullable()();

  /// Applied months interval; `NULL` with the override active = axis
  /// disabled.
  IntColumn get appliedIntervalMonths => integer().nullable()();

  /// Why the reference was overridden.
  TextColumn get overrideReason => text().nullable()();

  /// When the override was set, UTC.
  DateTimeColumn get overrideAt => dateTime().nullable()();

  /// Per-reminder lead in days.
  IntColumn get leadDays => integer().nullable()();

  /// Per-reminder lead in km.
  RealColumn get leadKm => real().nullable()();

  /// Postponed to this day.
  TextColumn get snoozeUntilDate =>
      text().map(const CalendarDateConverter()).nullable()();

  /// Postponed to this km.
  RealColumn get snoozeUntilKm => real().nullable()();

  /// Why it was postponed.
  TextColumn get snoozeReason => text().nullable()();

  /// When a one-shot reminder was closed, UTC.
  DateTimeColumn get completedAt => dateTime().nullable()();

  // Written as SQL rather than with `Column.check`, whose self-referencing
  // getter trips the `recursive_getters` lint. A NULL value passes a CHECK.
  @override
  List<String> get customConstraints => [
        'CHECK (length(trim(title)) > 0)',
        'CHECK (ref_interval_km > 0)',
        'CHECK (ref_interval_months > 0)',
        'CHECK (last_done_km >= 0)',
        'CHECK (applied_interval_km > 0)',
        'CHECK (applied_interval_months > 0)',
        'CHECK (lead_days >= 0)',
        'CHECK (lead_km >= 0)',
        // Recurring (an interval) xor one-shot (a due date).
        'CHECK ((due_date IS NULL) = '
            '(ref_interval_km IS NOT NULL OR ref_interval_months IS NOT NULL))',
        // A recurring reminder has an anchor day, and a km anchor whenever a
        // km axis exists, reference or applied.
        'CHECK (due_date IS NOT NULL OR last_done_date IS NOT NULL)',
        'CHECK (ref_interval_km IS NULL OR last_done_km IS NOT NULL)',
        'CHECK (applied_interval_km IS NULL OR last_done_km IS NOT NULL)',
        // An override never disables both axes.
        'CHECK (override_active = 0 OR applied_interval_km IS NOT NULL '
            'OR applied_interval_months IS NOT NULL)',
        // Only a one-shot reminder completes.
        'CHECK (completed_at IS NULL OR due_date IS NOT NULL)',
      ];
}

/// The `reminder_changes` table (schema v11): the append-only history of
/// each reminder, like `audit_log`, so the owner can see why every criterion
/// decision was taken.
///
/// Each row holds the reminder's state **after** the change. Written by the
/// repository in the same transaction as the reminder write it describes;
/// no `deleted` flag, no `updated_at`. Removed from disk only with its
/// reminder.
@DataClassName('ReminderChangeRow')
@TableIndex(
  name: 'reminder_changes_reminder_at',
  columns: {#reminderId, #changedAt},
)
class ReminderChanges extends Table {
  /// Device-generated UUID v4, the primary key.
  TextColumn get id => text()();

  /// The reminder it belongs to.
  TextColumn get reminderId =>
      text().references(Reminders, #id, onDelete: KeyAction.restrict)();

  /// When it happened, UTC.
  DateTimeColumn get changedAt => dateTime()();

  /// What happened, as a `ReminderChangeType` code.
  TextColumn get changeType =>
      text().map(const ReminderChangeTypeConverter())();

  /// The owner's words (override, snooze).
  TextColumn get reason => text().nullable()();

  /// The entry of a close or a complete; no foreign key, so the history
  /// outlives the entry.
  TextColumn get entryId => text().nullable()();

  /// Snapshot: due day of a one-shot reminder.
  TextColumn get dueDate =>
      text().map(const CalendarDateConverter()).nullable()();

  /// Snapshot: anchor day.
  TextColumn get lastDoneDate =>
      text().map(const CalendarDateConverter()).nullable()();

  /// Snapshot: anchor km.
  RealColumn get lastDoneKm => real().nullable()();

  /// Snapshot: reference km interval.
  RealColumn get refIntervalKm => real().nullable()();

  /// Snapshot: reference months interval.
  IntColumn get refIntervalMonths => integer().nullable()();

  /// Snapshot: whether the override was active.
  BoolColumn get overrideActive => boolean()();

  /// Snapshot: applied km interval.
  RealColumn get appliedIntervalKm => real().nullable()();

  /// Snapshot: applied months interval.
  IntColumn get appliedIntervalMonths => integer().nullable()();

  /// Snapshot: postponed to this day.
  TextColumn get snoozeUntilDate =>
      text().map(const CalendarDateConverter()).nullable()();

  /// Snapshot: postponed to this km.
  RealColumn get snoozeUntilKm => real().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
