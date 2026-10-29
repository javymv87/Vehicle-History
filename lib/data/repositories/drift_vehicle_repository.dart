import '../attachments/attachment_store.dart';
import '../db/daos/audit_log_dao.dart';
import '../db/daos/mileage_readings_dao.dart';
import '../db/daos/trash_dao.dart';
import '../db/daos/vehicles_dao.dart';
import '../models/archive_reason.dart';
import '../models/audit_entry.dart';
import '../models/calendar_date.dart';
import '../models/fuel_type.dart';
import '../models/mileage_reading.dart';
import '../models/trashed_vehicle.dart';
import '../models/vehicle.dart';
import '../models/vehicle_kind.dart';
import 'mileage_reading_repository.dart';
import 'repository_exceptions.dart';
import 'repository_support.dart';
import 'vehicle_repository.dart';

/// [VehicleRepository] backed by the local Drift database.
class DriftVehicleRepository implements VehicleRepository {
  /// Creates the repository on [_vehicles], writing the initial odometer
  /// reading through [_readings] and the final reading of an archive
  /// through [readingRepository], reading and emptying the Trash through
  /// [_trash] and auditing through [_audit]. A purge deletes the files of
  /// the vehicle's attachments from [attachmentFiles] once committed.
  ///
  /// [clock] must return UTC; it defaults to the system clock.
  DriftVehicleRepository(
    this._vehicles,
    this._readings,
    this._trash,
    this._audit, {
    required MileageReadingRepository readingRepository,
    required AttachmentStore attachmentFiles,
    UtcClock clock = systemUtcClock,
  })  : _readingRepository = readingRepository,
        _files = attachmentFiles,
        _clock = clock;

  /// Vehicle queries.
  final VehiclesDao _vehicles;

  /// Odometer readings, for the initial reading of a new vehicle.
  final MileageReadingsDao _readings;

  /// The reading rules, for the final reading of an archive: the same code
  /// path as a reading added by hand, nested in the archive transaction.
  final MileageReadingRepository _readingRepository;

  /// Soft-deleted vehicles and the physical deletes.
  final TrashDao _trash;

  /// Audit log writes, joined to the same transaction as each change.
  final AuditLogDao _audit;

  /// The attachment files, deleted after a purge.
  final AttachmentStore _files;

  /// Source of `created_at`, `updated_at` and audit timestamps.
  final UtcClock _clock;

  @override
  Stream<List<Vehicle>> watchActive() => _vehicles.watchActive();

  @override
  Future<List<Vehicle>> getActive() => _vehicles.getActive();

  @override
  Stream<List<Vehicle>> watchArchived() => _vehicles.watchArchived();

  @override
  Stream<List<Vehicle>> watchByOwner(String ownerId) =>
      _vehicles.watchLiveByOwner(ownerId);

  @override
  Future<List<Vehicle>> getByOwner(String ownerId) =>
      _vehicles.getLiveByOwner(ownerId);

  @override
  Future<Vehicle?> getById(String id) => _vehicles.getLiveById(id);

  @override
  Stream<Vehicle?> watchById(String id) => _vehicles.watchLiveById(id);

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
    required double currentOdometerKm,
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
      final current = await _requireActive(id);
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
  Future<Vehicle> archive(
    String id, {
    required ArchiveReason reason,
    required CalendarDate date,
    double? km,
    String? note,
  }) async {
    final now = utcNow(_clock);
    // Without a reading nothing else checks the day, so it is checked here;
    // with one, the reading rules refuse it the same way.
    if (date.isAfter(localToday(_clock))) {
      throw const InvalidFieldException('date', InvalidFieldException.inFuture);
    }
    return _vehicles.transaction(() async {
      final current = await _requireActive(id);
      // The final reading, under the reading rules, while the vehicle is
      // still active: a nested transaction, so a refusal writes nothing.
      if (km != null) {
        await _readingRepository.create(vehicleId: id, date: date, km: km);
      }
      final cleanNote = trimToNull(note);
      await _vehicles.archiveLive(
        id,
        archivedAt: date,
        reason: reason,
        note: cleanNote,
        km: km,
        at: now,
      );
      await _record(id, AuditOperation.archive, now);
      return current.copyWith(
        archivedAt: date,
        archiveReason: reason,
        archiveNote: cleanNote,
        archivedKm: km,
        currentOdometerKm: km ?? current.currentOdometerKm,
        updatedAt: now,
      );
    });
  }

  @override
  Future<Vehicle> reactivate(String id) async {
    final now = utcNow(_clock);
    return _vehicles.transaction(() async {
      final current = await _requireLive(id);
      if (!current.isArchived) {
        throw const InvalidFieldException('archivedAt', 'is not archived');
      }
      await _vehicles.reactivateArchived(id, now);
      await _record(id, AuditOperation.reactivate, now);
      return current.copyWith(
        archivedAt: null,
        archiveReason: null,
        archiveNote: null,
        archivedKm: null,
        updatedAt: now,
      );
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
    final files = await _vehicles.transaction(() async {
      final files = await _trash.purgeVehicle(id);
      if (files == null) {
        throw EntityNotFoundException(AuditEntityType.vehicle, id);
      }
      await _record(id, AuditOperation.purge, now);
      return files;
    });
    // Only once the rows are gone for good: a rolled-back purge keeps them.
    await deleteFilesQuietly(_files, files);
  }

  @override
  Future<int> purgeAllTrashed() async {
    final now = utcNow(_clock);
    final files = <String>[];
    final count = await _vehicles.transaction(() async {
      files.clear();
      final ids = await _trash.getTrashedVehicleIds();
      for (final id in ids) {
        files.addAll(await _trash.purgeVehicle(id) ?? const []);
        await _record(id, AuditOperation.purge, now);
      }
      return ids.length;
    });
    await deleteFilesQuietly(_files, files);
    return count;
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

  /// Returns the live vehicle with [id], active or archived, or throws
  /// [EntityNotFoundException].
  Future<Vehicle> _requireLive(String id) async {
    final vehicle = await _vehicles.getLiveById(id);
    if (vehicle == null) {
      throw EntityNotFoundException(AuditEntityType.vehicle, id);
    }
    return vehicle;
  }

  /// Returns the active vehicle with [id], or throws
  /// [EntityNotFoundException] when it is missing or deleted and
  /// [VehicleArchivedException] when it is archived.
  Future<Vehicle> _requireActive(String id) async {
    final vehicle = await _requireLive(id);
    if (vehicle.isArchived) {
      throw VehicleArchivedException(AuditEntityType.vehicle, id);
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
