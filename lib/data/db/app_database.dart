import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/archive_reason.dart';
import '../models/attachment.dart';
import '../models/audit_entry.dart';
import '../models/calendar_date.dart';
import '../models/fuel_type.dart';
import '../models/log_entry_type.dart';
import '../models/vehicle_kind.dart';
import 'app_database.steps.dart';
import 'attachments_table.dart';
import 'audit_log_table.dart';
import 'converters.dart';
import 'daos/attachments_dao.dart';
import 'daos/audit_log_dao.dart';
import 'daos/backup_dao.dart';
import 'daos/log_entries_dao.dart';
import 'daos/mileage_readings_dao.dart';
import 'daos/owners_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/trash_dao.dart';
import 'daos/vehicles_dao.dart';
import 'log_entries_table.dart';
import 'mileage_readings_table.dart';
import 'owners_table.dart';
import 'settings_table.dart';
import 'upgrade_safety.dart';
import 'vehicles_table.dart';

part 'app_database.g.dart';

/// The local SQLite database: the only live copy of the user's data.
///
/// There is no server to re-sync from, so every schema change must bump
/// [schemaVersion], add a migration step and commit the new schema dump
/// (see CLAUDE.md §2).
@DriftDatabase(
  tables: [
    Owners,
    Vehicles,
    AuditLog,
    LogEntries,
    MileageReadings,
    Settings,
    Attachments,
  ],
  daos: [
    OwnersDao,
    VehiclesDao,
    AuditLogDao,
    LogEntriesDao,
    MileageReadingsDao,
    TrashDao,
    SettingsDao,
    BackupDao,
    AttachmentsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the on-device database file `vehicle_history.sqlite` via
  /// `drift_flutter`.
  ///
  /// The file lives in the application support directory, not in the
  /// documents directory: on iOS the latter is visible to the user in the
  /// Files app and backed up to iCloud, and the only backup of this data is
  /// the app's own (see `Docs/05_sync_and_storage.md`). Attachment paths are
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
    // v3: the vehicle history (`log_entries`) and its two indexes. Only new
    // objects: no existing table or row is touched. `audit_log` needs no
    // change, since `entity_type` has no CHECK and accepts the new
    // `logEntry` code as it is.
    from2To3: (m, schema) async {
      await m.createTable(schema.logEntries);
      await m.createIndex(schema.logEntriesVehicleDate);
      await m.createIndex(schema.logEntriesVehicleType);
    },
    // v4: the odometer history (`mileage_readings`) and its index, plus one
    // initial reading per vehicle so every vehicle starts with exactly one.
    // Only new objects and new rows: no existing row is touched.
    from3To4: (m, schema) async {
      await m.createTable(schema.mileageReadings);
      await m.createIndex(schema.mileageReadingsVehicleDate);
      await insertInitialReadings(m.database);
    },
    // v5: `deleted_at` on every soft-deletable table, for the Trash and its
    // 30-day cleanup. Only new nullable columns, then a backfill of the rows
    // already deleted: their deletion instant is their `updated_at`, which
    // every soft delete has always written. No other value is touched.
    from4To5: (m, schema) async {
      for (final (table, column) in [
        (schema.owners, schema.owners.deletedAt),
        (schema.vehicles, schema.vehicles.deletedAt),
        (schema.logEntries, schema.logEntries.deletedAt),
        (schema.mileageReadings, schema.mileageReadings.deletedAt),
      ]) {
        await m.addColumn(table, column);
      }
      await backfillDeletedAt(m.database);
    },
    // v6: the `settings` key / value table, created empty. Only a new
    // table: no existing table or row is touched.
    from5To6: (m, schema) async {
      await m.createTable(schema.settings);
    },
    // v7: the `attachments` table and its index, created empty. Only new
    // objects: no existing table or row is touched. `audit_log` needs no
    // change, since `entity_type` has no CHECK and accepts the new
    // `attachment` code as it is.
    from6To7: (m, schema) async {
      await m.createTable(schema.attachments);
      await m.createIndex(schema.attachmentsEntity);
    },
    // v8: the archive columns of `vehicles`. Only new nullable columns, no
    // backfill: every existing vehicle stays active (`archived_at` NULL).
    // `audit_log` needs no change, since `operation` has no CHECK and
    // accepts the new `archive` / `reactivate` codes as they are.
    from7To8: (m, schema) async {
      final vehicles = schema.vehicles;
      for (final column in [
        vehicles.archivedAt,
        vehicles.archiveReason,
        vehicles.archiveNote,
        vehicles.archivedKm,
      ]) {
        await m.addColumn(vehicles, column);
      }
    },
    // v9: the four distance columns (`mileage_readings.km`,
    // `log_entries.km`, `vehicles.current_odometer_km` and
    // `vehicles.archived_km`) become REAL, so a value typed in miles is
    // stored exactly in km. SQLite cannot change a column's type in place:
    // each table is recreated with the new definition and its rows copied
    // across as they are (an INTEGER 85000 becomes the REAL 85000.0, still
    // km), then the old table is dropped and the copy renamed. Drift
    // recreates the indexes; the foreign keys to `vehicles` reference it by
    // name and survive the swap, which `runSafeUpgrade` does with foreign
    // keys off and checks afterwards. No value is changed.
    from8To9: (m, schema) async {
      await m.alterTable(TableMigration(schema.vehicles));
      await m.alterTable(TableMigration(schema.logEntries));
      await m.alterTable(TableMigration(schema.mileageReadings));
    },
  );

  /// Tables carrying the soft-delete columns `deleted` and `deleted_at`.
  static const List<String> _softDeleteTables = [
    'owners',
    'vehicles',
    'log_entries',
    'mileage_readings',
  ];

  /// Sets `deleted_at = updated_at` on every soft-deleted row, for the
  /// v4 → v5 upgrade.
  ///
  /// Before v5 a soft delete wrote its instant into `updated_at`, and a
  /// deleted row cannot be edited, so `updated_at` is when it was deleted.
  /// Live rows keep `deleted_at` NULL. Plain SQL against the v5 shape, and no
  /// audit row: the user did not write these values, the upgrade did.
  ///
  /// Runs inside the upgrade transaction of [runSafeUpgrade].
  @visibleForTesting
  static Future<void> backfillDeletedAt(GeneratedDatabase db) async {
    for (final table in _softDeleteTables) {
      await db.customStatement(
        'UPDATE $table SET deleted_at = updated_at WHERE deleted = 1',
      );
    }
  }

  /// Inserts the initial reading of every vehicle, for the v3 → v4 upgrade.
  ///
  /// One reading per vehicle row, **soft-deleted vehicles included**, so a
  /// vehicle restored later still has its reading: km = the vehicle's
  /// `current_odometer_km`, day = the local calendar day of its
  /// `created_at`, and `created_at` / `updated_at` copied from the vehicle,
  /// so the reading sorts as the oldest. Plain SQL against the v4 shape, and
  /// no audit row: the user did not write these, the upgrade did.
  ///
  /// Runs inside the upgrade transaction of [runSafeUpgrade]: if anything
  /// fails, no reading is inserted and the database stays at v3.
  @visibleForTesting
  static Future<void> insertInitialReadings(GeneratedDatabase db) async {
    final vehicles = await db
        .customSelect(
          'SELECT id, created_at, current_odometer_km FROM vehicles',
        )
        .get();
    for (final vehicle in vehicles) {
      final createdAt = vehicle.read<String>('created_at');
      final day = const CalendarDateConverter().toSql(
        CalendarDate.localDayOf(DateTime.parse(createdAt)),
      );
      await db.customStatement(
        'INSERT INTO mileage_readings (id, created_at, updated_at, deleted, '
        'vehicle_id, reading_date, km) VALUES (?, ?, ?, 0, ?, ?, ?)',
        [
          const Uuid().v4(),
          createdAt,
          createdAt,
          vehicle.read<String>('id'),
          day,
          vehicle.read<int>('current_odometer_km'),
        ],
      );
    }
  }

  /// Steps run by [runSafeUpgrade] when the file is older than the app.
  final OnUpgrade _upgradeSteps;

  /// Makes the copy of the database file taken before every upgrade.
  final PreUpgradeCopier _copier;

  @override
  int get schemaVersion => 9;

  /// Opens the connection now, running any pending migration.
  ///
  /// Drift opens the file lazily on the first query. Calling this at startup
  /// surfaces a refused or failed upgrade (such as
  /// [DatabaseNewerThanAppException]) before any screen tries to read data.
  Future<void> open() => customSelect('SELECT 1').get();

  /// The pending or finished [close], so that closing twice is harmless.
  Future<void>? _closing;

  /// Closes the connection. Idempotent: a second call waits for the first.
  ///
  /// The import closes the live database before replacing its file, and the
  /// provider closes the same instance again when it is disposed.
  @override
  Future<void> close() => _closing ??= _closeConnection();

  /// Closes the connection without waiting for the stream queries.
  ///
  /// Drift's own close first waits until every stream query has delivered
  /// its "done" event, and only then closes the connection. A paused
  /// listener never takes that event (Riverpod pauses the providers of
  /// screens that are not visible, such as the list below the Backup page),
  /// so that wait could last forever and the import would hang. The streams
  /// are shut down in the background instead, and the connection is closed
  /// right away; closing it again from drift's own close is a no-op.
  Future<void> _closeConnection() async {
    unawaited(super.close());
    await executor.close();
  }

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
