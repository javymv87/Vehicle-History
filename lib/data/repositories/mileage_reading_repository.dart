import '../models/calendar_date.dart';
import '../models/mileage_reading.dart';
import '../models/odometer_checks.dart';

/// The only access path to persisted odometer readings.
///
/// Every vehicle has at least one live reading, its initial one (the
/// oldest), and `Vehicle.currentOdometerKm` always equals the km of its last
/// live reading: every write here updates it in the same transaction.
/// Readings of a deleted vehicle are kept as they are and not visible.
/// Every write is recorded in the audit log in the same transaction. Errors
/// are reported as `RepositoryException` subtypes (see
/// `repository_exceptions.dart`).
abstract interface class MileageReadingRepository {
  /// Emits the readings of the vehicle with [vehicleId] now and after every
  /// change, newest first: by day, then by creation instant within the same
  /// day. The last element is the initial reading. Emits an empty list for a
  /// vehicle that is missing or deleted.
  Stream<List<MileageReading>> watchByVehicle(String vehicleId);

  /// Returns the same readings as [watchByVehicle] once.
  Future<List<MileageReading>> getByVehicle(String vehicleId);

  /// Returns the last reading of the vehicle with [vehicleId], or `null`
  /// when the vehicle is missing or deleted.
  Future<MileageReading?> getLast(String vehicleId);

  /// Adds a reading of [km] on [date] to the vehicle with [vehicleId], makes
  /// it the vehicle's current km, and returns it.
  ///
  /// Throws `InvalidFieldException` when [km] is negative or below the last
  /// reading (`belowLastReading`; equal is allowed), or [date] is after
  /// today (`inFuture`) or before the last reading (`beforeLastReading`), and
  /// `EntityNotFoundException` when the vehicle is missing or deleted. A
  /// [km] far above the last reading ([bigOdometerJumpKm]) is accepted.
  Future<MileageReading> create({
    required String vehicleId,
    required CalendarDate date,
    required double km,
  });

  /// Corrects the km and the day of the reading with [id], which must be the
  /// only live reading of its vehicle (its initial one), and returns it.
  ///
  /// Throws `MileageReadingRuleException` (`notSoleReading`) when the
  /// vehicle has more readings, `InvalidFieldException` when [km] is
  /// negative or [date] is after today, and `EntityNotFoundException` when
  /// the reading or its vehicle is missing or deleted.
  Future<MileageReading> updateInitial(
    String id, {
    required CalendarDate date,
    required double km,
  });

  /// Soft-deletes the reading with [id], which must be the last one and not
  /// the initial one; the previous reading becomes the current km.
  ///
  /// Throws `MileageReadingRuleException` (`notLast` or `initial`), and
  /// `EntityNotFoundException` when the reading or its vehicle is missing or
  /// deleted.
  Future<void> deleteLast(String id);

  /// Brings back the soft-deleted reading with [id], as "Undo" after
  /// [deleteLast], makes it the current km again, and returns it.
  ///
  /// Recorded in the audit log as a `restore`. Throws
  /// `MileageReadingRuleException` (`newerReadingExists`) when a more recent
  /// reading was added in the meantime, and `EntityNotFoundException` when
  /// no deleted reading has that id or its vehicle has been deleted. Nothing
  /// is written then.
  Future<MileageReading> restore(String id);
}
