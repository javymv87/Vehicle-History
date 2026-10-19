import '../db/daos/audit_log_dao.dart';
import '../db/daos/mileage_readings_dao.dart';
import '../db/daos/trash_dao.dart';
import '../db/daos/vehicles_dao.dart';
import '../models/audit_entry.dart';
import '../models/fuel_type.dart';
import '../models/mileage_reading.dart';
import '../models/trashed_vehicle.dart';
import '../models/vehicle.dart';
import '../models/vehicle_kind.dart';
import 'repository_exceptions.dart';
import 'repository_support.dart';
import 'vehicle_repository.dart';

/// [VehicleRepository] backed by the local Drift database.
class DriftVehicleRepository implements VehicleRepository {
  /// Creates the repository on [_vehicles], writing the initial odometer
  /// reading through [_readings], reading and emptying the Trash through
  /// [_trash] and auditing through [_audit].
  ///
  /// [clock] must return UTC; it defaults to the system clock.
  DriftVehicleRepository(
    this._vehicles,
    this._readings,
    this._trash,
    this._audit, {
    UtcClock clock = systemUtcClock,
  }) : _clock = clock;

  /// Vehicle queries.
  final VehiclesDao _vehicles;

  /// Odometer readings, for the initial reading of a new vehicle.
  final MileageReadingsDao _readings;

  /// Soft-deleted vehicles and the physical deletes.
  final TrashDao _trash;

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
    required VehicleKind kind,
    String? make,
    String? makeSlug,
    String? model,
    String? modelSlug,
    int? modelYear,
    String? version,
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
    final identity = _Identity.clean(
      make: make,
      makeSlug: makeSlug,
      model: model,
      modelSlug: modelSlug,
      modelYear: modelYear,
      version: version,
    );
    final now = utcNow(_clock);
    final vehicle = Vehicle(
      id: newId(),
      plate: normalisePlate(plate),
      kind: kind,
      make: identity.make,
      makeSlug: identity.makeSlug,
      model: identity.model,
      modelSlug: identity.modelSlug,
      modelYear: identity.modelYear,
      version: identity.version,
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
    // Every vehicle starts its odometer history with the km typed in the
    // form, dated today: its initial reading.
    final initialReading = MileageReading(
      id: newId(),
      vehicleId: vehicle.id,
      date: localToday(_clock),
      km: currentOdometerKm,
      createdAt: now,
      updatedAt: now,
    );
    return _vehicles.transaction(() async {
      await _checkOwnerAndPlate(vehicle);
      await _vehicles.insertVehicle(vehicle);
      await _readings.insertReading(initialReading);
      await _record(vehicle.id, AuditOperation.create, now);
      await _audit.insertEntry(
        AuditEntry(
          id: newId(),
          entityType: AuditEntityType.mileageReading,
          entityId: initialReading.id,
          operation: AuditOperation.create,
          at: now,
        ),
      );
      return vehicle;
    });
  }

  @override
  Future<Vehicle> update(
    String id, {
    required String plate,
    required VehicleKind kind,
    String? make,
    String? makeSlug,
    String? model,
    String? modelSlug,
    int? modelYear,
    String? version,
    String? nickname,
    required String ownerId,
    required FuelType fuelType,
    String? recommendedEngineOil,
    String? manufacturerNotes,
    String? photoPath,
  }) async {
    final cleanPlate = normalisePlate(plate);
    final identity = _Identity.clean(
      make: make,
      makeSlug: makeSlug,
      model: model,
      modelSlug: modelSlug,
      modelYear: modelYear,
      version: version,
    );
    final now = utcNow(_clock);
    return _vehicles.transaction(() async {
      final current = await _requireLive(id);
      final updated = current.copyWith(
        plate: cleanPlate,
        kind: kind,
        make: identity.make,
        makeSlug: identity.makeSlug,
        model: identity.model,
        modelSlug: identity.modelSlug,
        modelYear: identity.modelYear,
        version: identity.version,
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
  Future<VehicleContents> countContents(String id) async {
    await _requireLive(id);
    return _trash.countLiveContents(id);
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

  @override
  Future<Vehicle> restore(String id) async {
    final now = utcNow(_clock);
    return _vehicles.transaction(() async {
      final deleted = await _vehicles.getDeletedById(id);
      if (deleted == null) {
        throw EntityNotFoundException(AuditEntityType.vehicle, id);
      }
      // The owner may have been deleted, or the plate reused, since then.
      await _checkOwnerAndPlate(deleted);
      await _vehicles.restoreDeleted(id, now);
      await _record(id, AuditOperation.restore, now);
      return deleted.copyWith(updatedAt: now);
    });
  }

  @override
  Stream<List<TrashedVehicle>> watchTrashed() => _trash.watchTrashedVehicles();

  @override
  Future<void> purge(String id) async {
    final now = utcNow(_clock);
    return _vehicles.transaction(() async {
      final removed = await _trash.purgeVehicle(id);
      if (removed == 0) {
        throw EntityNotFoundException(AuditEntityType.vehicle, id);
      }
      await _record(id, AuditOperation.purge, now);
    });
  }

  @override
  Future<int> purgeAllTrashed() async {
    final now = utcNow(_clock);
    return _vehicles.transaction(() async {
      final ids = await _trash.getTrashedVehicleIds();
      for (final id in ids) {
        await _trash.purgeVehicle(id);
        await _record(id, AuditOperation.purge, now);
      }
      return ids.length;
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

/// The make / model fields of a vehicle, validated and trimmed.
class _Identity {
  const _Identity._({
    required this.make,
    required this.makeSlug,
    required this.model,
    required this.modelSlug,
    required this.modelYear,
    required this.version,
  });

  /// Trims the text fields (blank becomes `null`) and checks the rules that
  /// span them: a slug needs its name, and the year must be plausible.
  ///
  /// Throws [InvalidFieldException] when a rule is broken.
  factory _Identity.clean({
    required String? make,
    required String? makeSlug,
    required String? model,
    required String? modelSlug,
    required int? modelYear,
    required String? version,
  }) {
    final identity = _Identity._(
      make: trimToNull(make),
      makeSlug: trimToNull(makeSlug),
      model: trimToNull(model),
      modelSlug: trimToNull(modelSlug),
      modelYear: modelYear,
      version: trimToNull(version),
    );
    if (identity.makeSlug != null && identity.make == null) {
      throw const InvalidFieldException('makeSlug', 'needs a make name');
    }
    if (identity.modelSlug != null && identity.model == null) {
      throw const InvalidFieldException('modelSlug', 'needs a model name');
    }
    if (modelYear != null &&
        (modelYear < minModelYear || modelYear > maxModelYear)) {
      throw const InvalidFieldException(
        'modelYear',
        'must be between $minModelYear and $maxModelYear',
      );
    }
    return identity;
  }

  final String? make;
  final String? makeSlug;
  final String? model;
  final String? modelSlug;
  final int? modelYear;
  final String? version;
}
