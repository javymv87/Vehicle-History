import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';

import 'generated/schema.dart';

/// Data-integrity tests for schema upgrades: rows written by an older app
/// version must all be intact after the upgrade, version by version and
/// across the whole chain.
///
/// For the next schema change:
///
/// 1. run `dart run drift_dev make-migrations` (it regenerates
///    `generated/` for every version);
/// 2. set [latestVersion] to the new version;
/// 3. add an `_insertV<n>Rows` writing realistic rows at the previous
///    latest version with plain SQL (it always targets the *old* schema),
///    its `_expectV<n>RowsIntact`, and a test from it to the new version;
/// 4. extend the existing expectations with any new column's default.
///
/// The tests must never be weakened to make an upgrade pass.
const int latestVersion = 3;

/// Timestamp written into every old row.
const String _ts = '2024-03-04T10:30:00.000Z';

/// [_ts] as the UTC instant the domain models carry.
final DateTime _tsUtc = DateTime.utc(2024, 3, 4, 10, 30);

/// Counts the rows returned by `SELECT COUNT(*) AS c ...` [sql].
Future<int> _count(GeneratedDatabase db, String sql) async =>
    (await db.customSelect(sql).getSingle()).read<int>('c');

/// Fails if any foreign key points at a missing row.
Future<void> _expectForeignKeysValid(GeneratedDatabase db) async {
  final violations = await db.customSelect('PRAGMA foreign_key_check').get();
  expect(violations, isEmpty);
}

// ---------------------------------------------------------------------------
// Rows written at v1.
// ---------------------------------------------------------------------------

/// Writes rows covering every v1 column, NULLs, soft-deleted rows, the audit
/// log and non-ASCII text, using plain SQL against the v1 schema.
Future<void> _insertV1Rows(GeneratedDatabase oldDb) async {
  await oldDb.customStatement(
    'INSERT INTO owners (id, created_at, updated_at, deleted, first_name, '
    'last_name, birth_date, nationality, phone, email, notes, photo_path) '
    "VALUES ('o1', '$_ts', '$_ts', 0, 'José', 'Núñez', '1980-02-29', "
    "'ES', '+39 333 1234567', 'jose@example.com', 'línea 1\nlínea 2', "
    "'photos/o1.jpg'), "
    "('o2', '$_ts', '$_ts', 1, 'Deleted', NULL, NULL, NULL, NULL, NULL, NULL, "
    'NULL), '
    "('o3', '$_ts', '$_ts', 0, 'Ana', NULL, NULL, 'Cubana', NULL, NULL, "
    'NULL, NULL)',
  );
  await oldDb.customStatement(
    'INSERT INTO vehicles (id, created_at, updated_at, deleted, plate, '
    'nickname, owner_id, current_odometer_km, fuel_type, '
    'recommended_engine_oil, manufacturer_notes, photo_path) '
    "VALUES ('v1', '$_ts', '$_ts', 0, 'AB123CD', 'Punto', 'o1', 85000, "
    "'petrolLpg', '5W-40', 'Cambio cinghia 4-5 anni', 'photos/v1.jpg'), "
    "('v2', '$_ts', '$_ts', 1, 'AB123CD', NULL, 'o1', 0, 'diesel', NULL, "
    'NULL, NULL), '
    "('v3', '$_ts', '$_ts', 0, 'XY987ZW', NULL, 'o3', 0, 'electric', NULL, "
    'NULL, NULL)',
  );
  await oldDb.customStatement(
    'INSERT INTO audit_log (id, entity_type, entity_id, operation, at) '
    "VALUES ('a1', 'owner', 'o1', 'create', '$_ts'), "
    "('a2', 'vehicle', 'v1', 'create', '$_ts'), "
    "('a3', 'vehicle', 'v2', 'delete', '$_ts'), "
    "('a4', 'vehicle', 'v1', 'restore', '$_ts')",
  );
}

