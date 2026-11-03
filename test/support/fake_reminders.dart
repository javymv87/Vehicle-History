import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/log_entry.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/reminder.dart';
import 'package:vehicle_history/data/repositories/reminder_repository.dart';
import 'package:vehicle_history/data/repositories/repository_exceptions.dart';

import 'fake_repositories.dart';

/// [ReminderRepository] on a [FakeStore].
///
/// Mirrors the contract closely enough for widget tests: reads limited to
/// live reminders of live vehicles, the archive guard, the one-per-kind
/// rule and a change row for every write. The real rules are tested
/// against Drift in `test/unit/data/reminder_repository_test.dart`.
class FakeReminderRepository implements ReminderRepository {
  /// Creates the repository on [store], creating entries through
  /// [entries] (for "Mark done").
  FakeReminderRepository(this.store, this.entries);

  /// The shared data.
  final FakeStore store;

  /// The entries, for "Mark done".
  final FakeLogEntryRepository entries;

  /// Live reminders of the live vehicle [vehicleId], oldest first.
  List<Reminder> _liveOf(String vehicleId) {
    if (store.deletedVehicles.contains(vehicleId)) return [];
    return [
      for (final r in store.reminders.values)
        if (r.vehicleId == vehicleId && !store.deletedReminders.contains(r.id))
          r,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// The live reminder [id] of a live vehicle, or `null`.
  Reminder? _live(String id) {
    final reminder = store.reminders[id];
    if (reminder == null ||
        store.deletedReminders.contains(id) ||
        store.deletedVehicles.contains(reminder.vehicleId)) {
      return null;
    }
    return reminder;
  }

  /// The live reminder [id] when it can be written, or throws.
  Reminder _writable(String id) {
    final reminder = _live(id);
    if (reminder == null) {
      throw EntityNotFoundException(AuditEntityType.reminder, id);
    }
    store.requireActiveVehicle(reminder.vehicleId);
    if (reminder.isCompleted) {
      throw ReminderRuleException(id, ReminderRule.completed);
    }
    return reminder;
  }

  /// Stores [reminder] and its change of [type].
  Reminder _save(
    Reminder reminder,
    ReminderChangeType type, {
    String? reason,
  }) {
    store.reminders[reminder.id] = reminder;
    store.reminderChanges.add(
      ReminderChange.of(
        reminder,
        id: store.newId('change'),
        type: type,
        at: store.now,
        reason: reason,
      ),
    );
    return reminder;
  }

  /// Throws when another live, open reminder of the same unique kind
  /// exists on the vehicle of [reminder].
  void _requireKindFree(Reminder reminder) {
    if (!reminder.kind.uniquePerVehicle) return;
    final used = _liveOf(reminder.vehicleId).any(
      (r) => r.id != reminder.id && r.kind == reminder.kind && !r.isCompleted,
    );
    if (used) {
      throw ReminderKindAlreadyUsedException(
        reminder.vehicleId,
        reminder.kind,
      );
    }
  }

  /// [reminder] with the fields of [draft].
  Reminder _apply(Reminder reminder, ReminderDraft draft) => reminder.copyWith(
        kind: draft.kind,
        title: draft.title.trim(),
        note: draft.note,
        manualRef: draft.manualRef,
        refIntervalKm: draft.refIntervalKm,
        refIntervalMonths: draft.refIntervalMonths,
        dueDate: draft.dueDate,
        lastDoneDate: draft.lastDoneDate,
        lastDoneKm: draft.lastDoneKm,
        leadDays: draft.leadDays,
        leadKm: draft.leadKm,
        updatedAt: store.now,
      );

  @override
  Stream<List<Reminder>> watchByVehicle(String vehicleId) =>
      store.watch(() => _liveOf(vehicleId));

  @override
  Future<List<Reminder>> getByVehicle(String vehicleId) async =>
      _liveOf(vehicleId);

  @override
  Stream<List<ActiveReminder>> watchActiveAcrossVehicles() => store.watch(
        () => [
          for (final vehicle in store.activeVehicles)
            for (final reminder in _liveOf(vehicle.id))
              if (!reminder.isCompleted)
                ActiveReminder(reminder: reminder, vehicle: vehicle),
        ],
      );

  @override
  Future<Reminder?> getById(String id) async => _live(id);

  @override
  Stream<Reminder?> watchById(String id) => store.watch(() => _live(id));

  @override
  Stream<List<ReminderChange>> watchChanges(String reminderId) => store.watch(
        () => [
          for (final change in store.reminderChanges.reversed)
            if (change.reminderId == reminderId) change,
        ],
      );

  @override
  Stream<Set<String>> watchClosingEntryIds(String vehicleId) => store.watch(
        () => {
          for (final reminder in _liveOf(vehicleId))
            if (reminder.lastEntryId case final id?) id,
        },
      );

  @override
  Future<bool> hasBeenClosed(String id) async => _closed(id);

  /// Whether the history of [id] holds a `close` change.
  bool _closed(String id) => store.reminderChanges.any(
        (change) =>
            change.reminderId == id && change.type == ReminderChangeType.close,
      );

  @override
  Stream<List<Reminder>> watchClosedBy(String entryId) => store.watch(
        () => [
          for (final reminder in store.reminders.values)
            if (reminder.lastEntryId == entryId && _live(reminder.id) != null)
              reminder,
        ],
      );

  @override
  Stream<List<Reminder>> watchClosable(String vehicleId, LogEntryType type) =>
      store.watch(
        () => [
          for (final reminder in _liveOf(vehicleId))
            if (!reminder.isCompleted &&
                reminder.kind.closingEntryTypes.contains(type))
              reminder,
        ],
      );

  @override
  Future<Reminder> create({
    required String vehicleId,
    required ReminderDraft draft,
  }) =>
      store.write(() {
        store.requireActiveVehicle(vehicleId);
        final reminder = _apply(
          Reminder(
            id: store.newId('reminder'),
            vehicleId: vehicleId,
            kind: draft.kind,
            title: draft.title,
            createdAt: store.now,
            updatedAt: store.now,
          ),
          draft,
        );
        _requireKindFree(reminder);
        return _save(reminder, ReminderChangeType.create);
      });

  @override
  Future<Reminder> update(String id, ReminderDraft draft) => store.write(() {
        final current = _writable(id);
        final updated = _apply(current, draft);
        if ((updated.kind != current.kind ||
                updated.isOneShot != current.isOneShot) &&
            _closed(id)) {
          throw ReminderRuleException(id, ReminderRule.alreadyClosed);
        }
        _requireKindFree(updated);
        return _save(updated, ReminderChangeType.edit);
      });

  @override
  Future<Reminder> overrideCriterion(
    String id, {
    double? appliedKm,
    int? appliedMonths,
    required String reason,
    double? anchorKm,
  }) =>
      store.write(() {
        final current = _writable(id);
        return _save(
          current.copyWith(
            overrideActive: true,
            appliedIntervalKm: appliedKm,
            appliedIntervalMonths: appliedMonths,
            overrideReason: reason.trim(),
            overrideAt: store.now,
            lastDoneKm: current.lastDoneKm ?? anchorKm,
            updatedAt: store.now,
          ),
          ReminderChangeType.applyOverride,
          reason: reason.trim(),
        );
      });

  @override
  Future<Reminder> restoreReference(String id) => store.write(
        () => _save(
          _writable(id).copyWith(
            overrideActive: false,
            appliedIntervalKm: null,
            appliedIntervalMonths: null,
            overrideReason: null,
            overrideAt: null,
            updatedAt: store.now,
          ),
          ReminderChangeType.restoreReference,
        ),
      );

  @override
  Future<Reminder> snooze(
    String id, {
    CalendarDate? untilDate,
    double? untilKm,
    required String reason,
  }) =>
      store.write(
        () => _save(
          _writable(id).copyWith(
            snoozeUntilDate: untilDate,
            snoozeUntilKm: untilKm,
            snoozeReason: reason.trim(),
            updatedAt: store.now,
          ),
          ReminderChangeType.snooze,
          reason: reason.trim(),
        ),
      );

  @override
  Future<Reminder> unsnooze(String id) => store.write(
        () => _save(
          _writable(id).copyWith(
            snoozeUntilDate: null,
            snoozeUntilKm: null,
            snoozeReason: null,
            updatedAt: store.now,
          ),
          ReminderChangeType.unsnooze,
        ),
      );

  @override
  Future<Reminder> close(String id, String entryId) => store.write(() {
        _writable(id);
        return store.closeReminder(id, store.entries[entryId]!);
      });

  @override
  Future<({LogEntry entry, Reminder reminder})> markDone(
    String id, {
    required CalendarDate date,
    double? km,
    int? costCents,
    String? description,
  }) async {
    final reminder = _writable(id);
    final entry = await entries.create(
      vehicleId: reminder.vehicleId,
      date: date,
      km: km,
      type: reminder.kind.markDoneEntryType,
      description: description,
      costCents: costCents,
      closesReminderId: id,
    );
    return (entry: entry, reminder: store.reminders[id]!);
  }

  @override
  Future<void> delete(String id) => store.write(() {
        final current = _live(id);
        if (current == null) {
          throw EntityNotFoundException(AuditEntityType.reminder, id);
        }
        store.requireActiveVehicle(current.vehicleId);
        store.deletedReminders.add(id);
      });

  @override
  Future<Reminder> restore(String id) => store.write(() {
        final reminder = store.reminders[id];
        if (reminder == null || !store.deletedReminders.contains(id)) {
          throw EntityNotFoundException(AuditEntityType.reminder, id);
        }
        store.requireActiveVehicle(reminder.vehicleId);
        _requireKindFree(reminder);
        store.deletedReminders.remove(id);
        return reminder;
      });
}
