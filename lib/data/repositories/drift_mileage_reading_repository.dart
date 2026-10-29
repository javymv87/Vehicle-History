import '../db/daos/audit_log_dao.dart';
import '../db/daos/mileage_readings_dao.dart';
import '../db/vehicle_state.dart';
import '../models/audit_entry.dart';
import '../models/calendar_date.dart';
import '../models/mileage_reading.dart';
import 'mileage_reading_repository.dart';
import 'repository_exceptions.dart';
import 'repository_support.dart';

/// [MileageReadingRepository] backed by the local Drift database.
class DriftMileageReadingRepository implements MileageReadingRepository {
  /// Creates the repository on [_readings], auditing through [_audit].
  ///
  /// [clock] must return UTC; it defaults to the system clock. "Today" is
  /// the local day of its instant.
  DriftMileageReadingRepository(
    this._readings,
    this._audit, {
    UtcClock clock = systemUtcClock,
  }) : _clock = clock;

  /// Reading queries and the odometer cache of the vehicles.
  final MileageReadingsDao _readings;

  /// Audit log writes, joined to the same transaction as each change.
  final AuditLogDao _audit;

  /// Source of `created_at`, `updated_at`, audit timestamps and "today".
  final UtcClock _clock;

  @override
  Stream<List<MileageReading>> watchByVehicle(String vehicleId) =>
      _readings.watchLiveByVehicle(vehicleId);

  @override
  Future<List<MileageReading>> getByVehicle(String vehicleId) =>
      _readings.getLiveByVehicle(vehicleId);

  @override
  Future<MileageReading?> getLast(String vehicleId) =>
      _readings.getLastLive(vehicleId);

  @override
  Future<MileageReading> create({
    required String vehicleId,
    required CalendarDate date,
    required double km,
  }) async {
    final now = utcNow(_clock);
    _checkKmAndDate(km: km, date: date, today: localToday(_clock));
    final reading = MileageReading(
      id: newId(),
      vehicleId: vehicleId,
      date: date,
      km: km,
      createdAt: now,
      updatedAt: now,
    );
    return _readings.transaction(() async {
      await _requireActiveVehicle(vehicleId);
      final last = await _readings.getLastLive(vehicleId);
      if (last != null) {
        if (date.isBefore(last.date)) {
          throw const InvalidFieldException(
            'date',
            InvalidFieldException.beforeLastReading,
          );
        }
        if (km < last.km) {
          throw const InvalidFieldException(
            'km',
            InvalidFieldException.belowLastReading,
          );
        }
      }
      await _readings.insertReading(reading);
      await _readings.setVehicleOdometer(vehicleId, km);
      await _record(reading.id, AuditOperation.create, now);
      return reading;
    });
  }

  @override
  Future<MileageReading> updateInitial(
    String id, {
    required CalendarDate date,
    required double km,
  }) async {
    final now = utcNow(_clock);
    _checkKmAndDate(km: km, date: date, today: localToday(_clock));
    return _readings.transaction(() async {
      final current = await _requireLive(id);
      await _requireActiveVehicle(current.vehicleId);
      if (await _readings.countLive(current.vehicleId) != 1) {
        throw MileageReadingRuleException(
          id,
          MileageReadingRule.notSoleReading,
        );
      }
      final updated = current.copyWith(date: date, km: km, updatedAt: now);
      await _readings.updateLive(updated);
      await _readings.setVehicleOdometer(current.vehicleId, km);
      await _record(id, AuditOperation.update, now);
      return updated;
    });
  }

  @override
  Future<void> deleteLast(String id) async {
    final now = utcNow(_clock);
    return _readings.transaction(() async {
      final reading = await _requireLive(id);
      await _requireActiveVehicle(reading.vehicleId);
      final all = await _readings.getLiveByVehicle(reading.vehicleId);
      // Newest first: the first is the last reading, the final one the
      // initial reading.
      if (all.first.id != id) {
        throw MileageReadingRuleException(id, MileageReadingRule.notLast);
      }
      if (all.length == 1) {
        throw MileageReadingRuleException(id, MileageReadingRule.initial);
      }
      await _readings.softDeleteLive(id, now);
      await _readings.setVehicleOdometer(reading.vehicleId, all[1].km);
      await _record(id, AuditOperation.delete, now);
    });
  }

  @override
  Future<MileageReading> restore(String id) async {
    final now = utcNow(_clock);
    return _readings.transaction(() async {
      final deleted = await _readings.getDeletedById(id);
      if (deleted == null) {
        throw EntityNotFoundException(AuditEntityType.mileageReading, id);
      }
      // The vehicle may have been deleted or archived since: the reading
      // would come back invisible or read-only, so the undo is refused.
      await _requireActiveVehicle(deleted.vehicleId);
      final last = await _readings.getLastLive(deleted.vehicleId);
      if (last != null && !deleted.isAfter(last)) {
        throw MileageReadingRuleException(
          id,
          MileageReadingRule.newerReadingExists,
        );
      }
      await _readings.restoreDeleted(id, now);
      await _readings.setVehicleOdometer(deleted.vehicleId, deleted.km);
      await _record(id, AuditOperation.restore, now);
      return deleted.copyWith(updatedAt: now);
    });
  }

  /// Refuses a negative [km] and a [date] after [today].
  ///
  /// Throws [InvalidFieldException]. The rules against the last reading
  /// need the database and are checked inside the transaction.
  static void _checkKmAndDate({
    required double km,
    required CalendarDate date,
    required CalendarDate today,
  }) {
    if (km < 0) {
      throw const InvalidFieldException('km', 'must not be negative');
    }
    if (date.isAfter(today)) {
      throw const InvalidFieldException('date', InvalidFieldException.inFuture);
    }
  }

  /// Throws [EntityNotFoundException] unless the vehicle with [vehicleId] is
  /// live, and [VehicleArchivedException] when it is archived: its readings
  /// are read-only then. The reading the archive itself inserts goes through
  /// `create` while the vehicle is still active, in the same transaction.
  Future<void> _requireActiveVehicle(String vehicleId) async {
    switch (await _readings.vehicleStateOf(vehicleId)) {
      case VehicleState.active:
        return;
      case VehicleState.archived:
        throw VehicleArchivedException(AuditEntityType.vehicle, vehicleId);
      case VehicleState.absent:
        throw EntityNotFoundException(AuditEntityType.vehicle, vehicleId);
    }
  }

  /// Returns the live reading with [id] of a live vehicle, or throws
  /// [EntityNotFoundException].
  Future<MileageReading> _requireLive(String id) async {
    final reading = await _readings.getLiveById(id);
    if (reading == null) {
      throw EntityNotFoundException(AuditEntityType.mileageReading, id);
    }
    return reading;
  }

  /// Appends the audit entry for [operation] on the reading with [id].
  Future<void> _record(String id, AuditOperation operation, DateTime at) {
    return _audit.insertEntry(
      AuditEntry(
        id: newId(),
        entityType: AuditEntityType.mileageReading,
        entityId: id,
        operation: operation,
        at: at,
      ),
    );
  }
}
