import '../db/daos/audit_log_dao.dart';
import '../db/daos/log_entries_dao.dart';
import '../db/vehicle_state.dart';
import '../models/attachment.dart';
import '../models/audit_entry.dart';
import '../models/calendar_date.dart';
import '../models/log_entry.dart';
import '../models/log_entry_filter.dart';
import '../models/log_entry_type.dart';
import 'attachment_writer.dart';
import 'log_entry_repository.dart';
import 'repository_exceptions.dart';
import 'repository_support.dart';

/// [LogEntryRepository] backed by the local Drift database.
class DriftLogEntryRepository implements LogEntryRepository {
  /// Creates the repository on [_entries], auditing through [_audit] and
  /// saving the files picked in the entry form through [attachments].
  ///
  /// [clock] must return UTC; it defaults to the system clock.
  DriftLogEntryRepository(
    this._entries,
    this._audit, {
    required AttachmentWriter attachments,
    UtcClock clock = systemUtcClock,
  })  : _attachments = attachments,
        _clock = clock;

  /// Entry queries.
  final LogEntriesDao _entries;

  /// Audit log writes, joined to the same transaction as each change.
  final AuditLogDao _audit;

  /// Attachment writes joined to the entry's transaction.
  final AttachmentWriter _attachments;

  /// Source of `created_at`, `updated_at` and audit timestamps.
  final UtcClock _clock;

  @override
  Stream<List<LogEntry>> watchByVehicle(
    String vehicleId, {
    LogEntryFilter filter = LogEntryFilter.none,
  }) {
    // Date range and types run in SQL, on the (vehicle_id, entry_date) and
    // (vehicle_id, type) indexes. The text runs in Dart: SQLite's LIKE and
    // lower() ignore neither accents nor non-ASCII case.
    final rows = _entries.watchLiveByVehicle(
      vehicleId,
      from: filter.from,
      to: filter.to,
      types: filter.types,
    );
    if (!filter.hasText) return rows;
    return rows.map(
      (entries) => [
        for (final entry in entries)
          if (filter.matchesText(entry.description)) entry,
      ],
    );
  }

  @override
  Future<LogEntry?> getById(String id) => _entries.getLiveById(id);

  @override
  Stream<LogEntry?> watchById(String id) => _entries.watchLiveById(id);

  @override
  Future<LogEntry> create({
    required String vehicleId,
    required CalendarDate date,
    int? km,
    required LogEntryType type,
    String? description,
    int? costCents,
    List<StagedFile> attachments = const [],
  }) async {
    final now = utcNow(_clock);
    _checkValues(
      type: type,
      date: date,
      today: localToday(_clock),
      km: km,
      costCents: costCents,
    );
    attachments.forEach(AttachmentWriter.checkSize);
    final entry = LogEntry(
      id: newId(),
      vehicleId: vehicleId,
      date: date,
      km: km,
      type: type,
      description: trimToNull(description),
      costCents: costCents,
      createdAt: now,
      updatedAt: now,
    );
    return _attachments.runWithMovedFiles(
      (moved) => _entries.transaction(() async {
        await _requireActiveVehicle(vehicleId);
        await _entries.insertEntry(entry);
        await _record(entry.id, AuditOperation.create, now);
        await _attachments.addStaged(
          AttachmentTarget.logEntry(entry.id),
          attachments,
          now,
          moved,
        );
        return entry;
      }),
    );
  }

