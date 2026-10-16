import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';

import 'generated/schema.dart';

/// Data-integrity test for schema upgrades: rows written by an older app
/// version must all be intact after the upgrade.
///
/// For the next schema change:
///
/// 1. run `dart run drift_dev make-migrations` (it regenerates
///    `generated/` for every version);
/// 2. set [toVersion] to the new version;
/// 3. adapt [_insertRealisticRows] only if the old tables changed shape in a
///    way the old SQL no longer expresses (it always targets the *old*
///    schema), and extend the expectations with any new column's default.
///
/// The test must never be weakened to make an upgrade pass.
const int fromVersion = 1;

/// Schema version the app upgrades to.
const int toVersion = 2;

/// Timestamp written into every v1 row.
const String _ts = '2024-03-04T10:30:00.000Z';

/// Writes rows covering every column, NULLs, soft-deleted rows, the audit
/// log and non-ASCII text, using plain SQL against the old schema.
Future<void> _insertRealisticRows(GeneratedDatabase oldDb) async {
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

/// Checks every row and value written by [_insertRealisticRows] after the
/// upgrade to [toVersion].
Future<void> _expectRowsIntact(AppDatabase db) async {
  final ts = DateTime.utc(2024, 3, 4, 10, 30);

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
  expect(owner.createdAt, ts);
  expect(owner.updatedAt, ts);
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
  expect(vehicle.createdAt, ts);
  expect(vehicle.updatedAt, ts);

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
      ('a2', AuditOperation.create, ts),
      ('a4', AuditOperation.restore, ts),
    ]),
  );

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('c');
  expect(await count('SELECT COUNT(*) AS c FROM owners'), 3);
  expect(await count('SELECT COUNT(*) AS c FROM vehicles'), 3);
  expect(await count('SELECT COUNT(*) AS c FROM audit_log'), 4);
  final fkViolations = await db.customSelect('PRAGMA foreign_key_check').get();
  expect(fkViolations, isEmpty);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('rows written at v$fromVersion are intact at v$toVersion', () async {
    final schema = await verifier.schemaAt(fromVersion);

    final oldDb = GeneratedHelper().databaseForVersion(
      schema.newConnection(),
      fromVersion,
    );
    await _insertRealisticRows(oldDb);
    await oldDb.close();

    final db = AppDatabase.forExecutor(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, toVersion);

    await _expectRowsIntact(db);

    // The v2 model_year CHECK also holds on an upgraded database.
    await expectLater(
      db.customStatement(
        "UPDATE vehicles SET model_year = 1885 WHERE id = 'v1'",
      ),
      throwsA(anything),
    );
  });

  test('a real upgrade of a v$fromVersion file first copies it', () async {
    final dir = Directory.systemTemp.createTempSync('vehicle_history_v2_');
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
    await _insertRealisticRows(oldDb);
    await oldDb.close();
    expect(copyFile.existsSync(), isFalse);

    final db = AppDatabase.forExecutor(NativeDatabase(dbFile));
    await db.open();
    await _expectRowsIntact(db);
    await db.close();

    // The copy is the untouched old file: old version, old shape, all rows.
    expect(copyFile.existsSync(), isTrue);
    final copy = GeneratedHelper().databaseForVersion(
      NativeDatabase(copyFile),
      fromVersion,
    );
    addTearDown(copy.close);
    final version = await copy.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), fromVersion);
    final columns =
        await copy.customSelect('PRAGMA table_info(vehicles)').get();
    expect(
      [for (final c in columns) c.read<String>('name')],
      isNot(contains('kind')),
    );
    final rows = await copy
        .customSelect('SELECT COUNT(*) AS c FROM vehicles')
        .getSingle();
    expect(rows.read<int>('c'), 3);
  });
}
