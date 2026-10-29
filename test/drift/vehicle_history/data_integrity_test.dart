import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/archive_reason.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/mileage_reading.dart';
import 'package:vehicle_history/data/models/setting_key.dart';
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
const int latestVersion = 9;

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

// ---------------------------------------------------------------------------
// Rows written at v3.
// ---------------------------------------------------------------------------

/// A second creation instant, so the initial readings are checked against
/// more than one `created_at`. Noon UTC: the same local day in any timezone
/// within ±11 hours.
const String _ts2 = '2025-06-15T12:00:00.000Z';

/// Writes rows covering every v3 table using plain SQL against the v3
/// schema: owners (one soft-deleted), vehicles of every kind (one
/// soft-deleted, one at 0 km), history entries of several types with and
/// without km and cost (one soft-deleted, one of the deleted vehicle) and
/// the audit log with `logEntry` rows.
Future<void> _insertV3Rows(GeneratedDatabase oldDb) async {
  await oldDb.customStatement(
    'INSERT INTO owners (id, created_at, updated_at, deleted, first_name, '
    'last_name, birth_date, nationality, phone, email, notes, photo_path) '
    "VALUES ('o1', '$_ts', '$_ts', 0, 'Javier', 'Muñoz', '1987-05-20', "
    "'ES', '+39 333 7654321', NULL, NULL, NULL), "
    "('o2', '$_ts', '$_ts', 1, 'Borrado', NULL, NULL, NULL, NULL, NULL, NULL, "
    'NULL)',
  );
  await oldDb.customStatement(
    'INSERT INTO vehicles (id, created_at, updated_at, deleted, plate, kind, '
    'make, make_slug, model, model_slug, model_year, version, nickname, '
    'owner_id, current_odometer_km, fuel_type, recommended_engine_oil, '
    'manufacturer_notes, photo_path) VALUES '
    "('v1', '$_ts', '$_ts2', 0, 'AB123CD', 'car', 'Fiat', 'fiat', 'Punto', "
    "'punto', 2012, '1.2 69 CV Lounge', 'Punto', 'o1', 123456, 'petrolLpg', "
    "'5W-40', NULL, NULL), "
    "('v2', '$_ts2', '$_ts2', 1, 'CD456EF', 'van', 'Fiat', 'fiat', 'Doblò', "
    "'doblo', 2015, NULL, NULL, 'o1', 99000, 'diesel', NULL, NULL, NULL), "
    "('v3', '$_ts2', '$_ts2', 0, 'EX12345', 'motorcycle', 'Honda', 'honda', "
    "'SH125', 'sh125', 2020, NULL, NULL, 'o1', 12000, 'petrol', NULL, NULL, "
    'NULL), '
    "('v4', '$_ts', '$_ts', 0, 'X7Y8Z9', 'moped', 'Malagùti', NULL, "
    "'Fifty Top', NULL, NULL, NULL, NULL, 'o1', 0, 'petrol', NULL, NULL, "
    'NULL)',
  );
  await oldDb.customStatement(
    'INSERT INTO log_entries (id, created_at, updated_at, deleted, '
    'vehicle_id, entry_date, km, type, description, cost_cents) VALUES '
    "('e1', '$_ts', '$_ts', 0, 'v1', '2026-03-01', 120000, 'maintenance', "
    "'Tagliando: olio e filtri', 18950), "
    "('e2', '$_ts', '$_ts', 0, 'v1', '2026-04-10', NULL, 'legalDue', "
    "'Bollo auto', 21230), "
    "('e3', '$_ts', '$_ts2', 0, 'v1', '2026-05-02', 121500, 'refuel', NULL, "
    '0), '
    "('e4', '$_ts', '$_ts', 1, 'v1', '2026-05-03', 121600, 'repair', "
    "'Borrada', NULL), "
    "('e5', '$_ts2', '$_ts2', 0, 'v2', '2026-01-15', NULL, 'note', "
    "'Multa per eccesso di velocità', NULL), "
    "('e6', '$_ts2', '$_ts2', 0, 'v3', '2026-02-20', 11800, 'genericCheck', "
    "'Pressione gomme', NULL)",
  );
  await oldDb.customStatement(
    'INSERT INTO audit_log (id, entity_type, entity_id, operation, at) '
    "VALUES ('a1', 'owner', 'o1', 'create', '$_ts'), "
    "('a2', 'vehicle', 'v1', 'create', '$_ts'), "
    "('a3', 'vehicle', 'v2', 'create', '$_ts2'), "
    "('a4', 'vehicle', 'v2', 'delete', '$_ts2'), "
    "('a5', 'logEntry', 'e1', 'create', '$_ts'), "
    "('a6', 'logEntry', 'e4', 'create', '$_ts'), "
    "('a7', 'logEntry', 'e4', 'delete', '$_ts'), "
    "('a8', 'logEntry', 'e3', 'update', '$_ts2')",
  );
}

