import 'package:flutter/foundation.dart' show debugPrint;

import '../db/daos/audit_log_dao.dart';
import '../db/daos/trash_dao.dart';
import '../models/audit_entry.dart';
import '../models/trashed_vehicle.dart';
import 'repository_support.dart';

/// What one run of the startup cleanup removed from disk.
class CleanupReport {
  /// Creates the report.
  const CleanupReport({
    required this.vehicles,
    required this.entries,
    required this.readings,
    required this.owners,
  });

  /// Vehicles removed from the Trash, each with all its entries and
  /// readings (not counted in [entries] and [readings]).
  final int vehicles;

  /// Deleted entries of live vehicles removed.
  final int entries;

  /// Deleted readings of live vehicles removed.
  final int readings;

  /// Deleted owners, referenced by no vehicle row, removed.
  final int owners;

  @override
  String toString() => 'CleanupReport(vehicles: $vehicles, entries: $entries, '
      'readings: $readings, owners: $owners)';
}

/// Removes from disk what has been soft-deleted for longer than
/// [trashRetention] (`Docs/05_sync_and_storage.md`, "Papelera y limpieza").
///
/// Run once per app start, after the database is open and migrated (see
/// `databaseReadyProvider`).
class TrashCleanupService {
  /// Creates the service on [_trash], auditing through [_audit].
  TrashCleanupService(this._trash, this._audit);

  /// Soft-deleted rows and the physical deletes.
  final TrashDao _trash;

  /// Audit log writes, joined to the cleanup transaction.
  final AuditLogDao _audit;

  /// Removes, in one transaction, everything deleted at least
  /// [trashRetention] before [now] (UTC):
  ///
  /// 1. vehicles in the Trash, each with every entry and reading it has;
  /// 2. deleted entries and readings of live vehicles;
  /// 3. deleted owners that no vehicle row references any more (step 1 may
  ///    just have freed some).
  ///
  /// Vehicles and owners get a `purge` audit row; the entries and readings
  /// do not. Children of a vehicle still in the Trash are left alone: they
  /// go with their vehicle. If anything fails, the transaction rolls back,
  /// nothing is removed, and the error is rethrown.
  Future<CleanupReport> runStartupCleanup(DateTime now) async {
    if (!now.isUtc) {
      throw ArgumentError.value(now, 'now', 'must be a UTC DateTime');
    }
    final cutoff = now.subtract(trashRetention);
    // Exactly [trashRetention] old counts as expired.
    List<String> expired(List<DeletedRow> rows) => [
          for (final row in rows)
            if (!row.deletedAt.isAfter(cutoff)) row.id,
        ];

    return _trash.transaction(() async {
      final vehicles = expired(await _trash.getTrashedVehicles());
      for (final id in vehicles) {
        await _trash.purgeVehicle(id);
        await _record(AuditEntityType.vehicle, id, now);
      }

      final entries = expired(await _trash.getDeletedEntriesOfLiveVehicles());
      final removedEntries =
          entries.isEmpty ? 0 : await _trash.purgeEntries(entries);
      final readings = expired(await _trash.getDeletedReadingsOfLiveVehicles());
      final removedReadings =
          readings.isEmpty ? 0 : await _trash.purgeReadings(readings);

      final owners = expired(await _trash.getDeletedOwnersWithoutVehicles());
      for (final id in owners) {
        await _trash.purgeOwner(id);
        await _record(AuditEntityType.owner, id, now);
      }

      return CleanupReport(
        vehicles: vehicles.length,
        entries: removedEntries,
        readings: removedReadings,
        owners: owners.length,
      );
    });
  }

  /// Appends the `purge` audit entry of the entity [entityId].
  Future<void> _record(
    AuditEntityType entityType,
    String entityId,
    DateTime at,
  ) {
    return _audit.insertEntry(
      AuditEntry(
        id: newId(),
        entityType: entityType,
        entityId: entityId,
        operation: AuditOperation.purge,
        at: at,
      ),
    );
  }
}

/// Runs [service] at [now] without ever stopping the app start.
///
/// A failure is reported to the log and swallowed: the cleanup rolled back,
/// the data is as it was, and the next start tries again. Returns the
/// report, or `null` when the cleanup failed.
Future<CleanupReport?> runStartupCleanupSafely(
  TrashCleanupService service,
  DateTime now,
) async {
  try {
    return await service.runStartupCleanup(now);
    // Deliberately catches everything: nothing here may block the start.
    // ignore: avoid_catches_without_on_clauses
  } catch (error, stackTrace) {
    debugPrint('Startup cleanup failed, nothing removed: $error\n$stackTrace');
    return null;
  }
}
