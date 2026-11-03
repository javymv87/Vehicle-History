import '../db/daos/audit_log_dao.dart';
import '../db/daos/reminders_dao.dart';
import '../db/vehicle_state.dart';
import '../models/audit_entry.dart';
import '../models/calendar_date.dart';
import '../models/log_entry.dart';
import '../models/log_entry_type.dart';
import '../models/reminder.dart';
import '../models/reminder_status.dart';
import 'log_entry_repository.dart';
import 'reminder_closer.dart';
import 'reminder_repository.dart';
import 'repository_exceptions.dart';
import 'repository_support.dart';

/// [ReminderRepository] backed by the local Drift database.
class DriftReminderRepository implements ReminderRepository {
  /// Creates the repository on [_reminders], auditing through [_audit].
  ///
  /// [entries] creates the closing entry of "Mark done" and reads the entry
  /// of a close; [closer] applies a close. [clock] must return UTC.
  DriftReminderRepository(
    this._reminders,
    this._audit, {
    required LogEntryRepository entries,
    required ReminderCloser closer,
    UtcClock clock = systemUtcClock,
  })  : _entries = entries,
        _closer = closer,
        _clock = clock;

  /// Reminder queries.
  final RemindersDao _reminders;

  /// Audit log writes, joined to the same transaction as each change.
  final AuditLogDao _audit;

  /// The entries, for "Mark done" and for the entry of a close.
  final LogEntryRepository _entries;

  /// The close shared with the entry repository.
  final ReminderCloser _closer;

  /// Source of every instant written.
  final UtcClock _clock;

  @override
  Stream<List<Reminder>> watchByVehicle(String vehicleId) =>
      _reminders.watchLiveByVehicle(vehicleId);

  @override
  Future<List<Reminder>> getByVehicle(String vehicleId) =>
      _reminders.getLiveByVehicle(vehicleId);

  @override
  Stream<List<ActiveReminder>> watchActiveAcrossVehicles() =>
      _reminders.watchOpenOfActiveVehicles();

  @override
  Future<Reminder?> getById(String id) => _reminders.getLiveById(id);

  @override
  Stream<Reminder?> watchById(String id) => _reminders.watchLiveById(id);

  @override
  Stream<List<ReminderChange>> watchChanges(String reminderId) =>
      _reminders.watchChanges(reminderId);

  @override
  Stream<Set<String>> watchClosingEntryIds(String vehicleId) =>
      _reminders.watchClosingEntryIds(vehicleId);

  @override
  Future<bool> hasBeenClosed(String id) => _reminders.hasBeenClosed(id);

  @override
  Stream<List<Reminder>> watchClosedBy(String entryId) =>
      _reminders.watchClosedBy(entryId);

  @override
  Stream<List<Reminder>> watchClosable(String vehicleId, LogEntryType type) =>
      _reminders.watchLiveByVehicle(vehicleId).map(
            (reminders) => [
              for (final reminder in reminders)
                if (!reminder.isCompleted &&
                    reminder.kind.closingEntryTypes.contains(type))
                  reminder,
            ],
          );

  @override
  Future<Reminder> create({
    required String vehicleId,
    required ReminderDraft draft,
  }) async {
    final now = utcNow(_clock);
    final reminder = _applyDraft(
      Reminder(
        id: newId(),
        vehicleId: vehicleId,
        kind: draft.kind,
        title: draft.title,
        createdAt: now,
        updatedAt: now,
      ),
      draft,
      now,
    );
    _checkCriterion(reminder, localToday(_clock));
    return _reminders.transaction(() async {
      await _requireActiveVehicle(vehicleId, reminder.id);
      await _requireKindFree(reminder);
      await _reminders.insertReminder(reminder);
      await _recordChange(reminder, ReminderChangeType.create, now);
      await _record(reminder.id, AuditOperation.create, now);
      return reminder;
    });
  }

  @override
  Future<Reminder> update(String id, ReminderDraft draft) async {
    final now = utcNow(_clock);
    final today = localToday(_clock);
    return _reminders.transaction(() async {
      final current = await _requireWritable(id);
      final updated = _applyDraft(current, draft, now);
      if ((updated.kind != current.kind ||
              updated.isOneShot != current.isOneShot) &&
          await _reminders.hasBeenClosed(id)) {
        // Its closes belong to this kind and mode: another one is a new
        // reminder.
        throw ReminderRuleException(id, ReminderRule.alreadyClosed);
      }
      _checkCriterion(updated, today);
      if (updated.isOneShot && updated.overrideActive) {
        // A one-shot reminder has no criterion to override.
        throw const InvalidFieldException(
          'dueDate',
          'not while the criterion is overridden',
        );
      }
      await _requireKindFree(updated);
      await _reminders.updateLive(updated);
      await _recordChange(updated, ReminderChangeType.edit, now);
      await _record(id, AuditOperation.update, now);
      return updated;
    });
  }

