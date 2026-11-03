import 'package:drift/drift.dart';

import '../../models/reminder.dart';
import '../../models/reminder_kind.dart';
import '../app_database.dart';
import '../reminders_table.dart';
import '../row_mappers.dart';
import '../vehicles_table.dart';
import 'vehicles_dao.dart';

part 'reminders_dao.g.dart';

/// Queries on the `reminders` and `reminder_changes` tables (schema v11).
///
/// Accepts and returns domain models only. Every read is limited to live
/// reminders (`deleted = 0`) **of live vehicles**, like the entries: the
/// reminders of a vehicle in the Trash stay on disk untouched and come back
/// with it. Writes that target an existing row match live rows only.
/// `reminder_changes` is append-only: there is no update or delete here
/// (the physical deletes are `TrashDao`'s).
@DriftAccessor(tables: [Reminders, ReminderChanges, Vehicles])
class RemindersDao extends DatabaseAccessor<AppDatabase>
    with _$RemindersDaoMixin {
  /// Creates the DAO on [db]. Obtain it through `AppDatabase.remindersDao`.
  RemindersDao(super.db);

  /// Condition: the reminder's vehicle is live (active or archived).
  Expression<bool> _vehicleIsLive($RemindersTable r) => r.vehicleId.isInQuery(
        selectOnly(vehicles)
          ..addColumns([vehicles.id])
          ..where(vehicles.deleted.equals(false)),
      );

  /// Converts a list of rows into domain models.
  static List<Reminder> _toModels(List<ReminderRow> rows) =>
      [for (final r in rows) r.toModel()];

  /// Select of the live reminders of the live vehicle [vehicleId], oldest
  /// first (the screens sort by status).
  SimpleSelectStatement<$RemindersTable, ReminderRow> _liveByVehicle(
    String vehicleId,
  ) =>
      select(reminders)
        ..where(
          (r) =>
              r.vehicleId.equals(vehicleId) &
              r.deleted.equals(false) &
              _vehicleIsLive(r),
        )
        ..orderBy([
          (r) => OrderingTerm(expression: r.createdAt),
          (r) => OrderingTerm(expression: r.id),
        ]);

  /// Emits the live reminders of the live vehicle [vehicleId], completed
  /// ones included, now and after every change.
  Stream<List<Reminder>> watchLiveByVehicle(String vehicleId) =>
      _liveByVehicle(vehicleId).watch().map(_toModels);

  /// Returns what [watchLiveByVehicle] emits, once.
  Future<List<Reminder>> getLiveByVehicle(String vehicleId) =>
      _liveByVehicle(vehicleId).get().then(_toModels);

  /// Emits the live, open reminders of every active vehicle
  /// ([VehiclesDao.isActive]: live and not archived), each with its vehicle,
  /// now and after every change to either table.
  Stream<List<ActiveReminder>> watchOpenOfActiveVehicles() {
    final query = select(reminders).join([
      innerJoin(vehicles, vehicles.id.equalsExp(reminders.vehicleId)),
    ])
      ..where(
        reminders.deleted.equals(false) &
            reminders.completedAt.isNull() &
            VehiclesDao.isActive(vehicles),
      )
      ..orderBy([
        OrderingTerm(expression: reminders.createdAt),
        OrderingTerm(expression: reminders.id),
      ]);
    return query.watch().map(
          (rows) => [
            for (final row in rows)
              ActiveReminder(
                reminder: row.readTable(reminders).toModel(),
                vehicle: row.readTable(vehicles).toModel(),
              ),
          ],
        );
  }

  /// Select of the live reminder with [id] whose vehicle is live.
  SimpleSelectStatement<$RemindersTable, ReminderRow> _liveById(String id) =>
      select(reminders)
        ..where(
          (r) => r.id.equals(id) & r.deleted.equals(false) & _vehicleIsLive(r),
        );

  /// Returns the live reminder with [id], or `null` if it is missing,
  /// deleted, or its vehicle is deleted.
  Future<Reminder?> getLiveById(String id) async =>
      (await _liveById(id).getSingleOrNull())?.toModel();

  /// Emits what [getLiveById] returns, now and after every change.
  Stream<Reminder?> watchLiveById(String id) =>
      _liveById(id).watchSingleOrNull().map((row) => row?.toModel());

  /// Returns the soft-deleted reminder with [id], or `null` if it is
  /// missing or still live. Ignores the state of its vehicle.
  Future<Reminder?> getDeletedById(String id) async {
    final row = await (select(reminders)
          ..where((r) => r.id.equals(id) & r.deleted.equals(true)))
        .getSingleOrNull();
    return row?.toModel();
  }

  /// Whether a live, open reminder of [kind] other than [exceptId] exists on
  /// the vehicle [vehicleId]: the rule behind the partial unique index
  /// `reminders_one_per_kind`.
  Future<bool> isKindUsed(
    String vehicleId,
    ReminderKind kind, {
    String? exceptId,
  }) async {
    final query = select(reminders)
      ..where(
        (r) =>
            r.vehicleId.equals(vehicleId) &
            r.kind.equalsValue(kind) &
            r.deleted.equals(false) &
            r.completedAt.isNull(),
      );
    if (exceptId != null) {
      query.where((r) => r.id.equals(exceptId).not());
    }
    final rows = await (query..limit(1)).get();
    return rows.isNotEmpty;
  }

  /// Emits the ids of the entries that are the `last_entry_id` of a live
  /// reminder of the live vehicle [vehicleId]: the entries the history
  /// marks with the reminder icon.
  Stream<Set<String>> watchClosingEntryIds(String vehicleId) {
    final query = selectOnly(reminders)
      ..addColumns([reminders.lastEntryId])
      ..where(
        reminders.vehicleId.equals(vehicleId) &
            reminders.deleted.equals(false) &
            reminders.lastEntryId.isNotNull() &
            _vehicleIsLive(reminders),
      );
    return query.watch().map(
          (rows) => {for (final r in rows) r.read(reminders.lastEntryId)!},
        );
  }

  /// Emits the live reminders of a live vehicle whose `last_entry_id` is
  /// [entryId]: what that entry closed.
  Stream<List<Reminder>> watchClosedBy(String entryId) => (select(reminders)
        ..where(
          (r) =>
              r.lastEntryId.equals(entryId) &
              r.deleted.equals(false) &
              _vehicleIsLive(r),
        )
        ..orderBy([(r) => OrderingTerm(expression: r.createdAt)]))
      .watch()
      .map(_toModels);

  /// Inserts [reminder] as a new live row.
  Future<void> insertReminder(Reminder reminder) =>
      into(reminders).insert(reminder.toInsertCompanion());

  /// Overwrites every mutable field of the live reminder with `reminder.id`.
  ///
  /// Returns the number of rows changed: 0 when the reminder is missing or
  /// already deleted.
  Future<int> updateLive(Reminder reminder) =>
      _whereLive(reminder.id).write(reminder.toUpdateCompanion());

  /// Marks the live reminder with [id] as deleted at [at], setting
  /// `deleted` and `deleted_at` together.
  Future<int> softDeleteLive(String id, DateTime at) => _whereLive(id).write(
        RemindersCompanion(
          deleted: const Value(true),
          updatedAt: Value(at),
          deletedAt: Value(at),
        ),
      );

  /// Brings the soft-deleted reminder with [id] back to life at [at],
  /// clearing `deleted` and `deleted_at` together.
  Future<int> restoreDeleted(String id, DateTime at) => (update(reminders)
            ..where((r) => r.id.equals(id) & r.deleted.equals(true)))
          .write(
        RemindersCompanion(
          deleted: const Value(false),
          updatedAt: Value(at),
          deletedAt: const Value(null),
        ),
      );

  /// Appends [change] to the history of its reminder.
  ///
  /// Call it inside the transaction of the reminder write it describes.
  Future<void> insertChange(ReminderChange change) =>
      into(reminderChanges).insert(change.toInsertCompanion());

  /// Emits the history of the reminder [reminderId], newest first; changes
  /// of the same instant newest-inserted first.
  Stream<List<ReminderChange>> watchChanges(String reminderId) =>
      (select(reminderChanges)
            ..where((c) => c.reminderId.equals(reminderId))
            ..orderBy([
              (c) => OrderingTerm.desc(c.changedAt),
              (c) => OrderingTerm.desc(c.rowId),
            ]))
          .watch()
          .map((rows) => [for (final r in rows) r.toModel()]);

  /// Update statement restricted to the live reminder with [id].
  UpdateStatement<$RemindersTable, ReminderRow> _whereLive(String id) =>
      update(reminders)
        ..where((r) => r.id.equals(id) & r.deleted.equals(false));
}
