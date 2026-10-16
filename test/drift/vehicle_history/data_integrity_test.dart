import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';

import 'generated/schema.dart';

/// Data-integrity test for schema upgrades: rows written by an older app
/// version must all be intact after the upgrade.
///
/// Today [fromVersion] and [toVersion] are both 1, so this runs as a
/// "no upgrade" baseline that already exercises the whole path. When the
/// schema moves to v2:
///
/// 1. run `dart run drift_dev make-migrations` (it regenerates
///    `generated/` for both versions);
/// 2. set [toVersion] to 2;
/// 3. adapt [_insertRealisticRows] only if the v1 tables changed shape in a
///    way the old SQL no longer expresses (it always targets the *old*
///    schema), and extend the expectations with any new column's default.
///
/// The test must never be weakened to make an upgrade pass.
const int fromVersion = 1;

/// Schema version the app upgrades to.
const int toVersion = 1;

/// Writes rows covering every column, NULLs, soft-deleted rows, the audit
/// log and non-ASCII text, using plain SQL against the old schema.
Future<void> _insertRealisticRows(GeneratedDatabase oldDb) async {
  const ts = '2024-03-04T10:30:00.000Z';
  await oldDb.customStatement(
    'INSERT INTO owners (id, created_at, updated_at, deleted, first_name, '
    'last_name, birth_date, nationality, phone, email, notes, photo_path) '
    "VALUES ('o1', '$ts', '$ts', 0, 'José', 'Núñez', '1980-02-29', "
    "'ES', '+39 333 1234567', 'jose@example.com', 'línea 1\nlínea 2', "
    "'photos/o1.jpg'), "
    "('o2', '$ts', '$ts', 1, 'Deleted', NULL, NULL, NULL, NULL, NULL, NULL, "
    'NULL)',
  );
  await oldDb.customStatement(
    'INSERT INTO vehicles (id, created_at, updated_at, deleted, plate, '
    'nickname, owner_id, current_odometer_km, fuel_type, '
    'recommended_engine_oil, manufacturer_notes, photo_path) '
    "VALUES ('v1', '$ts', '$ts', 0, 'AB123CD', 'Punto', 'o1', 85000, "
    "'petrolLpg', '5W-40', 'Cambio cinghia 4-5 anni', NULL), "
    "('v2', '$ts', '$ts', 1, 'AB123CD', NULL, 'o1', 0, 'diesel', NULL, "
    'NULL, NULL)',
  );
  await oldDb.customStatement(
    'INSERT INTO audit_log (id, entity_type, entity_id, operation, at) '
    "VALUES ('a1', 'owner', 'o1', 'create', '$ts'), "
    "('a2', 'vehicle', 'v1', 'create', '$ts')",
  );
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

    final ts = DateTime.utc(2024, 3, 4, 10, 30);

    final owners = await db.ownersDao.getLive();
    expect(owners, hasLength(1));
    final owner = owners.single;
    expect(owner.id, 'o1');
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

    final vehicles = await db.vehiclesDao.getLive();
    expect(vehicles, hasLength(1));
    final vehicle = vehicles.single;
    expect(vehicle.id, 'v1');
    expect(vehicle.plate, 'AB123CD');
    expect(vehicle.nickname, 'Punto');
    expect(vehicle.ownerId, 'o1');
    expect(vehicle.currentOdometerKm, 85000);
    expect(vehicle.fuelType, FuelType.petrolLpg);
    expect(vehicle.recommendedEngineOil, '5W-40');
    expect(vehicle.manufacturerNotes, 'Cambio cinghia 4-5 anni');

    // Soft-deleted rows and the audit log survive too, row for row.
    Future<int> count(String sql) async =>
        (await db.customSelect(sql).getSingle()).read<int>('c');
    expect(await count('SELECT COUNT(*) AS c FROM owners'), 2);
    expect(await count('SELECT COUNT(*) AS c FROM vehicles'), 2);
    expect(await count('SELECT COUNT(*) AS c FROM audit_log'), 2);
    final fkViolations =
        await db.customSelect('PRAGMA foreign_key_check').get();
    expect(fkViolations, isEmpty);
  });
}
