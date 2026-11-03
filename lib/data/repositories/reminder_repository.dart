import '../models/calendar_date.dart';
import '../models/log_entry.dart';
import '../models/log_entry_type.dart';
import '../models/reminder.dart';

/// The only access path to persisted reminders and their history
/// (`Docs/08_recordatorios.md`).
///
/// Reads return live reminders of live vehicles only. Every write checks
/// that the vehicle is active (an archived vehicle is read-only:
/// `VehicleArchivedException`), adds its `audit_log` row and its
/// `reminder_changes` row, all in one transaction. Status is never stored:
/// see `evaluateReminder`. Errors are `RepositoryException` subtypes.
abstract interface class ReminderRepository {
  /// Emits the live reminders of the vehicle [vehicleId], completed ones
  /// included, now and after every change; empty for a missing or deleted
  /// vehicle.
  Stream<List<Reminder>> watchByVehicle(String vehicleId);

  /// Returns what [watchByVehicle] emits, once.
  Future<List<Reminder>> getByVehicle(String vehicleId);

  /// Emits the live, open reminders of every active vehicle (live and not
  /// archived), each with its vehicle: the Reminders page of Home and its
  /// badge.
  Stream<List<ActiveReminder>> watchActiveAcrossVehicles();

  /// Returns the live reminder with [id], or `null` if it is missing,
  /// deleted or belongs to a deleted vehicle.
  Future<Reminder?> getById(String id);

  /// Emits what [getById] returns, now and after every change.
  Stream<Reminder?> watchById(String id);

  /// Emits the history of the reminder [reminderId], newest first.
  Stream<List<ReminderChange>> watchChanges(String reminderId);

  /// Emits the ids of the entries of the vehicle [vehicleId] that are the
  /// last closing entry of a live reminder (the history-row icon).
  Stream<Set<String>> watchClosingEntryIds(String vehicleId);

  /// Emits the live reminders whose last closing entry is [entryId].
  Stream<List<Reminder>> watchClosedBy(String entryId);

  /// Emits the live, open reminders of the vehicle [vehicleId] that an
  /// entry of [type] can close (`ReminderKind.closingEntryTypes`).
  Stream<List<Reminder>> watchClosable(String vehicleId, LogEntryType type);

  /// Creates a reminder from [draft] on the active vehicle [vehicleId],
  /// with source `manual`, and returns it.
  ///
  /// Throws `InvalidFieldException` for a blank title, an interval or lead
  /// out of range, a one-shot reminder with an interval, a recurring one
  /// without interval or anchor day, a km interval without anchor km, or an
  /// anchor day after today; `ReminderKindAlreadyUsedException` when the
  /// vehicle already has a live, open reminder of a unique kind;
  /// `EntityNotFoundException` / `VehicleArchivedException` for the vehicle.
  Future<Reminder> create({
    required String vehicleId,
    required ReminderDraft draft,
  });

  /// Replaces the user-editable fields of the reminder [id] with [draft]
  /// (the reference criterion is the owner's data) and records an `edit`
  /// change. The override, the snooze and the closing state are kept.
  ///
  /// Throws what [create] throws, `ReminderRuleException` for a completed
  /// reminder, and `InvalidFieldException` when it would become one-shot
  /// while overridden.
  Future<Reminder> update(String id, ReminderDraft draft);

  /// Sets or changes the applied criterion of the recurring reminder [id]:
  /// [appliedKm] and / or [appliedMonths] (a `null` axis is disabled, never
  /// both), with a mandatory [reason].
  ///
  /// When [appliedKm] adds a km axis to a reminder with no km anchor,
  /// [anchorKm] (the km of the last time, a fact the owner states) is
  /// required and written as `last_done_km` in the same transaction; it is
  /// refused when an anchor km already exists.
  ///
  /// Throws `ReminderRuleException` for a one-shot or completed reminder,
  /// `InvalidFieldException` for no axis, a value out of range or a blank
  /// reason.
  Future<Reminder> overrideCriterion(
    String id, {
    double? appliedKm,
    int? appliedMonths,
    required String reason,
    double? anchorKm,
  });

  /// Removes the override of the reminder [id]: the reference applies
  /// again. The anchor (`last_done_km` included) and the history are kept.
  ///
  /// Throws `ReminderRuleException` when it is not overridden.
  Future<Reminder> restoreReference(String id);

  /// Postpones this occurrence of the reminder [id] to [untilDate] and / or
  /// [untilKm], with a mandatory [reason], replacing any earlier snooze.
  ///
  /// Each value must be later than the due value of the applied criterion
  /// on its axis, and that axis must have one. Throws
  /// `InvalidFieldException` otherwise, and `ReminderRuleException` for a
  /// completed reminder.
  Future<Reminder> snooze(
    String id, {
    CalendarDate? untilDate,
    double? untilKm,
    required String reason,
  });

  /// Removes the snooze of the reminder [id].
  ///
  /// Throws `ReminderRuleException` when it is not postponed.
  Future<Reminder> unsnooze(String id);

  /// Closes the reminder [id] with the live entry [entryId]
  /// (`ReminderCloser.close` has the rules and the effect).
  Future<Reminder> close(String id, String entryId);

  /// "Mark done": creates the closing entry of the reminder [id] (a
  /// maintenance, or a legal deadline for the legal kinds) on [date], with
  /// [km], [costCents] and [description], and closes the reminder with it,
  /// in one transaction. Returns both.
  ///
  /// Throws what `LogEntryRepository.create` and the close throw; nothing
  /// is written then.
  Future<({LogEntry entry, Reminder reminder})> markDone(
    String id, {
    required CalendarDate date,
    double? km,
    int? costCents,
    String? description,
  });

  /// Soft-deletes the reminder [id]. Deletes nothing else.
  Future<void> delete(String id);

  /// Brings back the soft-deleted reminder [id], as "Undo" after [delete].
  ///
  /// Throws `ReminderKindAlreadyUsedException` when another live, open
  /// reminder of the same unique kind appeared meanwhile, and the vehicle
  /// errors of [create].
  Future<Reminder> restore(String id);
}
