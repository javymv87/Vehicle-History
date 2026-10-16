import '../models/fuel_type.dart';
import '../models/vehicle.dart';

/// The only access path to persisted vehicles.
///
/// Reads return live vehicles only. Every write is recorded in the audit log
/// in the same transaction. Errors are reported as `RepositoryException`
/// subtypes (see `repository_exceptions.dart`).
abstract interface class VehicleRepository {
  /// Emits all live vehicles now and after every change, ordered by plate.
  Stream<List<Vehicle>> watchAll();

  /// Returns all live vehicles, ordered by plate.
  Future<List<Vehicle>> getAll();

  /// Emits the live vehicles of the owner with [ownerId], ordered by plate.
  Stream<List<Vehicle>> watchByOwner(String ownerId);

  /// Returns the live vehicles of the owner with [ownerId], ordered by plate.
  Future<List<Vehicle>> getByOwner(String ownerId);

  /// Returns the live vehicle with [id], or `null` if missing or deleted.
  Future<Vehicle?> getById(String id);

  /// Creates a vehicle and returns it with its id and timestamps set.
  ///
  /// [plate] is stored trimmed and upper-case; other text fields are trimmed,
  /// and optional ones left blank are stored as `null`.
  ///
  /// Throws `InvalidFieldException` when [plate] is blank or
  /// [currentOdometerKm] is negative, `DuplicatePlateException` when another
  /// live vehicle has the same plate, and `EntityNotFoundException` when the
  /// owner is missing or deleted.
  Future<Vehicle> create({
    required String plate,
    String? nickname,
    required String ownerId,
    required int currentOdometerKm,
    required FuelType fuelType,
    String? recommendedEngineOil,
    String? manufacturerNotes,
    String? photoPath,
  });

  /// Replaces every user-editable field of the vehicle with [id] and returns
  /// the updated vehicle. Passing `null` clears an optional field.
  ///
  /// The odometer is deliberately not a parameter: changing it belongs to the
  /// mileage feature (`MileageReading`), never to the vehicle form.
  ///
  /// Throws the same errors as [create], and `EntityNotFoundException` when
  /// the vehicle itself is missing or deleted.
  Future<Vehicle> update(
    String id, {
    required String plate,
    String? nickname,
    required String ownerId,
    required FuelType fuelType,
    String? recommendedEngineOil,
    String? manufacturerNotes,
    String? photoPath,
  });

  /// Soft-deletes the vehicle with [id]. Its plate becomes free for reuse.
  ///
  /// Throws `EntityNotFoundException` if the vehicle is missing or already
  /// deleted.
  Future<void> delete(String id);

  /// Brings back the soft-deleted vehicle with [id], as "Undo" after
  /// [delete].
  ///
  /// Recorded in the audit log as a `restore`. Throws
  /// `EntityNotFoundException` if no deleted vehicle has that id or its owner
  /// is no longer live, and `DuplicatePlateException` if another live vehicle
  /// took the plate in the meantime.
  Future<Vehicle> restore(String id);
}
