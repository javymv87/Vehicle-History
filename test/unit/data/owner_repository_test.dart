import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_mileage_reading_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';
import 'package:vehicle_history/data/repositories/repository_exceptions.dart';

import 'test_support.dart';

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
      db.mileageReadingsDao,
      db.trashDao,
      db.auditLogDao,
      readingRepository: DriftMileageReadingRepository(
        db.mileageReadingsDao,
        db.auditLogDao,
        clock: clock.call,
      ),
      attachmentFiles: MemoryAttachmentStore(),
      clock: clock.call,
    );
  });

  tearDown(() => db.close());

  group('create', () {
    test('sets id and timestamps, and trims the text fields', () async {
      final owner = await owners.create(
        firstName: '  Mario ',
        lastName: ' Rossi ',
        birthDate: const CalendarDate(1980, 2, 29),
        email: ' mario@example.com ',
        phone: '   ',
      );

      expect(owner.id, hasLength(36));
      expect(owner.firstName, 'Mario');
      expect(owner.lastName, 'Rossi');
      expect(owner.email, 'mario@example.com');
      expect(owner.phone, isNull, reason: 'blank optional text is null');
      expect(owner.createdAt, clock());
      expect(owner.updatedAt, clock());
      expect(await owners.getById(owner.id), owner);
    });

    test('refuses a blank first name and writes nothing', () async {
      await expectLater(
        owners.create(firstName: '   '),
        throwsA(isA<InvalidFieldException>()),
      );
      expect(await owners.getAll(), isEmpty);
    });

    test('generates a different id each time', () async {
      final a = await owners.create(firstName: 'Anna');
      final b = await owners.create(firstName: 'Anna');
      expect(a.id, isNot(b.id));
    });
  });

  group('update', () {
    test('replaces editable fields and bumps updatedAt only', () async {
      final created = await owners.create(firstName: 'Mario', notes: 'x');
      clock.advance();

      final updated = await owners.update(
        created.id,
        firstName: 'Mario',
        lastName: 'Bianchi',
      );

      expect(updated.lastName, 'Bianchi');
      expect(updated.notes, isNull, reason: 'omitted field is cleared');
      expect(updated.createdAt, created.createdAt);
      expect(updated.updatedAt, clock());
      expect(await owners.getById(created.id), updated);
    });

    test('a missing id throws EntityNotFoundException', () async {
      await expectLater(
        owners.update('missing', firstName: 'X'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('a deleted owner throws EntityNotFoundException', () async {
      final owner = await owners.create(firstName: 'Mario');
      await owners.delete(owner.id);
      await expectLater(
        owners.update(owner.id, firstName: 'Luigi'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });

  group('delete', () {
    test('is soft: the row stays on disk but is hidden from reads', () async {
      final owner = await owners.create(firstName: 'Mario');
      await owners.delete(owner.id);

      expect(await owners.getById(owner.id), isNull);
      expect(await owners.getAll(), isEmpty);
      final raw = await db.customSelect(
        'SELECT deleted FROM owners WHERE id = ?',
        variables: [Variable.withString(owner.id)],
      ).getSingle();
      expect(raw.read<int>('deleted'), 1);
    });

    test('deleting twice throws EntityNotFoundException', () async {
      final owner = await owners.create(firstName: 'Mario');
      await owners.delete(owner.id);
      await expectLater(
        owners.delete(owner.id),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('is refused while the owner has live vehicles; nothing is written',
        () async {
      final owner = await owners.create(firstName: 'Mario');
      await vehicles.create(
        plate: 'AB123CD',
        kind: VehicleKind.car,
        ownerId: owner.id,
        currentOdometerKm: 1000,
        fuelType: FuelType.petrol,
      );
      final auditBefore =
          await db.auditLogDao.getForEntity(AuditEntityType.owner, owner.id);

      await expectLater(
        owners.delete(owner.id),
        throwsA(
          isA<OwnerHasVehiclesException>()
              .having((e) => e.vehicleCount, 'vehicleCount', 1),
        ),
      );

      expect(await owners.getById(owner.id), isNotNull);
      expect(
        await db.auditLogDao.getForEntity(AuditEntityType.owner, owner.id),
        auditBefore,
      );
    });

    test('is allowed once the owner\'s vehicles are purged', () async {
      final owner = await owners.create(firstName: 'Mario');
      final vehicle = await vehicles.create(
        plate: 'AB123CD',
        kind: VehicleKind.car,
        ownerId: owner.id,
        currentOdometerKm: 1000,
        fuelType: FuelType.petrol,
      );
      await vehicles.delete(vehicle.id);
      await vehicles.purge(vehicle.id);

      await owners.delete(owner.id);
      expect(await owners.getById(owner.id), isNull);
    });

    test('is refused while a vehicle of the owner is in the Trash', () async {
      final owner = await owners.create(firstName: 'Mario');
      final vehicle = await vehicles.create(
        plate: 'AB123CD',
        kind: VehicleKind.car,
        ownerId: owner.id,
        currentOdometerKm: 1000,
        fuelType: FuelType.petrol,
      );
      await vehicles.delete(vehicle.id);

      await expectLater(
        owners.delete(owner.id),
        throwsA(
          isA<OwnerHasTrashedVehiclesException>()
              .having((e) => e.ownerId, 'ownerId', owner.id)
              .having((e) => e.vehicleCount, 'vehicleCount', 1),
        ),
      );
      expect(await owners.getById(owner.id), isNotNull);
      final audit =
          await db.auditLogDao.getForEntity(AuditEntityType.owner, owner.id);
      expect([for (final e in audit) e.operation], [AuditOperation.create]);
    });
  });

  group('reads', () {
    test('getAll is ordered by first name, then last name', () async {
      await owners.create(firstName: 'Zoe');
      await owners.create(firstName: 'Anna', lastName: 'Verdi');
      await owners.create(firstName: 'Anna', lastName: 'Bianchi');

      final names = [
        for (final o in await owners.getAll()) '${o.firstName} ${o.lastName}',
      ];
      expect(names, ['Anna Bianchi', 'Anna Verdi', 'Zoe null']);
    });

    test('watchAll emits on create, update and delete', () async {
      final emissions =
          owners.watchAll().map((list) => [for (final o in list) o.firstName]);
      final expectation = expectLater(
        emissions,
        emitsInOrder([
          <String>[],
          ['Mario'],
          ['Luigi'],
          <String>[],
        ]),
      );

      // Let the initial empty list arrive before writing.
      await pumpEventQueue();
      final owner = await owners.create(firstName: 'Mario');
      await pumpEventQueue();
      await owners.update(owner.id, firstName: 'Luigi');
      await pumpEventQueue();
      await owners.delete(owner.id);

      await expectation;
    });
  });
}