/// Checks every row and value written by [_insertV1Rows] after an upgrade
/// to v2 or later.
Future<void> _expectV1RowsIntact(AppDatabase db) async {
  final owners = await db.ownersDao.getLive();
  expect([for (final o in owners) o.id], unorderedEquals(['o1', 'o3']));
  final owner = owners.singleWhere((o) => o.id == 'o1');
  expect(owner.firstName, 'José');
  expect(owner.lastName, 'Núñez');
  expect(owner.birthDate, const CalendarDate(1980, 2, 29));
  expect(owner.nationality, 'ES');
  expect(owner.phone, '+39 333 1234567');
  expect(owner.email, 'jose@example.com');
  expect(owner.notes, 'línea 1\nlínea 2');
  expect(owner.photoPath, 'photos/o1.jpg');
  expect(owner.createdAt, _tsUtc);
  expect(owner.updatedAt, _tsUtc);
  // Free-text nationality from before the country picker stays as typed.
  expect(owners.singleWhere((o) => o.id == 'o3').nationality, 'Cubana');

  final vehicles = await db.vehiclesDao.getLive();
  expect([for (final v in vehicles) v.id], ['v1', 'v3']);
  final vehicle = vehicles.first;
  expect(vehicle.plate, 'AB123CD');
  expect(vehicle.nickname, 'Punto');
  expect(vehicle.ownerId, 'o1');
  expect(vehicle.currentOdometerKm, 85000);
  expect(vehicle.fuelType, FuelType.petrolLpg);
  expect(vehicle.recommendedEngineOil, '5W-40');
  expect(vehicle.manufacturerNotes, 'Cambio cinghia 4-5 anni');
  expect(vehicle.photoPath, 'photos/v1.jpg');
  expect(vehicle.createdAt, _tsUtc);
  expect(vehicle.updatedAt, _tsUtc);

  // v2: every existing vehicle is a car, with no make, model, year or
  // version until the user edits it.
  for (final v in vehicles) {
    expect(v.kind, VehicleKind.car);
    expect(v.make, isNull);
    expect(v.makeSlug, isNull);
    expect(v.model, isNull);
    expect(v.modelSlug, isNull);
    expect(v.modelYear, isNull);
    expect(v.version, isNull);
  }

  // The soft-deleted vehicle is still on disk, deleted, with its values.
  final deleted = await db.vehiclesDao.getDeletedById('v2');
  expect(deleted, isNotNull);
  expect(deleted!.fuelType, FuelType.diesel);
  expect(deleted.kind, VehicleKind.car);

  // The audit log is untouched, row for row.
  final audit =
      await db.auditLogDao.getForEntity(AuditEntityType.vehicle, 'v1');
  expect(
    [for (final e in audit) (e.id, e.operation, e.at)],
    unorderedEquals([
      ('a2', AuditOperation.create, _tsUtc),
      ('a4', AuditOperation.restore, _tsUtc),
    ]),
  );

  expect(await _count(db, 'SELECT COUNT(*) AS c FROM owners'), 3);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM vehicles'), 3);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM audit_log'), 4);
  await _expectForeignKeysValid(db);
}

// ---------------------------------------------------------------------------
// Rows written at v2.
// ---------------------------------------------------------------------------

