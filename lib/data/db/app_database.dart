import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/audit_entry.dart';
import '../models/calendar_date.dart';
import '../models/fuel_type.dart';
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
  /// Opens the on-device database file `vehicle_history` via `drift_flutter`.
  AppDatabase()
      : _upgradeSteps = _schemaSteps,
        _copier = const PreUpgradeCopier(),
        super(driftDatabase(name: 'vehicle_history'));

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

  /// Schema changes from one version to the next.
  ///
  /// At v1 there is nothing to upgrade from. With v2, replace this with the
  /// `stepByStep(...)` helper that `make-migrations` generates in
  /// `app_database.steps.dart` (see CLAUDE.md §2, "Upgrade safety").
  static Future<void> _schemaSteps(Migrator m, int from, int to) async {
    throw StateError('No migration step from v$from to v$to');
  }

  /// Steps run by [runSafeUpgrade] when the file is older than the app.
  final OnUpgrade _upgradeSteps;

  /// Makes the copy of the database file taken before every upgrade.
  final PreUpgradeCopier _copier;

  @override
  int get schemaVersion => 1;

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