  @override
  Future<Reminder> overrideCriterion(
    String id, {
    double? appliedKm,
    int? appliedMonths,
    required String reason,
    double? anchorKm,
  }) async {
    final now = utcNow(_clock);
    if (appliedKm == null && appliedMonths == null) {
      throw const InvalidFieldException(
        'appliedIntervalKm',
        'at least one axis must stay enabled',
      );
    }
    _checkPositive('appliedIntervalKm', appliedKm);
    _checkPositive('appliedIntervalMonths', appliedMonths);
    final why = requireText(reason, 'overrideReason');
    return _reminders.transaction(() async {
      final current = await _requireWritable(id);
      if (current.isOneShot) {
        throw ReminderRuleException(id, ReminderRule.oneShot);
      }
      var lastDoneKm = current.lastDoneKm;
      if (anchorKm != null && lastDoneKm != null) {
        throw const InvalidFieldException('lastDoneKm', 'already recorded');
      }
      if (appliedKm != null && lastDoneKm == null) {
        // A new km axis needs the km of the last time: a fact the owner
        // states, never assumed.
        if (anchorKm == null) {
          throw const InvalidFieldException(
            'lastDoneKm',
            InvalidFieldException.required,
          );
        }
        _checkNonNegative('lastDoneKm', anchorKm);
        lastDoneKm = anchorKm;
      }
      final updated = current.copyWith(
        overrideActive: true,
        appliedIntervalKm: appliedKm,
        appliedIntervalMonths: appliedMonths,
        overrideReason: why,
        overrideAt: now,
        lastDoneKm: lastDoneKm,
        updatedAt: now,
      );
      await _reminders.updateLive(updated);
      await _recordChange(
        updated,
        ReminderChangeType.applyOverride,
        now,
        reason: why,
      );
      await _record(id, AuditOperation.update, now);
      return updated;
    });
  }

  @override
  Future<Reminder> restoreReference(String id) async {
    final now = utcNow(_clock);
    return _reminders.transaction(() async {
      final current = await _requireWritable(id);
      if (!current.overrideActive) {
        throw ReminderRuleException(id, ReminderRule.notOverridden);
      }
      // The anchor stays as it is, `last_done_km` included: it is a fact.
      final updated = current.copyWith(
        overrideActive: false,
        appliedIntervalKm: null,
        appliedIntervalMonths: null,
        overrideReason: null,
        overrideAt: null,
        updatedAt: now,
      );
      await _reminders.updateLive(updated);
      await _recordChange(updated, ReminderChangeType.restoreReference, now);
      await _record(id, AuditOperation.update, now);
      return updated;
    });
  }

  @override
  Future<Reminder> snooze(
    String id, {
    CalendarDate? untilDate,
    double? untilKm,
    required String reason,
  }) async {
    final now = utcNow(_clock);
    if (untilDate == null && untilKm == null) {
      throw const InvalidFieldException(
        'snoozeUntilDate',
        'at least one axis is required',
      );
    }
    if (untilKm != null && !untilKm.isFinite) {
      throw const InvalidFieldException('snoozeUntilKm', 'must be a number');
    }
    final why = requireText(reason, 'snoozeReason');
    return _reminders.transaction(() async {
      final current = await _requireWritable(id);
      // Compared with the due value of the applied criterion, never with
      // the reference nor with an earlier snooze.
      if (untilDate != null) {
        final due = reminderDueDate(current);
        if (due == null) {
          throw const InvalidFieldException(
            'snoozeUntilDate',
            'no due date on this axis',
          );
        }
        if (!untilDate.isAfter(due)) {
          throw const InvalidFieldException(
            'snoozeUntilDate',
            InvalidFieldException.notLater,
          );
        }
      }
      if (untilKm != null) {
        final due = reminderDueKm(current);
        if (due == null) {
          throw const InvalidFieldException(
            'snoozeUntilKm',
            'no due km on this axis',
          );
        }
        if (untilKm <= due) {
          throw const InvalidFieldException(
            'snoozeUntilKm',
            InvalidFieldException.notLater,
          );
        }
      }
      final updated = current.copyWith(
        snoozeUntilDate: untilDate,
        snoozeUntilKm: untilKm,
        snoozeReason: why,
        updatedAt: now,
      );
      await _reminders.updateLive(updated);
      await _recordChange(updated, ReminderChangeType.snooze, now, reason: why);
      await _record(id, AuditOperation.update, now);
      return updated;
    });
  }