/// Checks every row and value written by [_insertV3Rows] after an upgrade
/// to v4 or later.
Future<void> _expectV3RowsIntact(AppDatabase db) async {
  final owners = await db.ownersDao.getLive();
  expect([for (final o in owners) o.id], ['o1']);
  final owner = owners.single;
  expect((owner.firstName, owner.lastName), ('Javier', 'Muñoz'));
  expect(owner.birthDate, const CalendarDate(1987, 5, 20));
  expect(owner.phone, '+39 333 7654321');

  final vehicles = {
    for (final v in await db.vehiclesDao.getLive()) v.id: v,
  };
  expect(vehicles.keys, unorderedEquals(['v1', 'v3', 'v4']));
  final punto = vehicles['v1']!;
  expect((punto.make, punto.model, punto.modelYear), ('Fiat', 'Punto', 2012));
  expect((punto.makeSlug, punto.modelSlug), ('fiat', 'punto'));
  expect(punto.version, '1.2 69 CV Lounge');
  expect(punto.currentOdometerKm, 123456);
  expect(punto.fuelType, FuelType.petrolLpg);
  expect(punto.createdAt, _tsUtc);
  expect(punto.updatedAt, DateTime.utc(2025, 6, 15, 12));
  expect(vehicles['v3']!.kind, VehicleKind.motorcycle);
  expect(vehicles['v4']!.currentOdometerKm, 0);
  final van = await db.vehiclesDao.getDeletedById('v2');
  expect(van?.model, 'Doblò');
  expect(van?.currentOdometerKm, 99000);

  final entries = await db.logEntriesDao.getLiveByVehicle('v1');
  expect([for (final e in entries) e.id], ['e3', 'e2', 'e1']);
  final service = entries.last;
  expect(service.type, LogEntryType.maintenance);
  expect(service.date, const CalendarDate(2026, 3, 1));
  expect(service.km, 120000);
  expect(service.description, 'Tagliando: olio e filtri');
  expect(service.costCents, 18950);
  final tax = entries[1];
  expect(
    (tax.type, tax.km, tax.costCents),
    (LogEntryType.legalDue, null, 21230),
  );
  final refuel = entries.first;
  expect(
    (refuel.type, refuel.description, refuel.costCents),
    (LogEntryType.refuel, null, 0),
  );
  expect(refuel.updatedAt, DateTime.utc(2025, 6, 15, 12));
  expect(await db.logEntriesDao.getDeletedById('e4'), isNotNull);
  final check = await db.logEntriesDao.getLiveByVehicle('v3');
  expect(check.single.type, LogEntryType.genericCheck);
  expect(check.single.description, 'Pressione gomme');
  // The entry of the deleted vehicle is on disk but hidden, as before.
  expect(await db.logEntriesDao.getLiveById('e5'), isNull);

  final e4Audit =
      await db.auditLogDao.getForEntity(AuditEntityType.logEntry, 'e4');
  expect(
    [for (final e in e4Audit) (e.id, e.operation, e.at)],
    [
      ('a6', AuditOperation.create, _tsUtc),
      ('a7', AuditOperation.delete, _tsUtc),
    ],
  );

  expect(await _count(db, 'SELECT COUNT(*) AS c FROM owners'), 2);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM vehicles'), 4);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM log_entries'), 6);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM audit_log'), 8);
  await _expectForeignKeysValid(db);
}

/// Checks the initial readings inserted by the v3 → v4 upgrade: every
/// vehicle row, deleted or not, has exactly one live reading with its
/// `current_odometer_km`, dated on the local day of its `created_at`, with
/// its `created_at` as timestamps. The upgrade adds no audit row, so the
/// audit log still has its [auditRows] rows.
Future<void> _expectInitialReadings(AppDatabase db, int auditRows) async {
  final vehicles = await db
      .customSelect('SELECT id, created_at, current_odometer_km FROM vehicles')
      .get();
  expect(vehicles, isNotEmpty);
  for (final vehicle in vehicles) {
    final id = vehicle.read<String>('id');
    final readings = await db.customSelect(
      'SELECT id, created_at, updated_at, deleted, reading_date, km '
      'FROM mileage_readings WHERE vehicle_id = ?',
      variables: [Variable(id)],
    ).get();
    expect(readings, hasLength(1), reason: 'readings of $id');
    final reading = readings.single;
    final createdAt = vehicle.read<String>('created_at');
    expect(reading.read<int>('km'), vehicle.read<int>('current_odometer_km'));
    expect(
      reading.read<String>('reading_date'),
      CalendarDate.localDayOf(DateTime.parse(createdAt)).toIso8601String(),
    );
    expect(reading.read<String>('created_at'), createdAt);
    expect(reading.read<String>('updated_at'), createdAt);
    expect(reading.read<bool>('deleted'), isFalse);
    // A UUID v4, like every id written by the app.
    expect(reading.read<String>('id'), hasLength(36));
  }
  expect(
    await _count(db, 'SELECT COUNT(*) AS c FROM mileage_readings'),
    vehicles.length,
  );
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM audit_log'), auditRows);
  await _expectForeignKeysValid(db);
}

/// Checks that the v4 odometer table enforces its rules on an upgraded
/// database: foreign key, CHECK, and the new `mileageReading` audit code.
Future<void> _expectV4ReadingsUsable(AppDatabase db, String vehicleId) async {
  final reading = MileageReading(
    id: 'r-new',
    vehicleId: vehicleId,
    date: const CalendarDate(2026, 10, 19),
    km: 200000,
    createdAt: _tsUtc,
    updatedAt: _tsUtc,
  );
  await db.mileageReadingsDao.insertReading(reading);
  expect(await db.mileageReadingsDao.getLiveById('r-new'), reading);
  await db.auditLogDao.insertEntry(
    AuditEntry(
      id: 'a-r-new',
      entityType: AuditEntityType.mileageReading,
      entityId: 'r-new',
      operation: AuditOperation.create,
      at: _tsUtc,
    ),
  );
  final audit = await db.auditLogDao
      .getForEntity(AuditEntityType.mileageReading, 'r-new');
  expect(audit.single.operation, AuditOperation.create);

  // Foreign key to vehicles, and the CHECK constraint.
  for (final (id, vehicle, km) in [
    ('r-bad-1', 'no-such-vehicle', 1),
    ('r-bad-2', vehicleId, -1),
  ]) {
    await expectLater(
      db.customStatement(
        'INSERT INTO mileage_readings (id, created_at, updated_at, '
        "vehicle_id, reading_date, km) VALUES ('$id', '$_ts', '$_ts', "
        "'$vehicle', '2026-10-19', $km)",
      ),
      throwsA(anything),
      reason: 'should be refused: $id',
    );
  }
}

// ---------------------------------------------------------------------------
// Rows written at v4.
// ---------------------------------------------------------------------------

/// A third instant: when the soft-deleted v4 rows were deleted, so the
/// `deleted_at` backfill is checked against a value that differs from
/// `created_at`. With microseconds, as `DateTime.now()` writes them.
const String _ts3 = '2026-09-01T08:15:30.123456Z';

/// [_ts3] as the UTC instant the domain models carry.
final DateTime _ts3Utc = DateTime.parse(_ts3);

