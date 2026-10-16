import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../models/audit_entry.dart';
import '../models/calendar_date.dart';
import '../models/fuel_type.dart';
import 'audit_log_table.dart';
import 'converters.dart';
import 'daos/audit_log_dao.dart';
import 'daos/owners_dao.dart';
import 'daos/vehicles_dao.dart';
import 'owners_table.dart';
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
  AppDatabase() : super(driftDatabase(name: 'vehicle_history'));

  /// Opens the database on an explicit [executor], such as an in-memory
  /// database in tests.
  AppDatabase.forExecutor(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          throw UnimplementedError('No migration from $from to $to');
        },
        beforeOpen: (details) async {
          // SQLite ships with foreign keys off; enable them on every connection.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
