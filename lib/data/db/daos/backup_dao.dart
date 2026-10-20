import 'package:drift/drift.dart';

import '../../models/backup_manifest.dart';
import '../app_database.dart';
import '../log_entries_table.dart';
import '../mileage_readings_table.dart';
import '../owners_table.dart';
import '../vehicles_table.dart';

part 'backup_dao.g.dart';

/// Queries for the backup package: the consistent copy of the whole
/// database and the figures written into its manifest.
@DriftAccessor(tables: [Owners, Vehicles, LogEntries, MileageReadings])
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

  /// The latest `updated_at` across owners, vehicles, entries and readings,
  /// deleted rows included (a delete writes `updated_at` too), in UTC;
  /// `null` when all four tables are empty.
  ///
  /// Compared as text: every timestamp is stored as ISO-8601 UTC in the same
  /// format, which sorts like the instants it represents.
  Future<DateTime?> lastModifiedAt() async {
    final row = await customSelect(
      'SELECT MAX(m) AS last FROM ('
      'SELECT MAX(updated_at) AS m FROM owners UNION ALL '
      'SELECT MAX(updated_at) FROM vehicles UNION ALL '
      'SELECT MAX(updated_at) FROM log_entries UNION ALL '
      'SELECT MAX(updated_at) FROM mileage_readings)',
      readsFrom: {owners, vehicles, logEntries, mileageReadings},
    ).getSingle();
    final last = row.read<String?>('last');
    return last == null ? null : DateTime.parse(last).toUtc();
  }
}