/// Writes rows covering every v4 table using plain SQL against the v4
/// schema: owners (one soft-deleted), vehicles (one soft-deleted, the
/// Trash's future content), history entries (one soft-deleted, one of the
/// deleted vehicle), odometer readings (initial ones, a later one, a
/// soft-deleted one, the deleted vehicle's) and the audit log with
/// `mileageReading` rows.
Future<void> _insertV4Rows(GeneratedDatabase oldDb) async {
  await oldDb.customStatement(
    'INSERT INTO owners (id, created_at, updated_at, deleted, first_name, '
    'last_name, birth_date, nationality, phone, email, notes, photo_path) '
    "VALUES ('o1', '$_ts', '$_ts2', 0, 'Javier', 'Muñoz', '1987-05-20', "
    "'ES', '+39 333 7654321', 'javier@example.com', NULL, NULL), "
    "('o2', '$_ts', '$_ts3', 1, 'Borrado', NULL, NULL, 'IT', NULL, NULL, "
    'NULL, NULL)',
  );
  await oldDb.customStatement(
    'INSERT INTO vehicles (id, created_at, updated_at, deleted, plate, kind, '
    'make, make_slug, model, model_slug, model_year, version, nickname, '
    'owner_id, current_odometer_km, fuel_type, recommended_engine_oil, '
    'manufacturer_notes, photo_path) VALUES '
    "('v1', '$_ts', '$_ts2', 0, 'AB123CD', 'car', 'Fiat', 'fiat', 'Punto', "
    "'punto', 2012, '1.2 69 CV Lounge', 'Punto', 'o1', 124000, 'petrolLpg', "
    "'5W-40', NULL, NULL), "
    "('v2', '$_ts2', '$_ts3', 1, 'CD456EF', 'van', 'Fiat', 'fiat', 'Doblò', "
    "'doblo', 2015, NULL, NULL, 'o1', 99000, 'diesel', NULL, NULL, NULL)",
  );
  await oldDb.customStatement(
    'INSERT INTO log_entries (id, created_at, updated_at, deleted, '
    'vehicle_id, entry_date, km, type, description, cost_cents) VALUES '
    "('e1', '$_ts', '$_ts', 0, 'v1', '2026-03-01', 120000, 'maintenance', "
    "'Tagliando: olio e filtri', 18950), "
    "('e2', '$_ts', '$_ts3', 1, 'v1', '2026-05-03', 121600, 'repair', "
    "'Borrada', NULL), "
    "('e3', '$_ts2', '$_ts2', 0, 'v2', '2026-01-15', NULL, 'note', "
    "'Multa per eccesso di velocità', 4200)",
  );
  await oldDb.customStatement(
    'INSERT INTO mileage_readings (id, created_at, updated_at, deleted, '
    'vehicle_id, reading_date, km) VALUES '
    "('r1', '$_ts', '$_ts', 0, 'v1', '2024-03-04', 100000), "
    "('r2', '$_ts2', '$_ts2', 0, 'v1', '2025-06-15', 124000), "
    "('r3', '$_ts2', '$_ts3', 1, 'v1', '2025-06-16', 124100), "
    "('r4', '$_ts2', '$_ts2', 0, 'v2', '2025-06-15', 99000)",
  );
  await oldDb.customStatement(
    'INSERT INTO audit_log (id, entity_type, entity_id, operation, at) '
    "VALUES ('a1', 'owner', 'o1', 'create', '$_ts'), "
    "('a2', 'owner', 'o2', 'delete', '$_ts3'), "
    "('a3', 'vehicle', 'v2', 'delete', '$_ts3'), "
    "('a4', 'logEntry', 'e2', 'delete', '$_ts3'), "
    "('a5', 'mileageReading', 'r2', 'create', '$_ts2'), "
    "('a6', 'mileageReading', 'r3', 'delete', '$_ts3')",
  );
}

/// Checks every row and value written by [_insertV4Rows] after an upgrade
/// to v5 or later, including the `deleted_at` backfill row by row.
Future<void> _expectV4RowsIntact(AppDatabase db) async {
  final owner = (await db.ownersDao.getLive()).single;
  expect(owner.id, 'o1');
  expect((owner.firstName, owner.lastName), ('Javier', 'Muñoz'));
  expect(owner.email, 'javier@example.com');
  expect(owner.updatedAt, DateTime.utc(2025, 6, 15, 12));

  final punto = (await db.vehiclesDao.getLive()).single;
  expect(punto.id, 'v1');
  expect((punto.make, punto.model, punto.modelYear), ('Fiat', 'Punto', 2012));
  expect(punto.version, '1.2 69 CV Lounge');
  expect(punto.currentOdometerKm, 124000);
  expect(punto.updatedAt, DateTime.utc(2025, 6, 15, 12));
  final van = await db.vehiclesDao.getDeletedById('v2');
  expect(van?.model, 'Doblò');
  expect(van?.updatedAt, _ts3Utc);

  final entries = await db.logEntriesDao.getLiveByVehicle('v1');
  expect([for (final e in entries) e.id], ['e1']);
  expect(entries.single.costCents, 18950);
  expect(entries.single.description, 'Tagliando: olio e filtri');
  expect(await db.logEntriesDao.getDeletedById('e2'), isNotNull);
  // The entry of the deleted vehicle is on disk but hidden, as before.
  expect(await db.logEntriesDao.getLiveById('e3'), isNull);

  final readings = await db.mileageReadingsDao.getLiveByVehicle('v1');
  expect(
    [for (final r in readings) (r.id, r.km)],
    [('r2', 124000), ('r1', 100000)],
  );
  expect(await db.mileageReadingsDao.getDeletedById('r3'), isNotNull);
  expect(await db.mileageReadingsDao.countLive('v2'), 1);

  // `deleted_at`: the instant of the delete on deleted rows, NULL on live
  // ones, stored as the very same text as `updated_at`.
  for (final (table, id, expected) in [
    ('owners', 'o1', null),
    ('owners', 'o2', _ts3),
    ('vehicles', 'v1', null),
    ('vehicles', 'v2', _ts3),
    ('log_entries', 'e1', null),
    ('log_entries', 'e2', _ts3),
    ('log_entries', 'e3', null),
    ('mileage_readings', 'r1', null),
    ('mileage_readings', 'r2', null),
    ('mileage_readings', 'r3', _ts3),
    ('mileage_readings', 'r4', null),
  ]) {
    final row = await db.customSelect(
      'SELECT deleted_at FROM $table WHERE id = ?',
      variables: [Variable(id)],
    ).getSingle();
    expect(row.read<String?>('deleted_at'), expected, reason: '$table $id');
  }

  // The audit log is untouched, row for row.
  final audit = await db
      .customSelect(
        'SELECT id, entity_type, entity_id, operation, at FROM audit_log '
        'ORDER BY id',
      )
      .get();
  expect(
    [
      for (final r in audit)
        [
          r.read<String>('id'),
          r.read<String>('entity_type'),
          r.read<String>('entity_id'),
          r.read<String>('operation'),
          r.read<String>('at'),
        ].join(' '),
    ],
    [
      'a1 owner o1 create $_ts',
      'a2 owner o2 delete $_ts3',
      'a3 vehicle v2 delete $_ts3',
      'a4 logEntry e2 delete $_ts3',
      'a5 mileageReading r2 create $_ts2',
      'a6 mileageReading r3 delete $_ts3',
    ],
  );

  expect(await _count(db, 'SELECT COUNT(*) AS c FROM owners'), 2);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM vehicles'), 2);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM log_entries'), 3);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM mileage_readings'), 4);
  await _expectForeignKeysValid(db);
}