/// Writes rows covering every v2 column using plain SQL against the v2
/// schema: owners (one soft-deleted), vehicles of every kind with a
/// catalogue make / model, a hand-typed one, one from the v1 era without
/// make and model, a soft-deleted one, and the audit log.
Future<void> _insertV2Rows(GeneratedDatabase oldDb) async {
  await oldDb.customStatement(
    'INSERT INTO owners (id, created_at, updated_at, deleted, first_name, '
    'last_name, birth_date, nationality, phone, email, notes, photo_path) '
    "VALUES ('o1', '$_ts', '$_ts', 0, 'Gianluca', 'Dell''Acqua', "
    "'1975-12-31', 'IT', '+39 06 1234', NULL, 'Proprietario più vecchio', "
    'NULL), '
    "('o2', '$_ts', '$_ts', 1, 'Borrado', NULL, NULL, NULL, NULL, NULL, NULL, "
    'NULL), '
    "('o3', '$_ts', '$_ts', 0, 'Zoë', 'Muñoz', NULL, 'Cubana', NULL, "
    "'zoe@example.com', NULL, NULL)",
  );
  await oldDb.customStatement(
    'INSERT INTO vehicles (id, created_at, updated_at, deleted, plate, kind, '
    'make, make_slug, model, model_slug, model_year, version, nickname, '
    'owner_id, current_odometer_km, fuel_type, recommended_engine_oil, '
    'manufacturer_notes, photo_path) VALUES '
    "('v1', '$_ts', '$_ts', 0, 'AB123CD', 'car', 'Fiat', 'fiat', "
    "'Grande Punto', 'grande-punto', 2008, '1.4 77 CV Dynamic', 'Punto', "
    "'o1', 185432, 'petrolLpg', '5W-40', 'Cinghia ogni 5 anni', "
    "'photos/v1.jpg'), "
    "('v2', '$_ts', '$_ts', 1, 'AB123CD', 'van', 'Fiat', 'fiat', 'Doblò', "
    "'doblo', 2015, NULL, NULL, 'o1', 99000, 'diesel', NULL, NULL, NULL), "
    "('v3', '$_ts', '$_ts', 0, 'EX12345', 'motorcycle', 'Honda', 'honda', "
    "'SH125', 'sh125', 2020, NULL, NULL, 'o3', 12000, 'petrol', NULL, NULL, "
    'NULL), '
    "('v4', '$_ts', '$_ts', 0, 'X7Y8Z9', 'moped', 'Malagùti', NULL, "
    "'Fifty Top', NULL, NULL, NULL, 'Il motorino', 'o3', 0, 'petrol', NULL, "
    'NULL, NULL), '
    "('v5', '$_ts', '$_ts', 0, 'ZZ999ZZ', 'car', NULL, NULL, NULL, NULL, "
    "NULL, NULL, NULL, 'o1', 0, 'hybrid', NULL, NULL, NULL)",
  );
  await oldDb.customStatement(
    'INSERT INTO audit_log (id, entity_type, entity_id, operation, at) '
    "VALUES ('a1', 'owner', 'o1', 'create', '$_ts'), "
    "('a2', 'owner', 'o2', 'create', '$_ts'), "
    "('a3', 'owner', 'o2', 'delete', '$_ts'), "
    "('a4', 'vehicle', 'v1', 'create', '$_ts'), "
    "('a5', 'vehicle', 'v1', 'update', '$_ts'), "
    "('a6', 'vehicle', 'v2', 'create', '$_ts'), "
    "('a7', 'vehicle', 'v2', 'delete', '$_ts'), "
    "('a8', 'vehicle', 'v3', 'create', '$_ts'), "
    "('a9', 'vehicle', 'v4', 'create', '$_ts'), "
    "('a10', 'vehicle', 'v5', 'create', '$_ts'), "
    "('a11', 'vehicle', 'v2', 'restore', '$_ts'), "
    "('a12', 'vehicle', 'v2', 'delete', '$_ts')",
  );
}

