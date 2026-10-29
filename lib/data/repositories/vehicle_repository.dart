import '../models/archive_reason.dart';
import '../models/calendar_date.dart';
import '../models/fuel_type.dart';
import '../models/trashed_vehicle.dart';
import '../models/vehicle.dart';
import '../models/vehicle_kind.dart';

/// Lowest model year the database accepts: the first automobile (1886).
const int minModelYear = 1886;

/// Highest model year the database accepts. The form is stricter (at most
/// next year); this bound only stops nonsense from reaching the disk.
const int maxModelYear = 2100;

/// The only access path to persisted vehicles.
///
/// Reads return live vehicles only, except the Trash methods
/// ([watchTrashed], [purge], [purgeAllTrashed]), which work on soft-deleted
/// ones. A live vehicle is *active* or *archived* (`Vehicle.isArchived`,
/// `Docs/02_data_model.md`, "Archivo"): [watchActive] is the one read of
/// the "current" vehicles, [watchArchived] the archived list, and the
/// per-id and per-owner reads return both. An archived vehicle is
/// read-only: [update] and every write on its entries, readings and
/// attachments throw `VehicleArchivedException`; only [reactivate],
/// [delete] and [restore] remain. Every write is recorded in the audit log
/// in the same transaction. Errors are reported as `RepositoryException`
/// subtypes (see `repository_exceptions.dart`).
abstract interface class VehicleRepository {
  /// Emits the active vehicles (live and not archived) now and after every
  /// change, ordered by plate: the main list.
  Stream<List<Vehicle>> watchActive();

  /// Returns the active vehicles, ordered by plate.
  Future<List<Vehicle>> getActive();

  /// Emits the archived vehicles that are not in the Trash, now and after
  /// every change, most recently archived first.
  Stream<List<Vehicle>> watchArchived();

  /// Emits the live vehicles of the owner with [ownerId], active and
  /// archived, ordered by plate.
  Stream<List<Vehicle>> watchByOwner(String ownerId);

  /// Returns the live vehicles of the owner with [ownerId], active and
  /// archived, ordered by plate.
  Future<List<Vehicle>> getByOwner(String ownerId);

  /// Returns the live vehicle with [id], active or archived, or `null` if
  /// missing or deleted.
  Future<Vehicle?> getById(String id);

  /// Emits what [getById] returns, now and after every change.
  Stream<Vehicle?> watchById(String id);

  /// Creates a vehicle and returns it with its id and timestamps set.
  ///
  /// In the same transaction it adds the vehicle's initial odometer reading:
  /// [currentOdometerKm], dated today.
  ///
  /// [plate] is stored trimmed and upper-case; other text fields are trimmed,
  /// and optional ones left blank are stored as `null`.
  ///
  /// [make] and [model] are the names shown to the user; [makeSlug] and
  /// [modelSlug] are their catalogue ids, `null` when typed by hand. A slug
  /// is meaningful only next to its name. The repository does not require a
  /// make or model (vehicles from schema v1 have none); the form does.
  ///
  /// Throws `InvalidFieldException` when [plate] is blank,
  /// [currentOdometerKm] is negative, [modelYear] is outside 1886–2100, or a
  /// slug is given without its name, `DuplicatePlateException` when another
  /// live vehicle has the same plate, and `EntityNotFoundException` when the
  /// owner is missing or deleted.
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
  });

  /// Replaces every user-editable field of the vehicle with [id] and returns
  /// the updated vehicle. Passing `null` clears an optional field.
  ///
  /// The odometer is deliberately not a parameter: changing it belongs to the
  /// mileage feature (`MileageReading`), never to the vehicle form.
  ///
  /// Throws the same errors as [create], `EntityNotFoundException` when
  /// the vehicle itself is missing or deleted, and `VehicleArchivedException`
  /// when it is archived.
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
  });

  /// Archives the active vehicle with [id] on [date] for [reason], with an
  /// optional [note] and the optional final [km], and returns it.
  ///
  /// When [km] is given, the archive first adds an odometer reading of [km]
  /// on [date] through `MileageReadingRepository.create`, in the same
  /// transaction and under the same rules as a reading added by hand (km
  /// not below the last reading, day not before it nor after today); a
  /// refused reading refuses the whole archive. [km] is also stored on the
  /// vehicle as its snapshot (`archivedKm`). Without [km] no reading is
  /// added. Recorded in the audit log as an `archive`.
  ///
  /// Throws `InvalidFieldException` for a refused reading or a [date] after
  /// today, `EntityNotFoundException` when the vehicle is missing or
  /// deleted, and `VehicleArchivedException` when it is already archived.
  Future<Vehicle> archive(
    String id, {
    required ArchiveReason reason,
    required CalendarDate date,
    double? km,
    String? note,
  });

  /// Reactivates the archived vehicle with [id]: clears its archive fields
  /// and returns it. Its readings, the one added by [archive] included, are
  /// left as they are. Recorded in the audit log as a `reactivate`.
  ///
  /// Throws `EntityNotFoundException` when the vehicle is missing or
  /// deleted, and `InvalidFieldException` when it is not archived.
  Future<Vehicle> reactivate(String id);

  /// Counts the live entries and readings of the live vehicle with [id]:
  /// what a delete would hide (and a restore bring back).
  ///
  /// Throws `EntityNotFoundException` if the vehicle is missing or deleted.
  Future<VehicleContents> countContents(String id);

  /// Soft-deletes the vehicle with [id], recording when (`deleted_at`): it
  /// moves to the Trash with its entries and readings. Its plate becomes
  /// free for reuse.
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
  ///
  /// It is also how a vehicle comes back from the Trash: to the archived
  /// list when it was archived, to the main list otherwise.
  Future<Vehicle> restore(String id);

  /// Emits the vehicles in the Trash (soft-deleted), most recently deleted
  /// first, each with its owner and its live entry and reading counts.
  Stream<List<TrashedVehicle>> watchTrashed();

  /// Removes the vehicle with [id] from the Trash for good: the vehicle and
  /// every one of its entries and readings, whatever their own flags, in
  /// one transaction. Irreversible. Recorded in the audit log as a `purge`
  /// of the vehicle; its older audit rows stay.
  ///
  /// Throws `EntityNotFoundException` if no vehicle with [id] is in the
  /// Trash (a live vehicle is never purged).
  Future<void> purge(String id);

  /// Empties the Trash: [purge] for every vehicle in it, in one transaction.
  /// Returns how many vehicles were removed.
  Future<int> purgeAllTrashed();
}
