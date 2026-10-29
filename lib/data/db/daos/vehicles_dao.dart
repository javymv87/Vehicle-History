import 'package:drift/drift.dart';

import '../../models/archive_reason.dart';
import '../../models/calendar_date.dart';
import '../../models/vehicle.dart';
import '../app_database.dart';
import '../owners_table.dart';
import '../row_mappers.dart';
import '../vehicles_table.dart';

part 'vehicles_dao.g.dart';

/// Queries on the `vehicles` table.
///
/// Accepts and returns domain models only. Every read is limited to live rows
/// (`deleted = 0`), and writes that target an existing row match live rows
/// only, so a deleted vehicle cannot be changed by accident. The archived
/// vehicles (v8) are live rows with `archived_at` set: [isActive] is the one
/// filter that leaves them out of the "current" vehicles.
@DriftAccessor(tables: [Vehicles, Owners])
class VehiclesDao extends DatabaseAccessor<AppDatabase>
    with _$VehiclesDaoMixin {
  /// Creates the DAO on [db]. Obtain it through `AppDatabase.vehiclesDao`.
  VehiclesDao(super.db);

  /// Condition of a current vehicle: live and not archived.
  ///
  /// The single filter behind every "current vehicles" read (the main list,
  /// and the reminders of step 11): an archived vehicle keeps its history
  /// but is never current.
  static Expression<bool> isActive($VehiclesTable v) =>
      v.deleted.equals(false) & v.archivedAt.isNull();

  /// Select of live vehicles, optionally of one owner, ordered by plate.
  /// [archived] limits it to the active (`false`) or the archived (`true`)
  /// ones; `null` takes both.
  SimpleSelectStatement<$VehiclesTable, VehicleRow> _live({
    String? ownerId,
    bool? archived,
  }) {
    final query = select(vehicles)..where((v) => v.deleted.equals(false));
    if (ownerId != null) {
      query.where((v) => v.ownerId.equals(ownerId));
    }
    switch (archived) {
      case false:
        query.where((v) => v.archivedAt.isNull());
      case true:
        query.where((v) => v.archivedAt.isNotNull());
      case null:
        break;
    }
    return query..orderBy([(v) => OrderingTerm(expression: v.plate)]);
  }

  /// Converts a list of rows into domain models.
  static List<Vehicle> _toModels(List<VehicleRow> rows) =>
      [for (final r in rows) r.toModel()];

  /// Returns every live vehicle, active and archived, once.
  Future<List<Vehicle>> getLive() => _live().get().then(_toModels);

  /// Emits the active vehicles ([isActive]) now and after every change.
  Stream<List<Vehicle>> watchActive() =>
      _live(archived: false).watch().map(_toModels);

  /// Returns the active vehicles once.
  Future<List<Vehicle>> getActive() =>
      _live(archived: false).get().then(_toModels);

  /// Emits the archived vehicles that are not in the Trash, now and after
  /// every change: most recently archived first, then by plate.
  Stream<List<Vehicle>> watchArchived() => (_live(archived: true)
        ..orderBy([
          (v) => OrderingTerm.desc(v.archivedAt),
          (v) => OrderingTerm(expression: v.plate),
        ]))
      .watch()
      .map(_toModels);

  /// Emits the live vehicles of the owner with [ownerId].
  Stream<List<Vehicle>> watchLiveByOwner(String ownerId) =>
      _live(ownerId: ownerId).watch().map(_toModels);

  /// Returns the live vehicles of the owner with [ownerId] once.
  Future<List<Vehicle>> getLiveByOwner(String ownerId) =>
      _live(ownerId: ownerId).get().then(_toModels);

  /// Select of the live vehicle with [id].
  SimpleSelectStatement<$VehiclesTable, VehicleRow> _liveById(String id) =>
      select(vehicles)..where((v) => v.id.equals(id) & v.deleted.equals(false));

  /// Returns the live vehicle with [id], active or archived, or `null` if
  /// missing or deleted.
  Future<Vehicle?> getLiveById(String id) async =>
      (await _liveById(id).getSingleOrNull())?.toModel();

  /// Emits what [getLiveById] returns, now and after every change.
  Stream<Vehicle?> watchLiveById(String id) =>
      _liveById(id).watchSingleOrNull().map((row) => row?.toModel());

  /// Returns the soft-deleted vehicle with [id], or `null` if it is missing
  /// or still live.
  Future<Vehicle?> getDeletedById(String id) async {
    final row = await (select(vehicles)
          ..where((v) => v.id.equals(id) & v.deleted.equals(true)))
        .getSingleOrNull();
    return row?.toModel();
  }

  /// Whether a live vehicle other than [exceptId] already uses [plate].
  ///
  /// [plate] must already be normalised (trimmed, upper-case).
  Future<bool> isPlateUsedByLive(String plate, {String? exceptId}) async {
    final query = select(vehicles)
      ..where((v) => v.plate.equals(plate) & v.deleted.equals(false));
    if (exceptId != null) {
      query.where((v) => v.id.equals(exceptId).not());
    }
    final rows = await (query..limit(1)).get();
    return rows.isNotEmpty;
  }

  /// Whether a live owner with [ownerId] exists.
  ///
  /// The foreign key alone cannot tell: a soft-deleted owner still has a row.
  Future<bool> isOwnerLive(String ownerId) async {
    final rows = await (select(owners)
          ..where((o) => o.id.equals(ownerId) & o.deleted.equals(false))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  /// Inserts [vehicle] as a new live row.
  Future<void> insertVehicle(Vehicle vehicle) =>
      into(vehicles).insert(vehicle.toInsertCompanion());

  /// Overwrites the editable fields and `updated_at` of the live vehicle with
  /// `vehicle.id`. `current_odometer_km` is never written here.
  ///
  /// Returns the number of rows changed: 0 when the vehicle is missing or
  /// already deleted.
  Future<int> updateLive(Vehicle vehicle) =>
      _whereLive(vehicle.id).write(vehicle.toUpdateCompanion());

  /// Marks the live vehicle with [id] as deleted at [at], setting
  /// `deleted` and `deleted_at` together.
  ///
  /// Returns the number of rows changed: 0 when the vehicle is missing or
  /// already deleted.
  Future<int> softDeleteLive(String id, DateTime at) => _whereLive(id).write(
        VehiclesCompanion(
          deleted: const Value(true),
          updatedAt: Value(at),
          deletedAt: Value(at),
        ),
      );

  /// Brings the soft-deleted vehicle with [id] back to life at [at],
  /// clearing `deleted` and `deleted_at` together.
  ///
  /// Returns the number of rows changed: 0 when the vehicle is missing or not
  /// deleted.
  Future<int> restoreDeleted(String id, DateTime at) =>
      (update(vehicles)..where((v) => v.id.equals(id) & v.deleted.equals(true)))
          .write(
        VehiclesCompanion(
          deleted: const Value(false),
          updatedAt: Value(at),
          deletedAt: const Value(null),
        ),
      );

  /// Archives the active vehicle with [id] at [at]: writes the four archive
  /// columns, `current_odometer_km` when [km] is given (the cache of the
  /// reading inserted with the archive) and `updated_at`.
  ///
  /// Returns the number of rows changed: 0 when the vehicle is missing,
  /// deleted or already archived.
  Future<int> archiveLive(
    String id, {
    required CalendarDate archivedAt,
    required ArchiveReason reason,
    required String? note,
    required double? km,
    required DateTime at,
  }) =>
      (_whereLive(id)..where((v) => v.archivedAt.isNull())).write(
        VehiclesCompanion(
          updatedAt: Value(at),
          archivedAt: Value(archivedAt),
          archiveReason: Value(reason),
          archiveNote: Value(note),
          archivedKm: Value(km),
        ),
      );

  /// Reactivates the archived vehicle with [id] at [at]: clears the four
  /// archive columns and writes `updated_at`. Its readings are left alone.
  ///
  /// Returns the number of rows changed: 0 when the vehicle is missing,
  /// deleted or not archived.
  Future<int> reactivateArchived(String id, DateTime at) =>
      (_whereLive(id)..where((v) => v.archivedAt.isNotNull())).write(
        VehiclesCompanion(
          updatedAt: Value(at),
          archivedAt: const Value(null),
          archiveReason: const Value(null),
          archiveNote: const Value(null),
          archivedKm: const Value(null),
        ),
      );

  /// Update statement restricted to the live vehicle with [id].
  UpdateStatement<$VehiclesTable, VehicleRow> _whereLive(String id) =>
      update(vehicles)..where((v) => v.id.equals(id) & v.deleted.equals(false));
}