  @override
  Future<LogEntry> update(
    String id, {
    required CalendarDate date,
    int? km,
    required LogEntryType type,
    String? description,
    int? costCents,
    List<StagedFile> addedAttachments = const [],
    Set<String> removedAttachmentIds = const {},
  }) async {
    final now = utcNow(_clock);
    _checkValues(
      type: type,
      date: date,
      today: localToday(_clock),
      km: km,
      costCents: costCents,
    );
    addedAttachments.forEach(AttachmentWriter.checkSize);
    final target = AttachmentTarget.logEntry(id);
    return _attachments.runWithMovedFiles(
      (moved) => _entries.transaction(() async {
        final current = await _requireLive(id);
        await _requireActiveVehicle(current.vehicleId);
        final updated = current.copyWith(
          date: date,
          km: km,
          type: type,
          description: trimToNull(description),
          costCents: costCents,
          updatedAt: now,
        );
        await _entries.updateLive(updated);
        await _record(id, AuditOperation.update, now);
        for (final attachmentId in removedAttachmentIds) {
          await _attachments.softDelete(target, attachmentId, now);
        }
        await _attachments.addStaged(target, addedAttachments, now, moved);
        return updated;
      }),
    );
  }

  @override
  Future<void> delete(String id) async {
    final now = utcNow(_clock);
    return _entries.transaction(() async {
      final current = await _requireLive(id);
      await _requireActiveVehicle(current.vehicleId);
      await _entries.softDeleteLive(id, now);
      await _record(id, AuditOperation.delete, now);
    });
  }

  @override
  Future<LogEntry> restore(String id) async {
    final now = utcNow(_clock);
    return _entries.transaction(() async {
      final deleted = await _entries.getDeletedById(id);
      if (deleted == null) {
        throw EntityNotFoundException(AuditEntityType.logEntry, id);
      }
      // The vehicle may have been deleted or archived since: the entry would
      // come back invisible or read-only, so the undo is refused instead.
      await _requireActiveVehicle(deleted.vehicleId);
      await _entries.restoreDeleted(id, now);
      await _record(id, AuditOperation.restore, now);
      return deleted.copyWith(updatedAt: now);
    });
  }

  /// Refuses values the form should already have caught: a missing km for a
  /// type that requires it, a negative km, a negative cost, and a date after
  /// [today] for a type that does not allow one.
  ///
  /// Throws [InvalidFieldException]. Enforced here too so no caller can
  /// write an entry that breaks the rules of `Docs/02_data_model.md`.
  static void _checkValues({
    required LogEntryType type,
    required CalendarDate date,
    required CalendarDate today,
    required int? km,
    required int? costCents,
  }) {
    if (!type.allowsFutureDate && date.isAfter(today)) {
      throw const InvalidFieldException('date', InvalidFieldException.inFuture);
    }
    if (km == null && type.requiresKm) {
      throw InvalidFieldException('km', 'required for ${type.name}');
    }
    if (km != null && km < 0) {
      throw const InvalidFieldException('km', 'must not be negative');
    }
    if (costCents != null && costCents < 0) {
      throw const InvalidFieldException('costCents', 'must not be negative');
    }
  }

  /// Throws [EntityNotFoundException] unless the vehicle with [vehicleId] is
  /// live, and [VehicleArchivedException] when it is archived: its entries
  /// are read-only then.
  Future<void> _requireActiveVehicle(String vehicleId) async {
    switch (await _entries.vehicleStateOf(vehicleId)) {
      case VehicleState.active:
        return;
      case VehicleState.archived:
        throw VehicleArchivedException(AuditEntityType.vehicle, vehicleId);
      case VehicleState.absent:
        throw EntityNotFoundException(AuditEntityType.vehicle, vehicleId);
    }
  }

  /// Returns the live entry with [id] or throws [EntityNotFoundException].
  Future<LogEntry> _requireLive(String id) async {
    final entry = await _entries.getLiveById(id);
    if (entry == null) {
      throw EntityNotFoundException(AuditEntityType.logEntry, id);
    }
    return entry;
  }

  /// Appends the audit entry for [operation] on the entry with [id].
  Future<void> _record(String id, AuditOperation operation, DateTime at) {
    return _audit.insertEntry(
      AuditEntry(
        id: newId(),
        entityType: AuditEntityType.logEntry,
        entityId: id,
        operation: operation,
        at: at,
      ),
    );
  }
}
