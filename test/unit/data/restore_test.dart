import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/audit_log_repository.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';
import 'package:vehicle_history/data/repositories/repository_exceptions.dart';

import 'test_support.dart';

/// `restore`, the repository side of "Undo" after a delete.
void main() {
  late AppDatabase db;
  late FakeClock clock;
  late DriftOwnerRepository owners;
  late DriftVehicleRepository vehicles;
  late DriftAuditLogRepository audit;

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
      attachmentFiles: MemoryAttachmentStore(),
      clock: clock.call,
    );
    audit = DriftAuditLogRepository(db.auditLogDao);
  });

  tearDown(() => db.close());

  Future<List<AuditOperation>> operationsOf(
    AuditEntityType type,
    String id,
  ) async =>
      [for (final e in await audit.getForEntity(type, id)) e.operation];

  group('owner restore', () {
    test('brings the owner back unchanged and audits a restore', () async {
      final owner = await owners.create(firstName: 'Mario', lastName: 'Rossi');
      clock.advance();
      await owners.delete(owner.id);
      clock.advance();

      final restored = await owners.restore(owner.id);

      expect(restored.firstName, 'Mario');
      expect(restored.lastName, 'Rossi');
      expect(restored.createdAt, owner.createdAt);
      expect(restored.updatedAt, clock());
      expect(await owners.getById(owner.id), restored);
      expect(
        await operationsOf(AuditEntityType.owner, owner.id),
        [AuditOperation.create, AuditOperation.delete, AuditOperation.restore],
      );
      final last =
          (await audit.getForEntity(AuditEntityType.owner, owner.id)).last;
      expect(last.at, clock());
    });

    test('refuses an owner that is live, writing nothing', () async {
      final owner = await owners.create(firstName: 'Mario');

      await expectLater(
        owners.restore(owner.id),
        throwsA(isA<EntityNotFoundException>()),
      );
      expect(
        await operationsOf(AuditEntityType.owner, owner.id),
        [AuditOperation.create],
      );
    });

    test('refuses an unknown id', () async {
      await expectLater(
        owners.restore('missing'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });

  group('vehicle restore', () {
    late String ownerId;

    setUp(() async {
      ownerId = (await owners.create(firstName: 'Mario')).id;
    });

    Future<String> createVehicle(String plate) async => (await vehicles.create(
          plate: plate,
          kind: VehicleKind.car,
          ownerId: ownerId,
          currentOdometerKm: 12345,
          fuelType: FuelType.diesel,
        ))
            .id;

    test('brings the vehicle back with its km and audits a restore', () async {
      final id = await createVehicle('AB123CD');
      clock.advance();
      await vehicles.delete(id);
      clock.advance();

      final restored = await vehicles.restore(id);

      expect(restored.plate, 'AB123CD');
      expect(restored.currentOdometerKm, 12345);
      expect(restored.updatedAt, clock());
      expect(await vehicles.getById(id), restored);
      expect(
        await operationsOf(AuditEntityType.vehicle, id),
        [AuditOperation.create, AuditOperation.delete, AuditOperation.restore],
      );
    });

    test('refuses when the plate was reused meanwhile, writing nothing',
        () async {
      final id = await createVehicle('AB123CD');
      await vehicles.delete(id);
      await createVehicle('ab123cd');

      await expectLater(
        vehicles.restore(id),
        throwsA(isA<DuplicatePlateException>()),
      );
      expect(await vehicles.getById(id), isNull);
      expect(
        await operationsOf(AuditEntityType.vehicle, id),
        [AuditOperation.create, AuditOperation.delete],
      );
    });

    test('refuses when the owner was deleted meanwhile', () async {
      final id = await createVehicle('AB123CD');
      await vehicles.delete(id);
      // The repository no longer deletes an owner with vehicles in the
      // Trash; an owner deleted that way before schema v5 is still possible.
      await db.ownersDao.softDeleteLive(ownerId, clock());

      await expectLater(
        vehicles.restore(id),
        throwsA(
          isA<EntityNotFoundException>().having(
            (e) => e.entityType,
            'entityType',
            AuditEntityType.owner,
          ),
        ),
      );
      expect(await vehicles.getById(id), isNull);
    });

    test('refuses a vehicle that is live', () async {
      final id = await createVehicle('AB123CD');

      await expectLater(
        vehicles.restore(id),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });
}
