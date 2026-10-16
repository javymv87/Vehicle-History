import 'package:drift/drift.dart';

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
/// only, so a deleted vehicle cannot be changed by accident.
@DriftAccessor(tables: [Vehicles, Owners])
class VehiclesDao extends DatabaseAccessor<AppDatabase>
    with _$VehiclesDaoMixin {
  /// Creates the DAO on [db]. Obtain it through `AppDatabase.vehiclesDao`.
  VehiclesDao(super.db);

  /// Select of live vehicles, optionally of one owner, ordered by plate.
  SimpleSelectStatement<$VehiclesTable, VehicleRow> _live({String? ownerId}) {
    final query = select(vehicles)..where((v) => v.deleted.equals(false));
    if (ownerId != null) {
      query.where((v) => v.ownerId.equals(ownerId));
    }
    return query..orderBy([(v) => OrderingTerm(expression: v.plate)]);
  }

  /// Converts a list of rows into domain models.
  static List<Vehicle> _toModels(List<VehicleRow> rows) =>
      [for (final r in rows) r.toModel()];

  /// Emits the live vehicles now and after every change.
  Stream<List<Vehicle>> watchLive() => _live().watch().map(_toModels);

  /// Returns the live vehicles once.
  Future<List<Vehicle>> getLive() => _live().get().then(_toModels);

  /// Emits the live vehicles of the owner with [ownerId].
  Stream<List<Vehicle>> watchLiveByOwner(String ownerId) =>
      _live(ownerId: ownerId).watch().map(_toModels);

  /// Returns the live vehicles of the owner with [ownerId] once.
  Future<List<Vehicle>> getLiveByOwner(String ownerId) =>
      _live(ownerId: ownerId).get().then(_toModels);

  /// Returns the live vehicle with [id], or `null` if missing or deleted.
  Future<Vehicle?> getLiveById(String id) async {
    final row = await (select(vehicles)
          ..where((v) => v.id.equals(id) & v.deleted.equals(false)))
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

  /// Marks the live vehicle with [id] as deleted at [at].
  ///
  /// Returns the number of rows changed: 0 when the vehicle is missing or
  /// already deleted.
  Future<int> softDeleteLive(String id, DateTime at) => _whereLive(id).write(
        VehiclesCompanion(deleted: const Value(true), updatedAt: Value(at)),
      );

  /// Update statement restricted to the live vehicle with [id].
  UpdateStatement<$VehiclesTable, VehicleRow> _whereLive(String id) =>
      update(vehicles)..where((v) => v.id.equals(id) & v.deleted.equals(false));
}