/// Checks the v4 → v5 backfill on any upgraded database: in every
/// soft-deletable table, deleted rows have `deleted_at = updated_at` and
/// live rows have `deleted_at` NULL.
Future<void> _expectDeletedAtBackfilled(GeneratedDatabase db) async {
  for (final table in [
    'owners',
    'vehicles',
    'log_entries',
    'mileage_readings',
  ]) {
    expect(
      await _count(
        db,
        'SELECT COUNT(*) AS c FROM $table WHERE '
        '(deleted = 1 AND deleted_at IS NOT updated_at) OR '
        '(deleted = 0 AND deleted_at IS NOT NULL)',
      ),
      0,
      reason: table,
    );
  }
}

/// Number of rows of [table] with `deleted_at` set.
Future<int> _countDeletedAt(GeneratedDatabase db, String table) => _count(
      db,
      'SELECT COUNT(*) AS c FROM $table WHERE deleted_at IS NOT NULL',
    );

// ---------------------------------------------------------------------------
// Rows written at v5.
// ---------------------------------------------------------------------------

/// Deletion instant of the soft-deleted rows written at v5.
const String _ts4 = '2026-10-01T08:15:00.000Z';

/// [_ts4] as the UTC instant the domain models carry.
final DateTime _ts4Utc = DateTime.parse(_ts4);

/// Writes rows covering every v5 table using plain SQL against the v5
/// schema: owners (one soft-deleted with `deleted_at`), vehicles (one in the
/// Trash), entries and readings (live, deleted, and those of the trashed
/// vehicle) and the audit log with `restore` and `purge` rows.
Future<void> _insertV5Rows(GeneratedDatabase oldDb) async {
  await oldDb.customStatement(
    'INSERT INTO owners (id, created_at, updated_at, deleted, deleted_at, '
    'first_name, last_name, birth_date, nationality, phone, email, notes, '
    'photo_path) VALUES '
    "('o1', '$_ts', '$_ts2', 0, NULL, 'Javier', 'Muñoz', '1987-05-20', "
    "'ES', '+39 333 7654321', 'javier@example.com', 'Nota: ñ, à, €', NULL), "
    "('o2', '$_ts', '$_ts4', 1, '$_ts4', 'Borrado', NULL, NULL, 'IT', NULL, "
    'NULL, NULL, NULL)',
  );
  await oldDb.customStatement(
    'INSERT INTO vehicles (id, created_at, updated_at, deleted, deleted_at, '
    'plate, kind, make, make_slug, model, model_slug, model_year, version, '
    'nickname, owner_id, current_odometer_km, fuel_type, '
    'recommended_engine_oil, manufacturer_notes, photo_path) VALUES '
    "('v1', '$_ts', '$_ts2', 0, NULL, 'AB123CD', 'car', 'Fiat', 'fiat', "
    "'Punto', 'punto', 2012, '1.2 69 CV Lounge', 'Punto', 'o1', 124500, "
    "'petrolLpg', '5W-40', 'Cinghia ogni 5 anni', NULL), "
    "('v2', '$_ts2', '$_ts4', 1, '$_ts4', 'CD456EF', 'van', 'Fiat', 'fiat', "
    "'Doblò', 'doblo', 2015, NULL, NULL, 'o1', 99000, 'diesel', NULL, NULL, "
    'NULL)',
  );
  await oldDb.customStatement(
    'INSERT INTO log_entries (id, created_at, updated_at, deleted, '
    'deleted_at, vehicle_id, entry_date, km, type, description, cost_cents) '
    'VALUES '
    "('e1', '$_ts', '$_ts', 0, NULL, 'v1', '2026-03-01', 120000, "
    "'maintenance', 'Tagliando: olio e filtri', 18950), "
    "('e2', '$_ts', '$_ts4', 1, '$_ts4', 'v1', '2026-05-03', 121600, "
    "'repair', 'Borrada', NULL), "
    "('e3', '$_ts2', '$_ts2', 0, NULL, 'v2', '2026-01-15', NULL, 'note', "
    "'Multa per eccesso di velocità', 4200), "
    "('e4', '$_ts2', '$_ts2', 0, NULL, 'v1', '2026-12-31', NULL, "
    "'legalDue', 'Revisione', NULL)",
  );
  await oldDb.customStatement(
    'INSERT INTO mileage_readings (id, created_at, updated_at, deleted, '
    'deleted_at, vehicle_id, reading_date, km) VALUES '
    "('r1', '$_ts', '$_ts', 0, NULL, 'v1', '2024-03-04', 100000), "
    "('r2', '$_ts2', '$_ts2', 0, NULL, 'v1', '2025-06-15', 124500), "
    "('r3', '$_ts2', '$_ts4', 1, '$_ts4', 'v1', '2025-06-16', 124600), "
    "('r4', '$_ts2', '$_ts2', 0, NULL, 'v2', '2025-06-15', 99000)",
  );
  await oldDb.customStatement(
    'INSERT INTO audit_log (id, entity_type, entity_id, operation, at) '
    "VALUES ('a1', 'owner', 'o1', 'create', '$_ts'), "
    "('a2', 'owner', 'o2', 'delete', '$_ts4'), "
    "('a3', 'vehicle', 'v2', 'delete', '$_ts4'), "
    "('a4', 'logEntry', 'e2', 'delete', '$_ts4'), "
    "('a5', 'mileageReading', 'r3', 'delete', '$_ts4'), "
    "('a6', 'vehicle', 'v9', 'purge', '$_ts3'), "
    "('a7', 'logEntry', 'e1', 'restore', '$_ts2')",
  );
}