  @override
  Future<Reminder> unsnooze(String id) async {
    final now = utcNow(_clock);
    return _reminders.transaction(() async {
      final current = await _requireWritable(id);
      if (!current.isSnoozed) {
        throw ReminderRuleException(id, ReminderRule.notSnoozed);
      }
      final updated = current.copyWith(
        snoozeUntilDate: null,
        snoozeUntilKm: null,
        snoozeReason: null,
        updatedAt: now,
      );
      await _reminders.updateLive(updated);
      await _recordChange(updated, ReminderChangeType.unsnooze, now);
      await _record(id, AuditOperation.update, now);
      return updated;
    });
  }

  @override
  Future<Reminder> close(String id, String entryId) async {
    final now = utcNow(_clock);
    return _reminders.transaction(() async {
      final entry = await _entries.getById(entryId);
      if (entry == null) {
        throw EntityNotFoundException(AuditEntityType.logEntry, entryId);
      }
      return _closer.close(id, entry, now: now, today: localToday(_clock));
    });
  }

  @override
  Future<({LogEntry entry, Reminder reminder})> markDone(
    String id, {
    required CalendarDate date,
    double? km,
    int? costCents,
    String? description,
  }) async {
    final reminder = await _requireWritable(id);
    // The entry and the close share the entry repository's transaction.
    final entry = await _entries.create(
      vehicleId: reminder.vehicleId,
      date: date,
      km: km,
      type: reminder.kind.markDoneEntryType,
      description: description,
      costCents: costCents,
      closesReminderId: id,
    );
    final closed = await _reminders.getLiveById(id);
    return (entry: entry, reminder: closed!);
  }

  @override
  Future<void> delete(String id) async {
    final now = utcNow(_clock);
    return _reminders.transaction(() async {
      final current = await _requireLive(id);
      await _requireActiveVehicle(current.vehicleId, id);
      await _reminders.softDeleteLive(id, now);
      await _record(id, AuditOperation.delete, now);
    });
  }

  @override
  Future<Reminder> restore(String id) async {
    final now = utcNow(_clock);
    return _reminders.transaction(() async {
      final deleted = await _reminders.getDeletedById(id);
      if (deleted == null) {
        throw EntityNotFoundException(AuditEntityType.reminder, id);
      }
      // The vehicle may have been deleted or archived since: the reminder
      // would come back invisible or read-only, so the undo is refused.
      await _requireActiveVehicle(deleted.vehicleId, id);
      await _requireKindFree(deleted);
      await _reminders.restoreDeleted(id, now);
      await _record(id, AuditOperation.restore, now);
      return deleted.copyWith(updatedAt: now);
    });
  }

  /// [current] with the fields of [draft] (title trimmed, optional texts
  /// trimmed to `null`) and `updated_at` = [now].
  static Reminder _applyDraft(
    Reminder current,
    ReminderDraft draft,
    DateTime now,
  ) =>
      current.copyWith(
        kind: draft.kind,
        title: requireText(draft.title, 'title'),
        note: trimToNull(draft.note),
        manualRef: trimToNull(draft.manualRef),
        refIntervalKm: draft.refIntervalKm,
        refIntervalMonths: draft.refIntervalMonths,
        dueDate: draft.dueDate,
        lastDoneDate: draft.lastDoneDate,
        lastDoneKm: draft.lastDoneKm,
        leadDays: draft.leadDays,
        leadKm: draft.leadKm,
        updatedAt: now,
      );

