import 'package:drift/drift.dart';

import '../../models/calendar_date.dart';
import '../../models/log_entry.dart';
import '../../models/log_entry_type.dart';
import '../app_database.dart';
import '../converters.dart';
import '../log_entries_table.dart';
import '../row_mappers.dart';
import '../vehicles_table.dart';

part 'log_entries_dao.g.dart';

/// Queries on the `log_entries` table.
///
/// Accepts and returns domain models only. Every read is limited to live
/// entries (`deleted = 0`) **of live vehicles**: the entries of a deleted
/// vehicle stay on disk untouched and come back when the vehicle is
/// restored. Writes that target an existing row match live rows only.
@DriftAccessor(tables: [LogEntries, Vehicles])
class LogEntriesDao extends DatabaseAccessor<AppDatabase>
    with _$LogEntriesDaoMixin {
  /// Creates the DAO on [db]. Obtain it through `AppDatabase.logEntriesDao`.
  LogEntriesDao(super.db);

  /// Converter used to compare the `type` column with plain codes.
  static const LogEntryTypeConverter _typeCodes = LogEntryTypeConverter();

  /// Condition: the entry's vehicle is live.
  ///
  /// A subquery rather than a join, so the select keeps returning plain
  /// entry rows; `watch` still re-runs when the vehicles change.
  Expression<bool> _vehicleIsLive($LogEntriesTable e) => e.vehicleId.isInQuery(
        selectOnly(vehicles)
          ..addColumns([vehicles.id])
          ..where(vehicles.deleted.equals(false)),
      );

  /// Select of the live entries of the live vehicle [vehicleId], newest
  /// first, restricted to the days [from]–[to] (both inclusive, each
  /// optional) and to [types] (all types when empty).
  ///
  /// Ordered by day, then by creation instant for entries of the same day,
  /// then by id so the order is always stable.
  SimpleSelectStatement<$LogEntriesTable, LogEntryRow> _liveByVehicle(
    String vehicleId, {
    CalendarDate? from,
    CalendarDate? to,
    Set<LogEntryType> types = const {},
  }) {
    final query = select(logEntries)
      ..where(
        (e) =>
            e.vehicleId.equals(vehicleId) &
            e.deleted.equals(false) &
            _vehicleIsLive(e),
      );
    // `yyyy-MM-dd` text sorts chronologically, so text comparison is a
    // day comparison.
    if (from != null) {
      query.where((e) => e.entryDate.isBiggerOrEqualValue(_day(from)));
    }
    if (to != null) {
      query.where((e) => e.entryDate.isSmallerOrEqualValue(_day(to)));
    }
    if (types.isNotEmpty) {
      query.where(
        (e) => e.type.isIn([for (final t in types) _typeCodes.toSql(t)]),
      );
    }
    return query
      ..orderBy([
        (e) => OrderingTerm.desc(e.entryDate),
        (e) => OrderingTerm.desc(e.createdAt),
        (e) => OrderingTerm.desc(e.id),
      ]);
  }

  /// Storage text of [date].
  static String _day(CalendarDate date) =>
      const CalendarDateConverter().toSql(date);

  /// Converts a list of rows into domain models.
  static List<LogEntry> _toModels(List<LogEntryRow> rows) =>
      [for (final r in rows) r.toModel()];

  /// Emits the live entries of the live vehicle [vehicleId] now and after
  /// every change, newest first, limited by the optional date range and
  /// types (see [_liveByVehicle]).
  Stream<List<LogEntry>> watchLiveByVehicle(
    String vehicleId, {
    CalendarDate? from,
    CalendarDate? to,
    Set<LogEntryType> types = const {},
  }) =>
      _liveByVehicle(vehicleId, from: from, to: to, types: types)
          .watch()
          .map(_toModels);

  /// Returns the same entries as [watchLiveByVehicle] once.
  Future<List<LogEntry>> getLiveByVehicle(
    String vehicleId, {
    CalendarDate? from,
    CalendarDate? to,
    Set<LogEntryType> types = const {},
  }) =>
      _liveByVehicle(vehicleId, from: from, to: to, types: types)
          .get()
          .then(_toModels);

  /// Select of the live entry with [id] whose vehicle is live.
  SimpleSelectStatement<$LogEntriesTable, LogEntryRow> _liveById(String id) =>
      select(logEntries)
        ..where(
          (e) => e.id.equals(id) & e.deleted.equals(false) & _vehicleIsLive(e),
        );

  /// Returns the live entry with [id], or `null` if it is missing, deleted,
  /// or its vehicle is deleted.
  Future<LogEntry?> getLiveById(String id) async =>
      (await _liveById(id).getSingleOrNull())?.toModel();

  /// Emits the entry [getLiveById] would return, now and after every change.
  Stream<LogEntry?> watchLiveById(String id) =>
      _liveById(id).watchSingleOrNull().map((row) => row?.toModel());

  /// Returns the soft-deleted entry with [id], or `null` if it is missing or
  /// still live. Ignores the state of its vehicle.
  Future<LogEntry?> getDeletedById(String id) async {
    final row = await (select(logEntries)
          ..where((e) => e.id.equals(id) & e.deleted.equals(true)))
        .getSingleOrNull();
    return row?.toModel();
  }

  /// Inserts [entry] as a new live row.
  Future<void> insertEntry(LogEntry entry) =>
      into(logEntries).insert(entry.toInsertCompanion());

  /// Overwrites the editable fields and `updated_at` of the live entry with
  /// `entry.id`.
  ///
  /// Returns the number of rows changed: 0 when the entry is missing or
  /// already deleted.
  Future<int> updateLive(LogEntry entry) =>
      _whereLive(entry.id).write(entry.toUpdateCompanion());

  /// Marks the live entry with [id] as deleted at [at], setting
  /// `deleted` and `deleted_at` together.
  ///
  /// Returns the number of rows changed: 0 when the entry is missing or
  /// already deleted.
  Future<int> softDeleteLive(String id, DateTime at) => _whereLive(id).write(
        LogEntriesCompanion(
          deleted: const Value(true),
          updatedAt: Value(at),
          deletedAt: Value(at),
        ),
      );

  /// Brings the soft-deleted entry with [id] back to life at [at],
  /// clearing `deleted` and `deleted_at` together.
  ///
  /// Returns the number of rows changed: 0 when the entry is missing or not
  /// deleted.
  Future<int> restoreDeleted(String id, DateTime at) => (update(logEntries)
            ..where((e) => e.id.equals(id) & e.deleted.equals(true)))
          .write(
        LogEntriesCompanion(
          deleted: const Value(false),
          updatedAt: Value(at),
          deletedAt: const Value(null),
        ),
      );

  /// Update statement restricted to the live entry with [id].
  UpdateStatement<$LogEntriesTable, LogEntryRow> _whereLive(String id) =>
      update(logEntries)
        ..where((e) => e.id.equals(id) & e.deleted.equals(false));
}
