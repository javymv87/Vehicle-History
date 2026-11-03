import '../db/daos/audit_log_dao.dart';
import '../db/daos/reminders_dao.dart';
import '../db/vehicle_state.dart';
import '../models/audit_entry.dart';
import '../models/calendar_date.dart';
import '../models/log_entry.dart';
import '../models/log_entry_type.dart';
import '../models/reminder.dart';
import 'repository_exceptions.dart';
import 'repository_support.dart';

/// Closes a reminder with an entry (`Docs/08_recordatorios.md`): the only
/// way a recurring reminder moves on, and how a one-shot one completes.
///
/// Shared by `ReminderRepository` (close, mark done) and
/// `LogEntryRepository` (the "Closes the reminder" field of the entry form),
/// so the entry and the close land in one transaction without the two
/// repositories depending on each other. Never opens a transaction itself:
/// call [close] inside the caller's.
class ReminderCloser {
  /// Creates the closer on [_reminders], auditing through [_audit].
  ReminderCloser(this._reminders, this._audit);

  /// Reminder queries.
  final RemindersDao _reminders;

  /// Audit log writes, joined to the caller's transaction.
  final AuditLogDao _audit;

  /// Checks that an entry of [type] dated [date] with [km], on the vehicle
  /// [vehicleId], can close [reminder] on [today]. Pure, so the entry form
  /// can show the same refusals inline.
  ///
  /// Throws [ReminderRuleException] when the reminder is completed, the
  /// entry belongs to another vehicle or its type cannot close the kind;
  /// [InvalidFieldException] when the entry is dated after today or before
  /// the anchor day (the same day is accepted), has fewer km than the anchor
  /// km, or has no km while the reminder has a km interval.
  static void checkEntry(
    Reminder reminder, {
    required String vehicleId,
    required LogEntryType type,
    required CalendarDate date,
    required double? km,
    required CalendarDate today,
  }) {
    if (reminder.isCompleted) {
      throw ReminderRuleException(reminder.id, ReminderRule.completed);
    }
    if (vehicleId != reminder.vehicleId) {
      throw ReminderRuleException(
        reminder.id,
        ReminderRule.entryOfOtherVehicle,
      );
    }
    if (!reminder.kind.closingEntryTypes.contains(type)) {
      throw ReminderRuleException(
        reminder.id,
        ReminderRule.entryTypeCannotClose,
      );
    }
    if (date.isAfter(today)) {
      throw const InvalidFieldException('date', InvalidFieldException.inFuture);
    }
    final anchorDate = reminder.lastDoneDate;
    if (anchorDate != null && date.isBefore(anchorDate)) {
      throw const InvalidFieldException(
        'date',
        InvalidFieldException.beforeAnchor,
      );
    }
    if (km == null && reminder.usesKm) {
      throw const InvalidFieldException('km', InvalidFieldException.required);
    }
    final anchorKm = reminder.lastDoneKm;
    if (km != null && anchorKm != null && km < anchorKm) {
      throw const InvalidFieldException(
        'km',
        InvalidFieldException.belowAnchor,
      );
    }
  }

  /// Closes the reminder [reminderId] with the live [entry] at [now], on
  /// [today], and returns it as written.
  ///
  /// A recurring reminder takes the entry's day and km as its new anchor (a
  /// copy: editing the entry later never moves it), the entry as
  /// `last_entry_id`, and loses its snooze; the override stays. A one-shot
  /// reminder is completed instead (`completed_at = now`, the entry as
  /// `last_entry_id`, snooze cleared). Writes the `close` or `complete`
  /// change and the `update` audit row.
  ///
  /// Throws [EntityNotFoundException] when the reminder or its vehicle is
  /// missing or deleted, [VehicleArchivedException] when the vehicle is
  /// archived, and what [checkEntry] throws.
  Future<Reminder> close(
    String reminderId,
    LogEntry entry, {
    required DateTime now,
    required CalendarDate today,
  }) async {
    final reminder = await _reminders.getLiveById(reminderId);
    if (reminder == null) {
      throw EntityNotFoundException(AuditEntityType.reminder, reminderId);
    }
    switch (await _reminders.vehicleStateOf(reminder.vehicleId)) {
      case VehicleState.active:
        break;
      case VehicleState.archived:
        throw VehicleArchivedException(AuditEntityType.reminder, reminderId);
      case VehicleState.absent:
        throw EntityNotFoundException(
          AuditEntityType.vehicle,
          reminder.vehicleId,
        );
    }
    checkEntry(
      reminder,
      vehicleId: entry.vehicleId,
      type: entry.type,
      date: entry.date,
      km: entry.km,
      today: today,
    );
    final cleared = reminder.copyWith(
      lastEntryId: entry.id,
      snoozeUntilDate: null,
      snoozeUntilKm: null,
      snoozeReason: null,
      updatedAt: now,
    );
    final closed = reminder.isOneShot
        ? cleared.copyWith(completedAt: now)
        : cleared.copyWith(lastDoneDate: entry.date, lastDoneKm: entry.km);
    await _reminders.updateLive(closed);
    await _reminders.insertChange(
      ReminderChange.of(
        closed,
        id: newId(),
        type: reminder.isOneShot
            ? ReminderChangeType.complete
            : ReminderChangeType.close,
        at: now,
        entryId: entry.id,
      ),
    );
    await _audit.insertEntry(
      AuditEntry(
        id: newId(),
        entityType: AuditEntityType.reminder,
        entityId: reminderId,
        operation: AuditOperation.update,
        at: now,
      ),
    );
    return closed;
  }
}