/// Checks every row and value written by [_insertV5Rows] after an upgrade
/// to v6 or later, `deleted_at` included.
Future<void> _expectV5RowsIntact(AppDatabase db) async {
  final owner = (await db.ownersDao.getLive()).single;
  expect(owner.id, 'o1');
  expect((owner.firstName, owner.lastName), ('Javier', 'Muñoz'));
  expect(owner.birthDate, const CalendarDate(1987, 5, 20));
  expect(owner.notes, 'Nota: ñ, à, €');
  expect(owner.updatedAt, DateTime.parse(_ts2));

  final punto = (await db.vehiclesDao.getLive()).single;
  expect(punto.id, 'v1');
  expect((punto.make, punto.model, punto.modelYear), ('Fiat', 'Punto', 2012));
  expect(punto.manufacturerNotes, 'Cinghia ogni 5 anni');
  expect(punto.currentOdometerKm, 124500);

  // The Trash is still the Trash: the van, with its deletion instant
  // (checked below with every `deleted_at`).
  final van = await db.vehiclesDao.getDeletedById('v2');
  expect(van?.model, 'Doblò');

  final entries = await db.logEntriesDao.getLiveByVehicle('v1');
  expect([for (final e in entries) e.id], unorderedEquals(['e1', 'e4']));
  expect(entries.singleWhere((e) => e.id == 'e1').costCents, 18950);
  expect(await db.logEntriesDao.getDeletedById('e2'), isNotNull);
  // The entry of the trashed vehicle is on disk but hidden, as before.
  expect(await db.logEntriesDao.getLiveById('e3'), isNull);

  final readings = await db.mileageReadingsDao.getLiveByVehicle('v1');
  expect(
    [for (final r in readings) (r.id, r.km)],
    [('r2', 124500), ('r1', 100000)],
  );
  expect(await db.mileageReadingsDao.getDeletedById('r3'), isNotNull);

  // `deleted_at` exactly as written, row by row.
  for (final (table, id, expected) in [
    ('owners', 'o1', null),
    ('owners', 'o2', _ts4),
    ('vehicles', 'v1', null),
    ('vehicles', 'v2', _ts4),
    ('log_entries', 'e2', _ts4),
    ('log_entries', 'e3', null),
    ('mileage_readings', 'r3', _ts4),
    ('mileage_readings', 'r4', null),
  ]) {
    final row = await db.customSelect(
      'SELECT deleted_at FROM $table WHERE id = ?',
      variables: [Variable(id)],
    ).getSingle();
    expect(row.read<String?>('deleted_at'), expected, reason: '$table $id');
  }

  // The audit log is untouched, row for row, `purge` included.
  final audit = await db
      .customSelect(
        'SELECT id, entity_type, entity_id, operation, at FROM audit_log '
        'ORDER BY id',
      )
      .get();
  expect(
    [
      for (final r in audit)
        [
          r.read<String>('id'),
          r.read<String>('entity_type'),
          r.read<String>('entity_id'),
          r.read<String>('operation'),
          r.read<String>('at'),
        ].join(' '),
    ],
    [
      'a1 owner o1 create $_ts',
      'a2 owner o2 delete $_ts4',
      'a3 vehicle v2 delete $_ts4',
      'a4 logEntry e2 delete $_ts4',
      'a5 mileageReading r3 delete $_ts4',
      'a6 vehicle v9 purge $_ts3',
      'a7 logEntry e1 restore $_ts2',
    ],
  );
  final purged =
      await db.auditLogDao.getForEntity(AuditEntityType.vehicle, 'v9');
  expect(purged.single.operation, AuditOperation.purge);

  expect(await _count(db, 'SELECT COUNT(*) AS c FROM owners'), 2);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM vehicles'), 2);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM log_entries'), 4);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM mileage_readings'), 4);
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM audit_log'), 7);
  await _expectForeignKeysValid(db);
}

/// Checks that the v6 `settings` table exists, starts empty and works on an
/// upgraded database.
Future<void> _expectV6SettingsUsable(AppDatabase db) async {
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM settings'), 0);
  expect(await db.settingsDao.readValue(SettingKey.lastExportAt), isNull);
  await db.settingsDao.writeValue(SettingKey.lastExportAt, _ts4, _ts4Utc);
  expect(await db.settingsDao.readValue(SettingKey.lastExportAt), _ts4);
}

// ---------------------------------------------------------------------------
// Rows written at v6.
// ---------------------------------------------------------------------------

/// Writes the v5 rows (the v6 schema has the same tables plus `settings`)
/// and a row for every setting key, as the step-6 and step-7 apps write
/// them, using plain SQL against the v6 schema.
Future<void> _insertV6Rows(GeneratedDatabase oldDb) async {
  await _insertV5Rows(oldDb);
  await oldDb.customStatement(
    'INSERT INTO settings (key, value, updated_at) VALUES '
    "('last_export_at', '$_ts4', '$_ts4'), "
    "('language', 'es', '$_ts3'), "
    "('theme', 'dark', '$_ts2'), "
    // A cleared value is a NULL, not a missing row.
    "('future_key', NULL, '$_ts')",
  );
}

/// Checks every row written by [_insertV6Rows] after an upgrade to v7 or
/// later: the v5 rows and the settings, row for row.
Future<void> _expectV6RowsIntact(AppDatabase db) async {
  await _expectV5RowsIntact(db);
  final settings = await db
      .customSelect('SELECT key, value, updated_at FROM settings ORDER BY key')
      .get();
  expect(
    [
      for (final r in settings)
        '${r.read<String>('key')}=${r.read<String?>('value')}'
            '@${r.read<String>('updated_at')}',
    ],
    [
      'future_key=null@$_ts',
      'language=es@$_ts3',
      'last_export_at=$_ts4@$_ts4',
      'theme=dark@$_ts2',
    ],
  );
  expect(await db.settingsDao.readValue(SettingKey.language), 'es');
  expect(await db.settingsDao.readValue(SettingKey.theme), 'dark');
}