/// Checks every row and value written by [_insertV2Rows] after an upgrade
/// to v3 or later.
Future<void> _expectV2RowsIntact(AppDatabase db) async {
  final owners = await db.ownersDao.getLive();
  expect([for (final o in owners) o.id], ['o1', 'o3']);
  final gianluca = owners.first;
  expect(gianluca.lastName, "Dell'Acqua");
  expect(gianluca.birthDate, const CalendarDate(1975, 12, 31));
  expect(gianluca.nationality, 'IT');
  expect(gianluca.phone, '+39 06 1234');
  expect(gianluca.email, isNull);
  expect(gianluca.notes, 'Proprietario più vecchio');
  expect(gianluca.createdAt, _tsUtc);
  final zoe = owners.last;
  expect((zoe.firstName, zoe.lastName), ('Zoë', 'Muñoz'));
  expect(zoe.nationality, 'Cubana');
  expect(zoe.email, 'zoe@example.com');

  final vehicles = {
    for (final v in await db.vehiclesDao.getLive()) v.id: v,
  };
  expect(vehicles.keys, unorderedEquals(['v1', 'v3', 'v4', 'v5']));

  final punto = vehicles['v1']!;
  expect(punto.plate, 'AB123CD');
  expect(punto.kind, VehicleKind.car);
  expect((punto.make, punto.makeSlug), ('Fiat', 'fiat'));
  expect((punto.model, punto.modelSlug), ('Grande Punto', 'grande-punto'));
  expect(punto.modelYear, 2008);
  expect(punto.version, '1.4 77 CV Dynamic');
  expect(punto.nickname, 'Punto');
  expect(punto.ownerId, 'o1');
  expect(punto.currentOdometerKm, 185432);
  expect(punto.fuelType, FuelType.petrolLpg);
  expect(punto.recommendedEngineOil, '5W-40');
  expect(punto.manufacturerNotes, 'Cinghia ogni 5 anni');
  expect(punto.photoPath, 'photos/v1.jpg');
  expect((punto.createdAt, punto.updatedAt), (_tsUtc, _tsUtc));

  final scooter = vehicles['v3']!;
  expect(scooter.kind, VehicleKind.motorcycle);
  expect((scooter.make, scooter.model), ('Honda', 'SH125'));
  expect((scooter.makeSlug, scooter.modelSlug), ('honda', 'sh125'));

  // Make and model typed by hand keep their text and have no slug.
  final moped = vehicles['v4']!;
  expect(moped.kind, VehicleKind.moped);
  expect((moped.make, moped.makeSlug), ('Malagùti', null));
  expect((moped.model, moped.modelSlug), ('Fifty Top', null));
  expect(moped.nickname, 'Il motorino');

  // A vehicle from the v1 era still has no make or model.
  final old = vehicles['v5']!;
  expect((old.make, old.model, old.modelYear), (null, null, null));
  expect(old.fuelType, FuelType.hybrid);

  final van = await db.vehiclesDao.getDeletedById('v2');
  expect(van, isNotNull);
  expect(van!.kind, VehicleKind.van);
  expect(van.model, 'Doblò');

  // The audit log is untouched, row for row and in order.
  final v2Audit =
      await db.auditLogDao.getForEntity(AuditEntityType.vehicle, 'v2');
  expect(
    [for (final e in v2Audit) (e.id, e.operation, e.at)],
    [
      ('a6', AuditOperation.create, _tsUtc),
      ('a7', AuditOperation.delete, _tsUtc),
      ('a11', AuditOperation.restore, _tsUtc),
      ('a12', AuditOperation.delete, _tsUtc),
    ],
  );
  final o2Audit =
      await db.auditLogDao.getForEntity(AuditEntityType.owner, 'o2');
  expect([for (final e in o2Audit) e.id], ['a2', 'a3']);

  expect(await _count(db, 'SELECT COUNT(*) AS c FROM owners'), 3);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM vehicles'), 5);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM audit_log'), 12);
  await _expectForeignKeysValid(db);
}

