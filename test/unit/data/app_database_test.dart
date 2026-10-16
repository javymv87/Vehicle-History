import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';

import 'test_support.dart';

/// Inserts a vehicle row with raw SQL, bypassing every repository check.
Future<void> _rawInsertVehicle(
  AppDatabase db, {
  required String id,
  required String ownerId,
  String plate = 'AB123CD',
  int km = 0,
  int deleted = 0,
}) {
  return db.customStatement(
    'INSERT INTO vehicles (id, created_at, updated_at, deleted, plate, '
    'owner_id, current_odometer_km, fuel_type) '
    "VALUES (?, '2024-01-01T00:00:00.000Z', '2024-01-01T00:00:00.000Z', "
    "?, ?, ?, ?, 'petrol')",
    [id, deleted, plate, ownerId, km],
  );
}

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late DriftOwnerRepository owners;
  late DriftVehicleRepository vehicles;

  setUp(() {
    db = openTestDatabase();
    clock = FakeClock();
    owners =
        DriftOwnerRepository(db.ownersDao, db.auditLogDao, clock: clock.call);
    vehicles = DriftVehicleRepository(
      db.vehiclesDao,
      db.auditLogDao,
      clock: clock.call,
    );
  });

  tearDown(() => db.close());

  group('foreign keys', () {
    test('are enabled on the connection', () async {
      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(row.data.values.single, 1);
    });

    test('a raw insert with an unknown owner_id fails', () async {
      await expectLater(
        _rawInsertVehicle(db, id: 'v1', ownerId: 'no-such-owner'),
        throwsA(anything),
      );
    });

    test('a referenced owner row cannot be hard-deleted', () async {
      final owner = await owners.create(firstName: 'Mario');
      await _rawInsertVehicle(db, id: 'v1', ownerId: owner.id);
      await expectLater(
        db.customStatement('DELETE FROM owners WHERE id = ?', [owner.id]),
        throwsA(anything),
      );
    });
  });

  group('check constraints', () {
    test('current_odometer_km < 0 is refused by the database', () async {
      final owner = await owners.create(firstName: 'Mario');
      await expectLater(
        _rawInsertVehicle(db, id: 'v1', ownerId: owner.id, km: -1),
        throwsA(anything),
      );
    });

    test('a blank plate or first name is refused by the database', () async {
      final owner = await owners.create(firstName: 'Mario');
      await expectLater(
        _rawInsertVehicle(db, id: 'v1', ownerId: owner.id, plate: '  '),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'INSERT INTO owners (id, created_at, updated_at, first_name) '
          "VALUES ('o2', 'x', 'x', '   ')",
        ),
        throwsA(anything),
      );
    });
  });

  group('model_year check', () {
    /// Sets model_year of the raw vehicle `v1` to [year].
    Future<void> setYear(int? year) => db.customStatement(
          'UPDATE vehicles SET model_year = ? WHERE id = ?',
          [year, 'v1'],
        );

    test('accepts 1886 to 2100 and NULL', () async {
      final owner = await owners.create(firstName: 'Mario');
      await _rawInsertVehicle(db, id: 'v1', ownerId: owner.id);
      await setYear(1886);
      await setYear(2100);
      await setYear(null);
    });

    test('refuses a year outside 1886 to 2100', () async {
      final owner = await owners.create(firstName: 'Mario');
      await _rawInsertVehicle(db, id: 'v1', ownerId: owner.id);
      await expectLater(setYear(1885), throwsA(anything));
      await expectLater(setYear(2101), throwsA(anything));
    });
  });

  group('partial unique index on plate', () {
    test('two live vehicles cannot share a plate', () async {
      final owner = await owners.create(firstName: 'Mario');
      await _rawInsertVehicle(db, id: 'v1', ownerId: owner.id);
      await expectLater(
        _rawInsertVehicle(db, id: 'v2', ownerId: owner.id),
        throwsA(anything),
      );
    });

    test('a deleted vehicle does not block its plate', () async {
      final owner = await owners.create(firstName: 'Mario');
      await _rawInsertVehicle(db, id: 'v1', ownerId: owner.id, deleted: 1);
      await _rawInsertVehicle(db, id: 'v2', ownerId: owner.id);
    });
  });

  group('storage formats', () {
    test('timestamps are stored as UTC text and read back as UTC', () async {
      final owner = await owners.create(firstName: 'Mario');

      final raw = await db.customSelect(
        'SELECT created_at FROM owners WHERE id = ?',
        variables: [Variable.withString(owner.id)],
      ).getSingle();
      expect(raw.read<String>('created_at'), '2024-03-04T10:30:00.000Z');

      final read = (await owners.getById(owner.id))!;
      expect(read.createdAt.isUtc, isTrue);
      expect(read.createdAt, DateTime.utc(2024, 3, 4, 10, 30));
    });

    test('a birth date is stored as yyyy-MM-dd and round-trips', () async {
      const birthDate = CalendarDate(1980, 2, 29);
      final owner =
          await owners.create(firstName: 'Mario', birthDate: birthDate);

      final raw = await db.customSelect(
        'SELECT birth_date FROM owners WHERE id = ?',
        variables: [Variable.withString(owner.id)],
      ).getSingle();
      expect(raw.read<String>('birth_date'), '1980-02-29');
      expect((await owners.getById(owner.id))!.birthDate, birthDate);
    });

    test('fuel types are stored with their stable codes', () async {
      final owner = await owners.create(firstName: 'Mario');
      final v = await vehicles.create(
        plate: 'AB123CD',
        kind: VehicleKind.car,
        ownerId: owner.id,
        currentOdometerKm: 0,
        fuelType: FuelType.pluginHybrid,
      );
      final raw = await db.customSelect(
        'SELECT fuel_type FROM vehicles WHERE id = ?',
        variables: [Variable.withString(v.id)],
      ).getSingle();
      expect(raw.read<String>('fuel_type'), 'pluginHybrid');
    });
  });
}