/// Checks that the v7 `attachments` table exists, starts empty, keeps its
/// CHECK and works on an upgraded database.
Future<void> _expectV7AttachmentsUsable(AppDatabase db) async {
  expect(await _count(db, 'SELECT COUNT(*) AS c FROM attachments'), 0);
  const columns = 'id, created_at, updated_at, deleted, entity_type, '
      'entity_id, kind, file_name, mime_type, relative_path, size_bytes, '
      'caption, sort_order';
  await db.customStatement(
    'INSERT INTO attachments ($columns) VALUES '
    "('t1', '$_ts4', '$_ts4', 0, 'vehicle', 'v1', 'pdf', 'Libretto.pdf', "
    "'application/pdf', 'attachments/t1.pdf', 1234, 'Libretto', 0)",
  );
  final rows = await db
      .customSelect(
        'SELECT file_name, size_bytes FROM attachments '
        "WHERE entity_type = 'vehicle' AND entity_id = 'v1'",
      )
      .get();
  expect(rows.single.read<String>('file_name'), 'Libretto.pdf');
  // A negative size is refused by the CHECK of the new table.
  await expectLater(
    db.customStatement(
      'INSERT INTO attachments ($columns) VALUES '
      "('t2', '$_ts4', '$_ts4', 0, 'vehicle', 'v1', 'pdf', 'x.pdf', "
      "'application/pdf', 'attachments/t2.pdf', -1, NULL, 1)",
    ),
    throwsA(anything),
  );
  // The index exists, so the per-entity reads use it.
  final index = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name = 'attachments_entity'",
      )
      .get();
  expect(index, hasLength(1));
}

// ---------------------------------------------------------------------------
// Rows written at v7.
// ---------------------------------------------------------------------------

/// Writes the v6 rows (the v7 schema has the same tables plus
/// `attachments`) and two attachment rows, one of them deleted, as the
/// step-8 / 9 apps write them, using plain SQL against the v7 schema.
Future<void> _insertV7Rows(GeneratedDatabase oldDb) async {
  await _insertV6Rows(oldDb);
  await oldDb.customStatement(
    'INSERT INTO attachments (id, created_at, updated_at, deleted, '
    'deleted_at, entity_type, entity_id, kind, file_name, mime_type, '
    'relative_path, size_bytes, caption, sort_order) VALUES '
    "('t1', '$_ts4', '$_ts4', 0, NULL, 'vehicle', 'v1', 'pdf', "
    "'Libretto.pdf', 'application/pdf', 'attachments/t1.pdf', 1234, "
    "'Libretto', 0), "
    "('t2', '$_ts4', '$_ts4', 1, '$_ts4', 'logEntry', 'e1', 'image', "
    "'Scontrino.jpg', 'image/jpeg', 'attachments/t2.jpg', 99, NULL, 0)",
  );
}

/// Checks every row written by [_insertV7Rows] after an upgrade to v8 or
/// later: the v6 rows and the attachments, row for row.
Future<void> _expectV7RowsIntact(AppDatabase db) async {
  await _expectV6RowsIntact(db);
  final rows = await db
      .customSelect(
        'SELECT id, deleted, deleted_at, entity_type, entity_id, kind, '
        'file_name, mime_type, relative_path, size_bytes, caption, '
        'sort_order FROM attachments ORDER BY id',
      )
      .get();
  expect(
    [
      for (final r in rows)
        [
          r.read<String>('id'),
          r.read<bool>('deleted'),
          r.read<String?>('deleted_at'),
          r.read<String>('entity_type'),
          r.read<String>('entity_id'),
          r.read<String>('kind'),
          r.read<String>('file_name'),
          r.read<String>('mime_type'),
          r.read<String>('relative_path'),
          r.read<int>('size_bytes'),
          r.read<String?>('caption'),
          r.read<int>('sort_order'),
        ].join(' '),
    ],
    [
      't1 false null vehicle v1 pdf Libretto.pdf application/pdf '
          'attachments/t1.pdf 1234 Libretto 0',
      't2 true $_ts4 logEntry e1 image Scontrino.jpg image/jpeg '
          'attachments/t2.jpg 99 null 0',
    ],
  );
}

/// Checks the v8 archive columns on an upgraded database: every vehicle is
/// active (all four NULL), the DAO reads them, an archive works and keeps
/// the CHECK, and the active read leaves the archived vehicle out.
Future<void> _expectV8ArchiveUsable(AppDatabase db) async {
  expect(
    await _count(
      db,
      'SELECT COUNT(*) AS c FROM vehicles WHERE archived_at IS NOT NULL '
      'OR archive_reason IS NOT NULL OR archive_note IS NOT NULL '
      'OR archived_km IS NOT NULL',
    ),
    0,
  );
  final before = await db.vehiclesDao.getActive();
  expect(before.every((v) => !v.isArchived), isTrue);
  expect(before.map((v) => v.id), contains('v1'));

  await db.customStatement(
    "UPDATE vehicles SET archived_at = '2026-03-12', archive_reason = 'sold', "
    "archive_note = 'A Luca', archived_km = 184300 WHERE id = 'v1'",
  );
  final archived = (await db.vehiclesDao.getLiveById('v1'))!;
  expect(archived.isArchived, isTrue);
  expect(archived.archivedAt, const CalendarDate(2026, 3, 12));
  expect(archived.archiveReason, ArchiveReason.sold);
  expect(archived.archiveNote, 'A Luca');
  expect(archived.archivedKm, 184300);
  expect(
    (await db.vehiclesDao.getActive()).map((v) => v.id),
    isNot(contains('v1')),
  );
  expect(
    (await db.vehiclesDao.watchArchived().first).map((v) => v.id),
    ['v1'],
  );
  // A negative final km is refused by the CHECK of the new column.
  await expectLater(
    db.customStatement("UPDATE vehicles SET archived_km = -1 WHERE id = 'v1'"),
    throwsA(anything),
  );
  await db.customStatement(
    'UPDATE vehicles SET archived_at = NULL, archive_reason = NULL, '
    "archive_note = NULL, archived_km = NULL WHERE id = 'v1'",
  );
}

// ---------------------------------------------------------------------------
// Rows written at v8.
// ---------------------------------------------------------------------------

/// Writes the v7 rows and then uses the v8 archive columns: `v1` archived
/// with a final km. No new rows, so every count of the older checks holds;
/// every km is an INTEGER, as every version up to v8 stored them.
Future<void> _insertV8Rows(GeneratedDatabase oldDb) async {
  await _insertV7Rows(oldDb);
  await oldDb.customStatement(
    "UPDATE vehicles SET archived_at = '2026-03-12', archive_reason = 'sold', "
    "archive_note = 'A Luca', archived_km = 184300 WHERE id = 'v1'",
  );
}

