import '../db/daos/audit_log_dao.dart';
import '../db/daos/owners_dao.dart';
import '../models/audit_entry.dart';
import '../models/calendar_date.dart';
import '../models/owner.dart';
import 'owner_repository.dart';
import 'repository_exceptions.dart';
import 'repository_support.dart';

/// [OwnerRepository] backed by the local Drift database.
class DriftOwnerRepository implements OwnerRepository {
  /// Creates the repository on [_owners], auditing through [_audit].
  ///
  /// [clock] must return UTC; it defaults to the system clock.
  DriftOwnerRepository(
    this._owners,
    this._audit, {
    UtcClock clock = systemUtcClock,
  }) : _clock = clock;

  /// Owner queries.
  final OwnersDao _owners;

  /// Audit log writes, joined to the same transaction as each change.
  final AuditLogDao _audit;

  /// Source of `created_at`, `updated_at` and audit timestamps.
  final UtcClock _clock;

  @override
  Stream<List<Owner>> watchAll() => _owners.watchLive();

  @override
  Future<List<Owner>> getAll() => _owners.getLive();

  @override
  Future<Owner?> getById(String id) => _owners.getLiveById(id);

  @override
  Future<Owner> create({
    required String firstName,
    String? lastName,
    CalendarDate? birthDate,
    String? nationality,
    String? phone,
    String? email,
    String? notes,
    String? photoPath,
  }) async {
    final now = utcNow(_clock);
    final owner = Owner(
      id: newId(),
      firstName: requireText(firstName, 'firstName'),
      lastName: trimToNull(lastName),
      birthDate: birthDate,
      nationality: trimToNull(nationality),
      phone: trimToNull(phone),
      email: trimToNull(email),
      notes: trimToNull(notes),
      photoPath: trimToNull(photoPath),
      createdAt: now,
      updatedAt: now,
    );
    return _owners.transaction(() async {
      await _owners.insertOwner(owner);
      await _record(owner.id, AuditOperation.create, now);
      return owner;
    });
  }

  @override
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
  }) async {
    final cleanFirstName = requireText(firstName, 'firstName');
    final now = utcNow(_clock);
    return _owners.transaction(() async {
      final current = await _requireLive(id);
      final updated = current.copyWith(
        firstName: cleanFirstName,
        lastName: trimToNull(lastName),
        birthDate: birthDate,
        nationality: trimToNull(nationality),
        phone: trimToNull(phone),
        email: trimToNull(email),
        notes: trimToNull(notes),
        photoPath: trimToNull(photoPath),
        updatedAt: now,
      );
      await _owners.updateLive(updated);
      await _record(id, AuditOperation.update, now);
      return updated;
    });
  }

  @override
  Future<void> delete(String id) async {
    final now = utcNow(_clock);
    return _owners.transaction(() async {
      await _requireLive(id);
      final vehicleCount = await _owners.countLiveVehicles(id);
      if (vehicleCount > 0) {
        throw OwnerHasVehiclesException(id, vehicleCount);
      }
      // A vehicle in the Trash can still be restored, which needs its
      // owner: the owner goes only once the Trash no longer holds any.
      final trashedCount = await _owners.countTrashedVehicles(id);
      if (trashedCount > 0) {
        throw OwnerHasTrashedVehiclesException(id, trashedCount);
      }
      await _owners.softDeleteLive(id, now);
      await _record(id, AuditOperation.delete, now);
    });
  }

  @override
  Future<Owner> restore(String id) async {
    final now = utcNow(_clock);
    return _owners.transaction(() async {
      final changed = await _owners.restoreDeleted(id, now);
      if (changed == 0) {
        throw EntityNotFoundException(AuditEntityType.owner, id);
      }
      await _record(id, AuditOperation.restore, now);
      return _requireLive(id);
    });
  }

  /// Returns the live owner with [id] or throws [EntityNotFoundException].
  Future<Owner> _requireLive(String id) async {
    final owner = await _owners.getLiveById(id);
    if (owner == null) {
      throw EntityNotFoundException(AuditEntityType.owner, id);
    }
    return owner;
  }

  /// Appends the audit entry for [operation] on the owner with [id].
  Future<void> _record(String id, AuditOperation operation, DateTime at) {
    return _audit.insertEntry(
      AuditEntry(
        id: newId(),
        entityType: AuditEntityType.owner,
        entityId: id,
        operation: operation,
        at: at,
      ),
    );
  }
}
