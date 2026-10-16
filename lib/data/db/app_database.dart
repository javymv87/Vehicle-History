import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../models/audit_entry.dart';
import '../models/calendar_date.dart';
import '../models/fuel_type.dart';
import '../models/vehicle_kind.dart';
import 'app_database.steps.dart';
import 'audit_log_table.dart';
import 'converters.dart';
import 'daos/audit_log_dao.dart';
import 'daos/owners_dao.dart';
import 'daos/vehicles_dao.dart';
import 'owners_table.dart';
import 'upgrade_safety.dart';
import 'vehicles_table.dart';

part 'app_database.g.dart';

/// The local SQLite database: the only live copy of the user's data.
///
/// There is no server to re-sync from, so every schema change must bump
/// [schemaVersion], add a migration step and commit the new schema dump
/// (see CLAUDE.md §2).
@DriftDatabase(
  tables: [Owners, Vehicles, AuditLog],
  daos: [OwnersDao, VehiclesDao, AuditLogDao],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the on-device database file `vehicle_history.sqlite` via
  /// `drift_flutter`.
  ///
  /// The file lives in the application support directory, not in the
  /// documents directory: on iOS the latter is visible to the user in the
  /// Files app and backed up to iCloud, and the only backup of this data is
  /// the app's own (see `Docs/05_sync_and_storage.md`). Future photo paths are
  /// relative to the same directory.
  AppDatabase()
      : _upgradeSteps = _schemaSteps,
        _copier = const PreUpgradeCopier(),
        super(
          driftDatabase(
            name: 'vehicle_history',
            native: const DriftNativeOptions(
              databaseDirectory: getApplicationSupportDirectory,
            ),
          ),
        );

  /// Opens the database on an explicit [executor], such as an in-memory
  /// database in tests.
  ///
  /// [upgradeSteps] and [copier] replace the production migration steps and
  /// the pre-upgrade copy. They exist only so tests can simulate a broken
  /// migration or observe the copy; the app never passes them.
  AppDatabase.forExecutor(
    super.executor, {
    @visibleForTesting OnUpgrade? upgradeSteps,
    @visibleForTesting PreUpgradeCopier copier = const PreUpgradeCopier(),
  })  : _upgradeSteps = upgradeSteps ?? _schemaSteps,
        _copier = copier;

  /// Schema changes from one version to the next, one step per version,
  /// built on the versioned schemas `make-migrations` generates in
  /// `app_database.steps.dart` (see CLAUDE.md §2, "Upgrade safety").
  static final OnUpgrade _schemaSteps = stepByStep(
    // v2: vehicle kind, make / model (name + catalogue slug), model year and
    // version. Only new columns, all nullable or with a default: no existing
    // value is touched, and every v1 vehicle becomes a car.
    from1To2: (m, schema) async {
      final vehicles = schema.vehicles;
      for (final column in [
        vehicles.kind,
        vehicles.make,
        vehicles.makeSlug,
        vehicles.model,
        vehicles.modelSlug,
        vehicles.modelYear,
        vehicles.version,
      ]) {
        await m.addColumn(vehicles, column);
      }
    },
  );

  /// Steps run by [runSafeUpgrade] when the file is older than the app.
  final OnUpgrade _upgradeSteps;

  /// Makes the copy of the database file taken before every upgrade.
  final PreUpgradeCopier _copier;

  @override
  int get schemaVersion => 2;

  /// Opens the connection now, running any pending migration.
  ///
  /// Drift opens the file lazily on the first query. Calling this at startup
  /// surfaces a refused or failed upgrade (such as
  /// [DatabaseNewerThanAppException]) before any screen tries to read data.
  Future<void> open() => customSelect('SELECT 1').get();

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        // Drift also calls this when the file is newer than the app;
        // runSafeUpgrade refuses that case.
        onUpgrade: (m, from, to) => runSafeUpgrade(
          db: this,
          migrator: m,
          from: from,
          to: to,
          steps: _upgradeSteps,
          copier: _copier,
        ),
        beforeOpen: (details) async {
          // SQLite ships with foreign keys off; enable them on every connection.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