/// Checks every row written by [_insertV8Rows] after an upgrade to v9 or
/// later: the v7 rows and the archived vehicle, with every km now a REAL
/// holding the same value, plus the indexes and the foreign keys of the
/// recreated tables.
Future<void> _expectV8RowsIntact(AppDatabase db) async {
  await _expectV7RowsIntact(db);

  final vehicle = (await db.vehiclesDao.getLiveById('v1'))!;
  expect(vehicle.isArchived, isTrue);
  expect(vehicle.archivedAt, const CalendarDate(2026, 3, 12));
  expect(vehicle.archiveReason, ArchiveReason.sold);
  expect(vehicle.archiveNote, 'A Luca');
  expect(vehicle.archivedKm, 184300);
  expect(vehicle.currentOdometerKm, 124500);

  // The values were copied as they were, into REAL columns: no km of any
  // row is still an integer on disk.
  for (final sql in [
    "SELECT COUNT(*) AS c FROM vehicles WHERE typeof(current_odometer_km) "
        "<> 'real'",
    "SELECT COUNT(*) AS c FROM vehicles WHERE archived_km IS NOT NULL AND "
        "typeof(archived_km) <> 'real'",
    "SELECT COUNT(*) AS c FROM mileage_readings WHERE typeof(km) <> 'real'",
    "SELECT COUNT(*) AS c FROM log_entries WHERE km IS NOT NULL AND "
        "typeof(km) <> 'real'",
  ]) {
    expect(await _count(db, sql), 0, reason: sql);
  }
  expect(
    await _count(db, 'SELECT COUNT(*) AS c FROM mileage_readings'),
    greaterThan(0),
  );
  for (final (table, column) in [
    ('vehicles', 'current_odometer_km'),
    ('vehicles', 'archived_km'),
    ('mileage_readings', 'km'),
    ('log_entries', 'km'),
  ]) {
    final columns = await db.customSelect('PRAGMA table_info($table)').get();
    expect(
      {
        for (final c in columns) c.read<String>('name'): c.read<String>('type'),
      },
      containsPair(column, 'REAL'),
      reason: '$table.$column',
    );
  }

  // The indexes of the three recreated tables are back.
  for (final (table, indexes) in [
    ('vehicles', ['vehicles_owner_id', 'vehicles_plate_live_unique']),
    ('log_entries', ['log_entries_vehicle_date', 'log_entries_vehicle_type']),
    ('mileage_readings', ['mileage_readings_vehicle_date']),
  ]) {
    final list = await db.customSelect('PRAGMA index_list($table)').get();
    expect(
      [for (final i in list) i.read<String>('name')],
      containsAll(indexes),
      reason: table,
    );
  }
  await _expectForeignKeysValid(db);
}