/// Checks that the v3 history table exists, starts empty and enforces its
/// rules on an upgraded database: foreign key, CHECKs, and the new
/// `logEntry` audit code.
Future<void> _expectV3HistoryUsable(AppDatabase db, String vehicleId) async {
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM log_entries'), 0);

  final entry = LogEntry(
    id: 'e1',
    vehicleId: vehicleId,
    date: const CalendarDate(2026, 10, 19),
    km: 185500,
    type: LogEntryType.maintenance,
    description: 'Tagliando',
    costCents: 12050,
    createdAt: _tsUtc,
    updatedAt: _tsUtc,
  );
  await db.logEntriesDao.insertEntry(entry);
  expect(await db.logEntriesDao.getLiveById('e1'), entry);
  await db.auditLogDao.insertEntry(
    AuditEntry(
      id: 'a-e1',
      entityType: AuditEntityType.logEntry,
      entityId: 'e1',
      operation: AuditOperation.create,
      at: _tsUtc,
    ),
  );
  final audit =
      await db.auditLogDao.getForEntity(AuditEntityType.logEntry, 'e1');
  expect(audit.single.operation, AuditOperation.create);

  // Foreign key to vehicles, and the two CHECK constraints.
  for (final (id, vehicle, km, cost) in [
    ('e2', 'no-such-vehicle', 1, 0),
    ('e3', vehicleId, -1, 0),
    ('e4', vehicleId, 1, -1),
  ]) {
    await expectLater(
      db.customStatement(
        'INSERT INTO log_entries (id, created_at, updated_at, vehicle_id, '
        'entry_date, km, type, cost_cents) VALUES '
        "('$id', '$_ts', '$_ts', '$vehicle', '2026-10-19', $km, 'note', "
        '$cost)',
      ),
      throwsA(anything),
      reason: 'should be refused: $id',
    );
  }
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM log_entries'), 1);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  /// Writes rows at [fromVersion] with [insert], then migrates them to
  /// [toVersion] and validates the resulting schema.
  Future<AppDatabase> upgrade(
    int fromVersion,
    int toVersion,
    Future<void> Function(GeneratedDatabase) insert,
  ) async {
    final schema = await verifier.schemaAt(fromVersion);
    final oldDb = GeneratedHelper().databaseForVersion(
      schema.newConnection(),
      fromVersion,
    );
    await insert(oldDb);
    await oldDb.close();

    final db = AppDatabase.forExecutor(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, toVersion);
    return db;
  }

  test('rows written at v1 are intact at v2', () async {
    final db = await upgrade(1, 2, _insertV1Rows);
    await _expectV1RowsIntact(db);

    // The v2 model_year CHECK also holds on an upgraded database.
    await expectLater(
      db.customStatement(
        "UPDATE vehicles SET model_year = 1885 WHERE id = 'v1'",
      ),
      throwsA(anything),
    );
  });

  test('rows written at v1 are intact at v$latestVersion (whole chain)',
      () async {
    final db = await upgrade(1, latestVersion, _insertV1Rows);
    await _expectV1RowsIntact(db);
    await _expectV3HistoryUsable(db, 'v1');
  });

  test('rows written at v2 are intact at v3', () async {
    final db = await upgrade(2, 3, _insertV2Rows);
    await _expectV2RowsIntact(db);
    await _expectV3HistoryUsable(db, 'v1');
  });

  /// Writes [insert]'s rows into a real file at [fromVersion], opens it with
  /// the app's database (a real upgrade, as on the phone), checks the rows
  /// with [expectIntact], and checks the pre-upgrade copy.
  Future<void> realUpgrade(
    int fromVersion,
    Future<void> Function(GeneratedDatabase) insert,
    Future<void> Function(AppDatabase) expectIntact, {
    required int vehicleRows,
  }) async {
    final dir = Directory.systemTemp.createTempSync('vehicle_history_up_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final sep = Platform.pathSeparator;
    final dbFile = File('${dir.path}${sep}vehicle_history.sqlite');
    final copyFile = File(
      '${dir.path}${sep}vehicle_history.pre_v$fromVersion.sqlite',
    );

    // The file exactly as the previous app version left it.
    final oldDb = GeneratedHelper().databaseForVersion(
      NativeDatabase(dbFile),
      fromVersion,
    );
    await insert(oldDb);
    await oldDb.close();
    expect(copyFile.existsSync(), isFalse);

    final db = AppDatabase.forExecutor(NativeDatabase(dbFile));
    await db.open();
    await expectIntact(db);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), latestVersion);
    await db.close();

    // The copy is the untouched old file: old version, old shape, all rows.
    expect(copyFile.existsSync(), isTrue);
    final copy = GeneratedHelper().databaseForVersion(
      NativeDatabase(copyFile),
      fromVersion,
    );
    addTearDown(copy.close);
    final copyVersion =
        await copy.customSelect('PRAGMA user_version').getSingle();
    expect(copyVersion.read<int>('user_version'), fromVersion);
    final tables = await copy
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'log_entries'",
        )
        .get();
    expect(tables, isEmpty);
    expect(
      await _count(copy, 'SELECT COUNT(*) AS c FROM vehicles'),
      vehicleRows,
    );
  }

  test('a real upgrade of a v1 file first copies it', () async {
    await realUpgrade(1, _insertV1Rows, _expectV1RowsIntact, vehicleRows: 3);
  });

  test('a real upgrade of a v2 file first copies it', () async {
    await realUpgrade(2, _insertV2Rows, _expectV2RowsIntact, vehicleRows: 5);
  });
}
