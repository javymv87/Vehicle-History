import 'package:drift/drift.dart';

import '../../models/backup_manifest.dart';
import '../app_database.dart';
import '../attachments_table.dart';
import '../audit_log_table.dart';
import '../log_entries_table.dart';
import '../mileage_readings_table.dart';
import '../owners_table.dart';
import '../vehicles_table.dart';

part 'backup_dao.g.dart';

/// Queries for the backup package: the consistent copy of the whole
/// database and the figures written into its manifest.
@DriftAccessor(
  tables: [
    Owners,
    Vehicles,
    LogEntries,
    MileageReadings,
    Attachments,
    AuditLog,
  ],
)
class BackupDao extends DatabaseAccessor<AppDatabase> with _$BackupDaoMixin {
  /// Creates the DAO on [db]. Obtain it through `AppDatabase.backupDao`.
  BackupDao(super.db);

  /// Writes a consistent copy of the whole database to the new file at
  /// [path] with SQLite's `VACUUM INTO`.
  ///
  /// The copy includes pages still in the WAL and every table (Trash and
  /// audit log included), whatever else the connection is doing. SQLite
  /// refuses to overwrite an existing file and to run inside a transaction.
  Future<void> vacuumInto(String path) =>
      customStatement('VACUUM INTO ?', [path]);

  /// Counts the live rows of each main table (see [BackupCounts]).
  Future<BackupCounts> liveCounts() async {
    final row = await customSelect(
      'SELECT '
      '(SELECT COUNT(*) FROM owners WHERE deleted = 0) AS owners, '
      '(SELECT COUNT(*) FROM vehicles WHERE deleted = 0) AS vehicles, '
      '(SELECT COUNT(*) FROM log_entries e JOIN vehicles v '
      'ON v.id = e.vehicle_id WHERE e.deleted = 0 AND v.deleted = 0) '
      'AS log_entries, '
      '(SELECT COUNT(*) FROM mileage_readings r JOIN vehicles v '
      'ON v.id = r.vehicle_id WHERE r.deleted = 0 AND v.deleted = 0) '
      'AS mileage_readings',
      readsFrom: {owners, vehicles, logEntries, mileageReadings},
    ).getSingle();
    return BackupCounts(
      owners: row.read<int>('owners'),
      vehicles: row.read<int>('vehicles'),
      logEntries: row.read<int>('log_entries'),
      mileageReadings: row.read<int>('mileage_readings'),
    );
  }

  /// The latest instant at which anything the user records changed, in
  /// UTC, or `null` for a database with no data and no purge: the latest
  /// `updated_at` across owners, vehicles, entries, readings and
  /// attachments, deleted rows included (a delete and an undo write
  /// `updated_at` too), and the latest `at` of the `purge` audit rows, which
  /// stand for the rows deleted for good.
  ///
  /// Without the purges the value could go backwards when the most recently
  /// changed row is removed from disk. Left out on purpose: the `settings`
  /// table (preferences and the last export date, which would move the
  /// value at every export) and the `import` audit rows (after an import the
  /// data is the package's, so a freshly restored copy must not look newer
  /// than it). This value is the version stamp of the backup guard.
  ///
  /// Compared as text: every timestamp, `audit_log.at` included, is stored
  /// as ISO-8601 UTC in the same format, which sorts like the instants it
  /// represents.
  Future<DateTime?> lastModifiedAt() async =>
      _lastOf(await _lastModifiedQuery().getSingle());

  /// The number of attachment rows, live or deleted: the attachment figure
  /// the Drive guard compares (the package carries every row's file).
  Future<int> attachmentRowCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM attachments',
      readsFrom: {attachments},
    ).getSingle();
    return row.read<int>('n');
  }

  /// The value of the row selected by [_lastModifiedQuery].
  static DateTime? _lastOf(QueryRow row) {
    final last = row.read<String?>('last');
    return last == null ? null : DateTime.parse(last).toUtc();
  }

  /// The query behind [lastModifiedAt].
  Selectable<QueryRow> _lastModifiedQuery() {
    return customSelect(
      'SELECT MAX(m) AS last FROM ('
      'SELECT MAX(updated_at) AS m FROM owners UNION ALL '
      'SELECT MAX(updated_at) FROM vehicles UNION ALL '
      'SELECT MAX(updated_at) FROM log_entries UNION ALL '
      'SELECT MAX(updated_at) FROM mileage_readings UNION ALL '
      'SELECT MAX(updated_at) FROM attachments UNION ALL '
      "SELECT MAX(at) FROM audit_log WHERE operation = 'purge')",
      readsFrom: {
        owners,
        vehicles,
        logEntries,
        mileageReadings,
        attachments,
        auditLog,
      },
    );
  }
}
