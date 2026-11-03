import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/calendar_date.dart';
import '../../../data/models/log_entry.dart';
import '../../../data/models/reminder.dart';
import '../../../shared/utils/action_result.dart';

/// The actions of a reminder's detail page: override and restore the
/// criterion, snooze and unsnooze, mark done, delete and its Undo
/// (`Docs/08_recordatorios.md`).
///
/// Kept alive: the Undo snackbar of a delete and the odometer offer of a
/// "Mark done" outlive the page, so their callbacks hold this notifier, read
/// before the page goes, never the page's `ref`.
class ReminderActionsController extends Notifier<void> {
  @override
  void build() {}

  /// Sets or changes the applied criterion of the reminder [id].
  Future<ActionResult<Reminder>> overrideCriterion(
    String id, {
    double? appliedKm,
    int? appliedMonths,
    required String reason,
    double? anchorKm,
  }) =>
      runAction(
        () => ref.read(reminderRepositoryProvider).overrideCriterion(
              id,
              appliedKm: appliedKm,
              appliedMonths: appliedMonths,
              reason: reason,
              anchorKm: anchorKm,
            ),
      );

  /// Removes the override of the reminder [id].
  Future<ActionResult<Reminder>> restoreReference(String id) => runAction(
        () => ref.read(reminderRepositoryProvider).restoreReference(id),
      );

  /// Postpones this occurrence of the reminder [id].
  Future<ActionResult<Reminder>> snooze(
    String id, {
    CalendarDate? untilDate,
    double? untilKm,
    required String reason,
  }) =>
      runAction(
        () => ref.read(reminderRepositoryProvider).snooze(
              id,
              untilDate: untilDate,
              untilKm: untilKm,
              reason: reason,
            ),
      );

  /// Removes the snooze of the reminder [id].
  Future<ActionResult<Reminder>> unsnooze(String id) =>
      runAction(() => ref.read(reminderRepositoryProvider).unsnooze(id));

  /// Creates the closing entry of the reminder [id] and closes it.
  Future<ActionResult<LogEntry>> markDone(
    String id, {
    required CalendarDate date,
    double? km,
    int? costCents,
    String? description,
  }) =>
      runAction(() async {
        final done = await ref.read(reminderRepositoryProvider).markDone(
              id,
              date: date,
              km: km,
              costCents: costCents,
              description: description,
            );
        return done.entry;
      });

  /// Soft-deletes the reminder [id].
  Future<ActionResult<void>> delete(String id) =>
      runAction(() => ref.read(reminderRepositoryProvider).delete(id));

  /// Brings back the reminder [id] deleted a moment ago (Undo).
  Future<ActionResult<Reminder>> undoDelete(String id) =>
      runAction(() => ref.read(reminderRepositoryProvider).restore(id));
}

/// The [ReminderActionsController], kept alive.
final reminderActionsControllerProvider =
    NotifierProvider<ReminderActionsController, void>(
  ReminderActionsController.new,
);
