import '../db/daos/audit_log_dao.dart';
import '../db/daos/vehicles_dao.dart';
import '../models/audit_entry.dart';
import '../models/fuel_type.dart';
import '../models/vehicle.dart';
import 'repository_exceptions.dart';
import 'repository_support.dart';
import 'vehicle_repository.dart';

/// [VehicleRepository] backed by the local Drift database.
class DriftVehicleRepository implements VehicleRepository {
  /// Creates the repository on [_vehicles], auditing through [_audit].
  ///
  /// [clock] must return UTC; it defaults to the system clock.
  DriftVehicleRepository(
    this._vehicles,
    this._audit, {
    UtcClock clock = systemUtcClock,
  }) : _clock = clock;

  /// Vehicle queries.
  final VehiclesDao _vehicles;

  /// Audit log writes, joined to the same transaction as each change.
  final AuditLogDao _audit;

  /// Source of `created_at`, `updated_at` and audit timestamps.
  final UtcClock _clock;

  @override
  Stream<List<Vehicle>> watchAll() => _vehicles.watchLive();

  @override
  Future<List<Vehicle>> getAll() => _vehicles.getLive();

  @override
  Stream<List<Vehicle>> watchByOwner(String ownerId) =>
      _vehicles.watchLiveByOwner(ownerId);

  @override
  Future<List<Vehicle>> getByOwner(String ownerId) =>
      _vehicles.getLiveByOwner(ownerId);

  @override
  Future<Vehicle?> getById(String id) => _vehicles.getLiveById(id);

  @override
  Future<Vehicle> create({
    required String plate,
    String? nickname,
    required String ownerId,
    required int currentOdometerKm,
    required FuelType fuelType,
    String? recommendedEngineOil,
    String? manufacturerNotes,
    String? photoPath,
  }) async {
    if (currentOdometerKm < 0) {
      throw const InvalidFieldException(
        'currentOdometerKm',
        'must not be negative',
      );
    }
    final now = utcNow(_clock);
    final vehicle = Vehicle(
      id: newId(),
      plate: normalisePlate(plate),
      nickname: trimToNull(nickname),
      ownerId: ownerId,
      currentOdometerKm: currentOdometerKm,
      fuelType: fuelType,
      recommendedEngineOil: trimToNull(recommendedEngineOil),
      manufacturerNotes: trimToNull(manufacturerNotes),
      photoPath: trimToNull(photoPath),
      createdAt: now,
      updatedAt: now,
    );
    return _vehicles.transaction(() async {
      await _checkOwnerAndPlate(vehicle);
      await _vehicles.insertVehicle(vehicle);
      await _record(vehicle.id, AuditOperation.create, now);
      return vehicle;
    });
  }

  @override
  Future<Vehicle> update(
    String id, {
    required String plate,
    String? nickname,
    required String ownerId,
    required FuelType fuelType,
    String? recommendedEngineOil,
    String? manufacturerNotes,
    String? photoPath,
  }) async {
    final cleanPlate = normalisePlate(plate);
    final now = utcNow(_clock);
    return _vehicles.transaction(() async {
      final current = await _requireLive(id);
      final updated = current.copyWith(
        plate: cleanPlate,
        nickname: trimToNull(nickname),
        ownerId: ownerId,
        fuelType: fuelType,
        recommendedEngineOil: trimToNull(recommendedEngineOil),
        manufacturerNotes: trimToNull(manufacturerNotes),
        photoPath: trimToNull(photoPath),
        updatedAt: now,
      );
      await _checkOwnerAndPlate(updated);
      await _vehicles.updateLive(updated);
      await _record(id, AuditOperation.update, now);
      return updated;
    });
  }

  @override
  Future<void> delete(String id) async {
    final now = utcNow(_clock);
    return _vehicles.transaction(() async {
      await _requireLive(id);
      await _vehicles.softDeleteLive(id, now);
      await _record(id, AuditOperation.delete, now);
    });
  }

  /// Trims [plate] and upper-cases it, refusing a blank one.
  static String normalisePlate(String plate) =>
      requireText(plate, 'plate').toUpperCase();

  /// Refuses [vehicle] if its owner is not live or its plate is taken by
  /// another live vehicle.
  Future<void> _checkOwnerAndPlate(Vehicle vehicle) async {
    if (!await _vehicles.isOwnerLive(vehicle.ownerId)) {
      throw EntityNotFoundException(AuditEntityType.owner, vehicle.ownerId);
    }
    if (await _vehicles.isPlateUsedByLive(
      vehicle.plate,
      exceptId: vehicle.id,
    )) {
      throw DuplicatePlateException(vehicle.plate);
    }
  }

  /// Returns the live vehicle with [id] or throws [EntityNotFoundException].
  Future<Vehicle> _requireLive(String id) async {
    final vehicle = await _vehicles.getLiveById(id);
    if (vehicle == null) {
      throw EntityNotFoundException(AuditEntityType.vehicle, id);
    }
    return vehicle;
  }

  /// Appends the audit entry for [operation] on the vehicle with [id].
  Future<void> _record(String id, AuditOperation operation, DateTime at) {
    return _audit.insertEntry(
      AuditEntry(
        id: newId(),
        entityType: AuditEntityType.vehicle,
        entityId: id,
        operation: operation,
        at: at,
      ),
    );
  }
}
