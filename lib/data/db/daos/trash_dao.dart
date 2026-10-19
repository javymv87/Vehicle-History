import 'package:drift/drift.dart';

import '../../models/trashed_vehicle.dart';
import '../app_database.dart';
import '../log_entries_table.dart';
import '../mileage_readings_table.dart';
import '../owners_table.dart';
import '../row_mappers.dart';
import '../vehicles_table.dart';

part 'trash_dao.g.dart';

/// A soft-deleted row and the instant it was deleted, as read by the
/// cleanup before deciding whether it is old enough to remove.
typedef DeletedRow = ({String id, DateTime deletedAt});

/// Queries on soft-deleted rows: the Trash and the physical deletes.
///
/// The only place that removes rows from disk. Every other DAO only flags
/// rows as deleted. Accepts and returns domain models only.
@DriftAccessor(tables: [Vehicles, Owners, LogEntries, MileageReadings])
class TrashDao extends DatabaseAccessor<AppDatabase> with _$TrashDaoMixin {
  /// Creates the DAO on [db]. Obtain it through `AppDatabase.trashDao`.
  TrashDao(super.db);

  /// Number of live entries of the vehicle in the current row of the outer
  /// query, as a correlated subquery.
  Expression<int> get _liveEntryCount {
    final count = logEntries.id.count();
    return subqueryExpression<int>(
      selectOnly(logEntries)
        ..addColumns([count])
        ..where(
          logEntries.vehicleId.equalsExp(vehicles.id) &
              logEntries.deleted.equals(false),
        ),
    );
  }

  /// Number of live readings of the vehicle in the current row of the outer
  /// query, as a correlated subquery.
  Expression<int> get _liveReadingCount {
    final count = mileageReadings.id.count();
    return subqueryExpression<int>(
      selectOnly(mileageReadings)
        ..addColumns([count])
        ..where(
          mileageReadings.vehicleId.equalsExp(vehicles.id) &
              mileageReadings.deleted.equals(false),
        ),
    );
  }

  /// Emits the soft-deleted vehicles, most recently deleted first, each with
  /// its owner and the counts of its live entries and readings.
  ///
  /// The owner is joined whatever its own state. A deleted vehicle without
  /// `deleted_at` cannot exist from schema v5 on; it would sort last and
  /// show the epoch as its deletion instant rather than vanish.
  Stream<List<TrashedVehicle>> watchTrashedVehicles() {
    final entryCount = _liveEntryCount;
    final readingCount = _liveReadingCount;
    final query = select(vehicles).join([
      innerJoin(owners, owners.id.equalsExp(vehicles.ownerId)),
    ])
      ..addColumns([entryCount, readingCount])
      ..where(vehicles.deleted.equals(true))
      ..orderBy([
        OrderingTerm.desc(vehicles.deletedAt),
        OrderingTerm.asc(vehicles.plate),
      ]);
    return query.watch().map(
          (rows) => [
            for (final row in rows)
              TrashedVehicle(
                vehicle: row.readTable(vehicles).toModel(),
                owner: row.readTable(owners).toModel(),
                deletedAt: row.readTable(vehicles).deletedAt?.toUtc() ??
                    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
                contents: VehicleContents(
                  entryCount: row.read(entryCount) ?? 0,
                  readingCount: row.read(readingCount) ?? 0,
                ),
              ),
          ],
        );
  }

  /// Counts the live entries and readings of the vehicle [vehicleId],
  /// whatever the state of the vehicle.
  Future<VehicleContents> countLiveContents(String vehicleId) async {
    final entries = logEntries.id.count();
    final readings = mileageReadings.id.count();
    final entryRow = await (selectOnly(logEntries)
          ..addColumns([entries])
          ..where(
            logEntries.vehicleId.equals(vehicleId) &
                logEntries.deleted.equals(false),
          ))
        .getSingle();
    final readingRow = await (selectOnly(mileageReadings)
          ..addColumns([readings])
          ..where(
            mileageReadings.vehicleId.equals(vehicleId) &
                mileageReadings.deleted.equals(false),
          ))
        .getSingle();
    return VehicleContents(
      entryCount: entryRow.read(entries) ?? 0,
      readingCount: readingRow.read(readings) ?? 0,
    );
  }

  /// Ids of every soft-deleted vehicle, with or without `deleted_at`.
  Future<List<String>> getTrashedVehicleIds() async {
    final rows = await (selectOnly(vehicles)
          ..addColumns([vehicles.id])
          ..where(vehicles.deleted.equals(true)))
        .get();
    return [for (final r in rows) r.read(vehicles.id)!];
  }