/// Checks the REAL km columns on an upgraded database: a reading typed in
/// miles (100 mi = 160.9344 km) is stored and read back exactly, the CHECK
/// constraints still refuse a negative km and the foreign keys still hold.
Future<void> _expectV9RealKmUsable(AppDatabase db) async {
  final reading = MileageReading(
    id: 'r-miles',
    vehicleId: 'v1',
    date: const CalendarDate(2026, 10, 28),
    km: 160.9344,
    createdAt: _tsUtc,
    updatedAt: _tsUtc,
  );
  await db.mileageReadingsDao.insertReading(reading);
  expect(await db.mileageReadingsDao.getLiveById('r-miles'), reading);
  final raw = await db
      .customSelect("SELECT km FROM mileage_readings WHERE id = 'r-miles'")
      .getSingle();
  expect(raw.read<double>('km'), 160.9344);
  await db.customStatement(
    "UPDATE vehicles SET current_odometer_km = 160.9344 WHERE id = 'v1'",
  );
  expect(
    (await db.vehiclesDao.getLiveById('v1'))!.currentOdometerKm,
    160.9344,
  );

  for (final sql in [
    "UPDATE mileage_readings SET km = -1 WHERE id = 'r-miles'",
    "UPDATE vehicles SET current_odometer_km = -0.5 WHERE id = 'v1'",
    "UPDATE vehicles SET archived_km = -1 WHERE id = 'v1'",
    'INSERT INTO log_entries (id, created_at, updated_at, vehicle_id, '
        "entry_date, km, type) VALUES ('e-bad', '$_ts', '$_ts', 'v1', "
        "'2026-10-28', -1, 'note')",
    'INSERT INTO mileage_readings (id, created_at, updated_at, vehicle_id, '
        "reading_date, km) VALUES ('r-bad', '$_ts', '$_ts', 'no-such-vehicle', "
        "'2026-10-28', 1.5)",
  ]) {
    await expectLater(
      db.customStatement(sql),
      throwsA(anything),
      reason: 'should be refused: $sql',
    );
  }
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
    await _expectInitialReadings(db, 4);
    await _expectDeletedAtBackfilled(db);
    // The soft-deleted owner and vehicle got their deletion instant.
    expect(await _countDeletedAt(db, 'owners'), 1);
    expect(await _countDeletedAt(db, 'vehicles'), 1);
    await _expectV3HistoryUsable(db, 'v1');
    await _expectV4ReadingsUsable(db, 'v1');
    await _expectV6SettingsUsable(db);
    await _expectV7AttachmentsUsable(db);
    await _expectV8ArchiveUsable(db);
    await _expectV9RealKmUsable(db);
  });

  test('rows written at v2 are intact at v3', () async {
    final db = await upgrade(2, 3, _insertV2Rows);
    await _expectV2RowsIntact(db);
    await _expectV3HistoryUsable(db, 'v1');
  });

  test('rows written at v2 are intact at v$latestVersion (chain)', () async {
    final db = await upgrade(2, latestVersion, _insertV2Rows);
    await _expectV2RowsIntact(db);
    await _expectInitialReadings(db, 12);
    await _expectDeletedAtBackfilled(db);
    expect(await _countDeletedAt(db, 'owners'), 1);
    expect(await _countDeletedAt(db, 'vehicles'), 1);
    await _expectV4ReadingsUsable(db, 'v1');
    await _expectV6SettingsUsable(db);
    await _expectV7AttachmentsUsable(db);
    await _expectV8ArchiveUsable(db);
    await _expectV9RealKmUsable(db);
  });

  test('rows written at v3 are intact at v4, each vehicle with one reading',
      () async {
    final db = await upgrade(3, 4, _insertV3Rows);
    await _expectV3RowsIntact(db);
    await _expectInitialReadings(db, 8);

    // Through the DAO: the live vehicle shows its one reading, the deleted
    // one shows nothing, but its reading is on disk for a future restore.
    final punto = await db.mileageReadingsDao.getLiveByVehicle('v1');
    expect([for (final r in punto) r.km], [123456]);
    expect(punto.single.createdAt, _tsUtc);
    expect(await db.mileageReadingsDao.getLiveByVehicle('v2'), isEmpty);
    expect(await db.mileageReadingsDao.countLive('v2'), 1);

    await _expectV4ReadingsUsable(db, 'v1');
  });

  test('rows written at v3 are intact at v$latestVersion (chain)', () async {
    final db = await upgrade(3, latestVersion, _insertV3Rows);
    await _expectV3RowsIntact(db);
    await _expectInitialReadings(db, 8);
    await _expectDeletedAtBackfilled(db);
    // The deleted owner, van and entry got their deletion instant.
    expect(await _countDeletedAt(db, 'owners'), 1);
    expect(await _countDeletedAt(db, 'vehicles'), 1);
    expect(await _countDeletedAt(db, 'log_entries'), 1);
    expect(await _countDeletedAt(db, 'mileage_readings'), 0);
    await _expectV6SettingsUsable(db);
    await _expectV7AttachmentsUsable(db);
    await _expectV8ArchiveUsable(db);
    await _expectV9RealKmUsable(db);
  });

  test('rows written at v4 are intact at v5, with deleted_at backfilled',
      () async {
    final db = await upgrade(4, 5, _insertV4Rows);
    await _expectV4RowsIntact(db);
    await _expectDeletedAtBackfilled(db);
  });

  test('rows written at v4 are intact at v$latestVersion (chain)', () async {
    final db = await upgrade(4, latestVersion, _insertV4Rows);
    await _expectV4RowsIntact(db);
    await _expectDeletedAtBackfilled(db);
    await _expectV6SettingsUsable(db);
    await _expectV7AttachmentsUsable(db);
    await _expectV8ArchiveUsable(db);
    await _expectV9RealKmUsable(db);
  });

  test('rows written at v5 are intact at v6, with an empty settings table',
      () async {
    final db = await upgrade(5, 6, _insertV5Rows);
    await _expectV5RowsIntact(db);
    await _expectV6SettingsUsable(db);
  });

  test('rows written at v5 are intact at v$latestVersion (chain)', () async {
    final db = await upgrade(5, latestVersion, _insertV5Rows);
    await _expectV5RowsIntact(db);
    await _expectV6SettingsUsable(db);
    await _expectV7AttachmentsUsable(db);
    await _expectV8ArchiveUsable(db);
    await _expectV9RealKmUsable(db);
  });

  test('rows written at v6 are intact at v7, with an empty attachments table',
      () async {
    final db = await upgrade(6, 7, _insertV6Rows);
    await _expectV6RowsIntact(db);
    await _expectV7AttachmentsUsable(db);
  });

  test('rows written at v6 are intact at v$latestVersion (chain)', () async {
    final db = await upgrade(6, latestVersion, _insertV6Rows);
    await _expectV6RowsIntact(db);
    await _expectV7AttachmentsUsable(db);
    await _expectV8ArchiveUsable(db);
    await _expectV9RealKmUsable(db);
  });

  test('rows written at v7 are intact at v8, every vehicle active', () async {
    final db = await upgrade(7, 8, _insertV7Rows);
    await _expectV7RowsIntact(db);
    await _expectV8ArchiveUsable(db);
  });

  test('rows written at v8 are intact at v9, every km copied as REAL',
      () async {
    final db = await upgrade(8, 9, _insertV8Rows);
    await _expectV8RowsIntact(db);
    await _expectV9RealKmUsable(db);
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
    // The REAL km columns of the latest version are in the copy of no older
    // file: `current_odometer_km` is still INTEGER there.
    final columns =
        await copy.customSelect('PRAGMA table_info(vehicles)').get();
    expect(
      {
        for (final c in columns) c.read<String>('name'): c.read<String>('type'),
      },
      containsPair('current_odometer_km', 'INTEGER'),
    );
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

  test('a real upgrade of a v3 file first copies it', () async {
    await realUpgrade(
      3,
      _insertV3Rows,
      (db) async {
        await _expectV3RowsIntact(db);
        await _expectInitialReadings(db, 8);
      },
      vehicleRows: 4,
    );
  });

  test('a real upgrade of a v4 file first copies it', () async {
    await realUpgrade(
      4,
      _insertV4Rows,
      (db) async {
        await _expectV4RowsIntact(db);
        await _expectDeletedAtBackfilled(db);
      },
      vehicleRows: 2,
    );
  });

  test('a real upgrade of a v5 file first copies it', () async {
    await realUpgrade(
      5,
      _insertV5Rows,
      (db) async {
        await _expectV5RowsIntact(db);
        await _expectV6SettingsUsable(db);
        await _expectV7AttachmentsUsable(db);
      },
      vehicleRows: 2,
    );
  });

  test('a real upgrade of a v6 file first copies it', () async {
    await realUpgrade(
      6,
      _insertV6Rows,
      (db) async {
        await _expectV6RowsIntact(db);
        await _expectV7AttachmentsUsable(db);
        await _expectV8ArchiveUsable(db);
        await _expectV9RealKmUsable(db);
      },
      vehicleRows: 2,
    );
  });

  test('a real upgrade of a v7 file first copies it', () async {
    await realUpgrade(
      7,
      _insertV7Rows,
      (db) async {
        await _expectV7RowsIntact(db);
        await _expectV8ArchiveUsable(db);
        await _expectV9RealKmUsable(db);
      },
      vehicleRows: 2,
    );
  });

  test('a real upgrade of a v8 file first copies it', () async {
    await realUpgrade(
      8,
      _insertV8Rows,
      (db) async {
        await _expectV8RowsIntact(db);
        await _expectV9RealKmUsable(db);
      },
      vehicleRows: 2,
    );
  });
}
