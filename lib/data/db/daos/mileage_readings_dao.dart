import 'package:drift/drift.dart';

import '../../models/mileage_reading.dart';
import '../app_database.dart';
import '../mileage_readings_table.dart';
import '../row_mappers.dart';
import '../vehicles_table.dart';

part 'mileage_readings_dao.g.dart';

/// Queries on the `mileage_readings` table, and the odometer cache in
/// `vehicles.current_odometer_km` that follows it.
///
/// Accepts and returns domain models only. Every read is limited to live
/// readings (`deleted = 0`) **of live vehicles**: the readings of a deleted
/// vehicle stay on disk untouched and come back when the vehicle is
/// restored. Writes that target an existing row match live rows only.
@DriftAccessor(tables: [MileageReadings, Vehicles])
class MileageReadingsDao extends DatabaseAccessor<AppDatabase>
    with _$MileageReadingsDaoMixin {
  /// Creates the DAO on [db]. Obtain it through
  /// `AppDatabase.mileageReadingsDao`.
  MileageReadingsDao(super.db);

  /// Condition: the reading's vehicle is live.
  ///
  /// A subquery rather than a join, so the select keeps returning plain
  /// reading rows; `watch` still re-runs when the vehicles change.
  Expression<bool> _vehicleIsLive($MileageReadingsTable r) =>
      r.vehicleId.isInQuery(
        selectOnly(vehicles)
          ..addColumns([vehicles.id])
          ..where(vehicles.deleted.equals(false)),
      );

  /// Select of the live readings of the live vehicle [vehicleId], newest
  /// first.
  ///
  /// Ordered by day, then by creation instant for readings of the same day,
  /// then by id so the order is always stable. The first row is the last
  /// reading, the final row the initial one.
  SimpleSelectStatement<$MileageReadingsTable, MileageReadingRow>
      _liveByVehicle(String vehicleId) => select(mileageReadings)
        ..where(
          (r) =>
              r.vehicleId.equals(vehicleId) &
              r.deleted.equals(false) &
              _vehicleIsLive(r),
        )
        ..orderBy([
          (r) => OrderingTerm.desc(r.readingDate),
          (r) => OrderingTerm.desc(r.createdAt),
          (r) => OrderingTerm.desc(r.id),
        ]);

  /// Converts a list of rows into domain models.
  static List<MileageReading> _toModels(List<MileageReadingRow> rows) =>
      [for (final r in rows) r.toModel()];

  /// Emits the live readings of the live vehicle [vehicleId] now and after
  /// every change, newest first.
  Stream<List<MileageReading>> watchLiveByVehicle(String vehicleId) =>
      _liveByVehicle(vehicleId).watch().map(_toModels);

  /// Returns the same readings as [watchLiveByVehicle] once.
  Future<List<MileageReading>> getLiveByVehicle(String vehicleId) =>
      _liveByVehicle(vehicleId).get().then(_toModels);

  /// Returns the last live reading of the live vehicle [vehicleId], or
  /// `null` when it has none or the vehicle is missing or deleted.
  Future<MileageReading?> getLastLive(String vehicleId) async {
    final row = await (_liveByVehicle(vehicleId)..limit(1)).getSingleOrNull();
    return row?.toModel();
  }

  /// Emits what [getLastLive] returns, now and after every change.
  Stream<MileageReading?> watchLastLive(String vehicleId) =>
      (_liveByVehicle(vehicleId)..limit(1))
          .watchSingleOrNull()
          .map((row) => row?.toModel());

  /// Number of live readings of the vehicle [vehicleId], ignoring the state
  /// of the vehicle.
  Future<int> countLive(String vehicleId) async {
    final count = mileageReadings.id.count();
    final row = await (selectOnly(mileageReadings)
          ..addColumns([count])
          ..where(
            mileageReadings.vehicleId.equals(vehicleId) &
                mileageReadings.deleted.equals(false),
          ))
        .getSingle();
    return row.read(count) ?? 0;
  }

  /// Returns the live reading with [id] whose vehicle is live, or `null`.
  Future<MileageReading?> getLiveById(String id) async {
    final row = await (select(mileageReadings)
          ..where(
            (r) =>
                r.id.equals(id) & r.deleted.equals(false) & _vehicleIsLive(r),
          ))
        .getSingleOrNull();
    return row?.toModel();
  }

  /// Returns the soft-deleted reading with [id], or `null` if it is missing
  /// or still live. Ignores the state of its vehicle.
  Future<MileageReading?> getDeletedById(String id) async {
    final row = await (select(mileageReadings)
          ..where((r) => r.id.equals(id) & r.deleted.equals(true)))
        .getSingleOrNull();
    return row?.toModel();
  }

  /// Whether a live vehicle with [vehicleId] exists.
  ///
  /// The foreign key alone cannot tell: a soft-deleted vehicle still has a
  /// row.
  Future<bool> isVehicleLive(String vehicleId) async {
    final rows = await (select(vehicles)
          ..where((v) => v.id.equals(vehicleId) & v.deleted.equals(false))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  /// Inserts [reading] as a new live row.
  Future<void> insertReading(MileageReading reading) =>
      into(mileageReadings).insert(reading.toInsertCompanion());

  /// Overwrites the day, the km and `updated_at` of the live reading with
  /// `reading.id`.
  ///
  /// Returns the number of rows changed: 0 when the reading is missing or
  /// already deleted.
  Future<int> updateLive(MileageReading reading) =>
      _whereLive(reading.id).write(reading.toUpdateCompanion());

  /// Marks the live reading with [id] as deleted at [at], setting
  /// `deleted` and `deleted_at` together.
  ///
  /// Returns the number of rows changed: 0 when the reading is missing or
  /// already deleted.
  Future<int> softDeleteLive(String id, DateTime at) => _whereLive(id).write(
        MileageReadingsCompanion(
          deleted: const Value(true),
          updatedAt: Value(at),
          deletedAt: Value(at),
        ),
      );

  /// Brings the soft-deleted reading with [id] back to life at [at],
  /// clearing `deleted` and `deleted_at` together.
  ///
  /// Returns the number of rows changed: 0 when the reading is missing or
  /// not deleted.
  Future<int> restoreDeleted(String id, DateTime at) => (update(mileageReadings)
            ..where((r) => r.id.equals(id) & r.deleted.equals(true)))
          .write(
        MileageReadingsCompanion(
          deleted: const Value(false),
          updatedAt: Value(at),
          deletedAt: const Value(null),
        ),
      );

  /// Writes [km] into `current_odometer_km` of the vehicle [vehicleId].
  ///
  /// The column is a cache of the last live reading: call it in the same
  /// transaction as every reading write. `updated_at` of the vehicle is left
  /// alone, since none of its own fields changed.
  Future<int> setVehicleOdometer(String vehicleId, int km) =>
      (update(vehicles)..where((v) => v.id.equals(vehicleId)))
          .write(VehiclesCompanion(currentOdometerKm: Value(km)));

  /// Update statement restricted to the live reading with [id].
  UpdateStatement<$MileageReadingsTable, MileageReadingRow> _whereLive(
    String id,
  ) =>
      update(mileageReadings)
        ..where((r) => r.id.equals(id) & r.deleted.equals(false));
}