  /// Returns the soft-deleted vehicles with their deletion instant.
  ///
  /// Rows without `deleted_at` are left out: without a date they are never
  /// old enough to be removed by the cleanup.
  Future<List<DeletedRow>> getTrashedVehicles() async {
    final rows = await (select(vehicles)
          ..where((v) => v.deleted.equals(true) & v.deletedAt.isNotNull()))
        .get();
    return [for (final r in rows) (id: r.id, deletedAt: r.deletedAt!.toUtc())];
  }

  /// Returns the soft-deleted entries whose vehicle is live, with their
  /// deletion instant. Rows without `deleted_at` are left out.
  Future<List<DeletedRow>> getDeletedEntriesOfLiveVehicles() async {
    final rows = await (select(logEntries)
          ..where(
            (e) =>
                e.deleted.equals(true) &
                e.deletedAt.isNotNull() &
                e.vehicleId.isInQuery(_liveVehicleIds()),
          ))
        .get();
    return [for (final r in rows) (id: r.id, deletedAt: r.deletedAt!.toUtc())];
  }

  /// Returns the soft-deleted readings whose vehicle is live, with their
  /// deletion instant. Rows without `deleted_at` are left out.
  Future<List<DeletedRow>> getDeletedReadingsOfLiveVehicles() async {
    final rows = await (select(mileageReadings)
          ..where(
            (r) =>
                r.deleted.equals(true) &
                r.deletedAt.isNotNull() &
                r.vehicleId.isInQuery(_liveVehicleIds()),
          ))
        .get();
    return [for (final r in rows) (id: r.id, deletedAt: r.deletedAt!.toUtc())];
  }

  /// Returns the soft-deleted owners that no vehicle row references, live
  /// or deleted, with their deletion instant. Rows without `deleted_at` are
  /// left out.
  Future<List<DeletedRow>> getDeletedOwnersWithoutVehicles() async {
    final referenced = selectOnly(vehicles)..addColumns([vehicles.ownerId]);
    final rows = await (select(owners)
          ..where(
            (o) =>
                o.deleted.equals(true) &
                o.deletedAt.isNotNull() &
                o.id.isNotInQuery(referenced),
          ))
        .get();
    return [for (final r in rows) (id: r.id, deletedAt: r.deletedAt!.toUtc())];
  }

  /// Ids of the live vehicles, as a subquery.
  JoinedSelectStatement<$VehiclesTable, VehicleRow> _liveVehicleIds() =>
      selectOnly(vehicles)
        ..addColumns([vehicles.id])
        ..where(vehicles.deleted.equals(false));

  /// Removes from disk the soft-deleted vehicle [vehicleId] and **every**
  /// entry and reading that references it, whatever their own flags.
  ///
  /// Children go first: their foreign keys are `ON DELETE RESTRICT`. Returns
  /// the number of vehicle rows removed: 0, with nothing removed at all,
  /// when the vehicle is missing or still live. Call it inside a
  /// transaction together with its audit row.
  Future<int> purgeVehicle(String vehicleId) async {
    final isTrashed = await (select(vehicles)
          ..where((v) => v.id.equals(vehicleId) & v.deleted.equals(true)))
        .getSingleOrNull();
    if (isTrashed == null) return 0;
    await (delete(mileageReadings)..where((r) => r.vehicleId.equals(vehicleId)))
        .go();
    await (delete(logEntries)..where((e) => e.vehicleId.equals(vehicleId)))
        .go();
    return (delete(vehicles)
          ..where((v) => v.id.equals(vehicleId) & v.deleted.equals(true)))
        .go();
  }

  /// Removes from disk the soft-deleted entries with [ids]. Live entries are
  /// never touched. Returns the number of rows removed.
  Future<int> purgeEntries(Iterable<String> ids) => (delete(logEntries)
        ..where((e) => e.id.isIn(ids) & e.deleted.equals(true)))
      .go();

  /// Removes from disk the soft-deleted readings with [ids]. Live readings
  /// are never touched. Returns the number of rows removed.
  Future<int> purgeReadings(Iterable<String> ids) => (delete(mileageReadings)
        ..where((r) => r.id.isIn(ids) & r.deleted.equals(true)))
      .go();

  /// Removes from disk the soft-deleted owner [ownerId]. Live owners are
  /// never touched; an owner still referenced by a vehicle row is refused by
  /// its foreign key. Returns the number of rows removed.
  Future<int> purgeOwner(String ownerId) => (delete(owners)
        ..where((o) => o.id.equals(ownerId) & o.deleted.equals(true)))
      .go();
}