  /// Refuses, before SQLite does, a criterion that breaks the CHECKs of the
  /// `reminders` table, and an anchor day after [today].
  static void _checkCriterion(Reminder reminder, CalendarDate today) {
    _checkPositive('refIntervalKm', reminder.refIntervalKm);
    _checkPositive('refIntervalMonths', reminder.refIntervalMonths);
    _checkNonNegative('lastDoneKm', reminder.lastDoneKm);
    _checkNonNegative('leadKm', reminder.leadKm);
    final leadDays = reminder.leadDays;
    if (leadDays != null && leadDays < 0) {
      throw const InvalidFieldException('leadDays', 'must not be negative');
    }
    final hasInterval =
        reminder.refIntervalKm != null || reminder.refIntervalMonths != null;
    if (reminder.isOneShot) {
      if (hasInterval) {
        throw const InvalidFieldException(
          'dueDate',
          'a one-shot reminder has no interval',
        );
      }
    } else {
      if (!hasInterval) {
        throw const InvalidFieldException(
          'refIntervalKm',
          'an interval or a due date is required',
        );
      }
      if (reminder.lastDoneDate == null) {
        throw const InvalidFieldException(
          'lastDoneDate',
          InvalidFieldException.required,
        );
      }
    }
    final needsKmAnchor =
        reminder.refIntervalKm != null || reminder.appliedIntervalKm != null;
    if (needsKmAnchor && reminder.lastDoneKm == null) {
      throw const InvalidFieldException(
        'lastDoneKm',
        InvalidFieldException.required,
      );
    }
    final anchor = reminder.lastDoneDate;
    if (anchor != null && anchor.isAfter(today)) {
      throw const InvalidFieldException(
        'lastDoneDate',
        InvalidFieldException.inFuture,
      );
    }
  }

  /// Throws [InvalidFieldException] for [field] unless [value] is `null` or
  /// a finite number above 0.
  static void _checkPositive(String field, num? value) {
    if (value != null && (value <= 0 || !value.isFinite)) {
      throw InvalidFieldException(field, 'must be above 0');
    }
  }

  /// Throws [InvalidFieldException] for [field] unless [value] is `null` or
  /// a finite number of at least 0.
  static void _checkNonNegative(String field, double? value) {
    if (value != null && (value < 0 || !value.isFinite)) {
      throw InvalidFieldException(field, 'must not be negative');
    }
  }

  /// Throws [ReminderKindAlreadyUsedException] when [reminder] is open, of a
  /// unique kind, and another live, open reminder of that kind exists on
  /// its vehicle.
  Future<void> _requireKindFree(Reminder reminder) async {
    if (!reminder.kind.uniquePerVehicle || reminder.isCompleted) return;
    if (await _reminders.isKindUsed(
      reminder.vehicleId,
      reminder.kind,
      exceptId: reminder.id,
    )) {
      throw ReminderKindAlreadyUsedException(
        reminder.vehicleId,
        reminder.kind,
      );
    }
  }

  /// Throws [EntityNotFoundException] unless the vehicle [vehicleId] is
  /// live, and [VehicleArchivedException] (for the reminder [reminderId])
  /// when it is archived: its reminders are read-only then.
  Future<void> _requireActiveVehicle(
    String vehicleId,
    String reminderId,
  ) async {
    switch (await _reminders.vehicleStateOf(vehicleId)) {
      case VehicleState.active:
        return;
      case VehicleState.archived:
        throw VehicleArchivedException(AuditEntityType.reminder, reminderId);
      case VehicleState.absent:
        throw EntityNotFoundException(AuditEntityType.vehicle, vehicleId);
    }
  }

  /// Returns the live reminder with [id] or throws
  /// [EntityNotFoundException].
  Future<Reminder> _requireLive(String id) async {
    final reminder = await _reminders.getLiveById(id);
    if (reminder == null) {
      throw EntityNotFoundException(AuditEntityType.reminder, id);
    }
    return reminder;
  }

  /// Returns the live reminder with [id] when it can be changed: its
  /// vehicle is active and it is not a completed one-shot.
  Future<Reminder> _requireWritable(String id) async {
    final reminder = await _requireLive(id);
    await _requireActiveVehicle(reminder.vehicleId, id);
    if (reminder.isCompleted) {
      throw ReminderRuleException(id, ReminderRule.completed);
    }
    return reminder;
  }

  /// Appends the change of [type] that left [reminder] as it is.
  Future<void> _recordChange(
    Reminder reminder,
    ReminderChangeType type,
    DateTime at, {
    String? reason,
  }) =>
      _reminders.insertChange(
        ReminderChange.of(
          reminder,
          id: newId(),
          type: type,
          at: at,
          reason: reason,
        ),
      );

  /// Appends the audit entry for [operation] on the reminder with [id].
  Future<void> _record(String id, AuditOperation operation, DateTime at) =>
      _audit.insertEntry(
        AuditEntry(
          id: newId(),
          entityType: AuditEntityType.reminder,
          entityId: id,
          operation: operation,
          at: at,
        ),
      );
}
