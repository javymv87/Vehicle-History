import 'package:flutter/foundation.dart' show debugPrint;

import '../attachments/attachment_store.dart';
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
    this.attachments = 0,
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

  /// Deleted attachments removed on their own, with their files (not
  /// counting those that went with a vehicle, an entry or an owner).
  final int attachments;

  @override
  String toString() => 'CleanupReport(vehicles: $vehicles, entries: $entries, '
      'readings: $readings, owners: $owners, attachments: $attachments)';
}

/// Removes from disk what has been soft-deleted for longer than
/// [trashRetention] (`Docs/05_sync_and_storage.md`, "Papelera y limpieza").
///
/// Run once per app start, after the database is open and migrated (see
/// `databaseReadyProvider`).
class TrashCleanupService {
  /// Creates the service on [_trash], auditing through [_audit] and
  /// deleting the files of the removed attachments from [_files].
  TrashCleanupService(this._trash, this._audit, this._files);

  /// Soft-deleted rows and the physical deletes.
  final TrashDao _trash;

  /// Audit log writes, joined to the cleanup transaction.
  final AuditLogDao _audit;

  /// The attachment files, deleted once the rows are gone.
  final AttachmentStore _files;

  /// Removes, in one transaction, everything deleted at least
  /// [trashRetention] before [now] (UTC):
  ///
  /// 1. vehicles in the Trash, each with every entry and reading it has;
  /// 2. deleted entries and readings of live vehicles;
  /// 3. deleted owners that no vehicle row references any more (step 1 may
  ///    just have freed some);
  /// 4. deleted attachments that do not travel with a vehicle in the Trash.
  ///
  /// The attachments of a removed vehicle, entry or owner go with it,
  /// whatever their own flag. Vehicles and owners get a `purge` audit row;
  /// the entries, readings and attachments do not. Children of a vehicle
  /// still in the Trash are left alone: they go with their vehicle. If
  /// anything fails, the transaction rolls back, nothing is removed, and the
  /// error is rethrown. The attachment files are deleted only after the
  /// commit; one that cannot be deleted is left to the orphan sweep.
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

    final files = <String>[];
    final report = await _trash.transaction(() async {
      files.clear();
      final vehicles = expired(await _trash.getTrashedVehicles());
      for (final id in vehicles) {
        files.addAll(await _trash.purgeVehicle(id) ?? const []);
        await _record(AuditEntityType.vehicle, id, now);
      }

      final entries = expired(await _trash.getDeletedEntriesOfLiveVehicles());
      var removedEntries = 0;
      if (entries.isNotEmpty) {
        final purged = await _trash.purgeEntries(entries);
        removedEntries = purged.rows;
        files.addAll(purged.files);
      }
      final readings = expired(await _trash.getDeletedReadingsOfLiveVehicles());
      final removedReadings =
          readings.isEmpty ? 0 : await _trash.purgeReadings(readings);

      final owners = expired(await _trash.getDeletedOwnersWithoutVehicles());
      for (final id in owners) {
        files.addAll((await _trash.purgeOwner(id)).files);
        await _record(AuditEntityType.owner, id, now);
      }

      final attachments =
          expired(await _trash.getDeletedAttachmentsOutsideTrash());
      var removedAttachments = 0;
      if (attachments.isNotEmpty) {
        final purged = await _trash.purgeAttachments(attachments);
        removedAttachments = purged.rows;
        files.addAll(purged.files);
      }

      return CleanupReport(
        vehicles: vehicles.length,
        entries: removedEntries,
        readings: removedReadings,
        owners: owners.length,
        attachments: removedAttachments,
      );
    });
    await deleteFilesQuietly(_files, files);
    return report;
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

/// Housekeeping of the attachment files at app start, after the cleanup:
/// wipes the staging directory (no form is open yet, so whatever is there
/// was left by a form that never finished) and deletes the files under
/// `attachments/` that no row references (orphans). Rows whose file is
/// missing are kept.
///
/// Like the cleanup, it never stops the start: a failure is logged and
/// swallowed. Returns the number of orphan files deleted, or `null` when it
/// failed.
Future<int?> runAttachmentSweepSafely(
  AttachmentStore store,
  Future<Set<String>> Function() referencedPaths,
) async {
  try {
    await store.wipeStaging();
    return await deleteOrphanFiles(store, await referencedPaths());
    // Deliberately catches everything: nothing here may block the start.
    // ignore: avoid_catches_without_on_clauses
  } catch (error, stackTrace) {
    debugPrint('Attachment sweep failed: $error\n$stackTrace');
    return null;
  }
}
