import '../models/calendar_date.dart';
import '../models/owner.dart';

/// The only access path to persisted owners.
///
/// Reads return live owners only. Every write is recorded in the audit log in
/// the same transaction. Errors are reported as `RepositoryException`
/// subtypes (see `repository_exceptions.dart`).
abstract interface class OwnerRepository {
  /// Emits all live owners now and after every change, ordered by name.
  Stream<List<Owner>> watchAll();

  /// Returns all live owners, ordered by name.
  Future<List<Owner>> getAll();

  /// Returns the live owner with [id], or `null` if missing or deleted.
  Future<Owner?> getById(String id);

  /// Creates an owner and returns it with its id and timestamps set.
  ///
  /// Text fields are trimmed; optional ones left blank are stored as `null`.
  /// Throws `InvalidFieldException` when [firstName] is blank.
  Future<Owner> create({
    required String firstName,
    String? lastName,
    CalendarDate? birthDate,
    String? nationality,
    String? phone,
    String? email,
    String? notes,
    String? photoPath,
  });

  /// Replaces every user-editable field of the owner with [id] and returns
  /// the updated owner. Passing `null` clears an optional field.
  ///
  /// Throws `EntityNotFoundException` if the owner is missing or deleted,
  /// and `InvalidFieldException` when [firstName] is blank.
  Future<Owner> update(
    String id, {
    required String firstName,
    String? lastName,
    CalendarDate? birthDate,
    String? nationality,
    String? phone,
    String? email,
    String? notes,
    String? photoPath,
  });

  /// Soft-deletes the owner with [id].
  ///
  /// Throws `OwnerHasVehiclesException`, writing nothing, while the owner
  /// still has live vehicles, and `EntityNotFoundException` if the owner is
  /// missing or already deleted.
  Future<void> delete(String id);

  /// Brings back the soft-deleted owner with [id], as "Undo" after [delete].
  ///
  /// Recorded in the audit log as a `restore`. Throws
  /// `EntityNotFoundException` if no deleted owner has that id.
  Future<Owner> restore(String id);
}
