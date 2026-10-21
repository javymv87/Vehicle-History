import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/db/daos/audit_log_dao.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/audit_log_repository.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';

import 'test_support.dart';

/// An audit DAO whose every write fails, to prove the entity write and its
/// audit row share one transaction.
class _FailingAuditLogDao extends AuditLogDao {
  _FailingAuditLogDao(super.db);

  @override
  Future<void> insertEntry(AuditEntry entry) async =>
      throw StateError('simulated audit failure');
}

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

  /// Operations recorded for one entity, oldest first.
  Future<List<AuditOperation>> operationsOf(
    AuditEntityType type,
    String id,
  ) async =>
      [for (final e in await audit.getForEntity(type, id)) e.operation];

  test('owner create, update and delete each add one audit row', () async {
    final owner = await owners.create(firstName: 'Mario');
    final createdAt = clock();
    clock.advance();
    await owners.update(owner.id, firstName: 'Luigi');
    clock.advance();
    await owners.delete(owner.id);

    final entries = await audit.getForEntity(AuditEntityType.owner, owner.id);
    expect(
      [for (final e in entries) e.operation],
      [AuditOperation.create, AuditOperation.update, AuditOperation.delete],
    );
    expect(entries.every((e) => e.entityId == owner.id), isTrue);
    expect(entries.first.at, createdAt);
    expect(entries.last.at, clock());
    expect(entries.every((e) => e.at.isUtc), isTrue);
  });

  test('vehicle create, update and delete each add one audit row', () async {
    final owner = await owners.create(firstName: 'Mario');
    final v = await vehicles.create(
      plate: 'AB123CD',
      kind: VehicleKind.car,
      ownerId: owner.id,
      currentOdometerKm: 0,
      fuelType: FuelType.diesel,
    );
    await vehicles.update(
      v.id,
      plate: 'AB123CD',
      kind: VehicleKind.car,
      ownerId: owner.id,
      fuelType: FuelType.petrol,
    );
    await vehicles.delete(v.id);

    expect(
      await operationsOf(AuditEntityType.vehicle, v.id),
      [AuditOperation.create, AuditOperation.update, AuditOperation.delete],
    );
    // The vehicle writes did not touch the owner's history.
    expect(
      await operationsOf(AuditEntityType.owner, owner.id),
      [AuditOperation.create],
    );
  });

  test('a refused write leaves no audit row', () async {
    final owner = await owners.create(firstName: 'Mario');
    await vehicles.create(
      plate: 'AB123CD',
      kind: VehicleKind.car,
      ownerId: owner.id,
      currentOdometerKm: 0,
      fuelType: FuelType.diesel,
    );
    final countBefore = await _auditRowCount(db);

    await expectLater(
      vehicles.create(
        plate: 'AB123CD',
        kind: VehicleKind.car,
        ownerId: owner.id,
        currentOdometerKm: 0,
        fuelType: FuelType.diesel,
      ),
      throwsA(anything),
    );
    expect(await _auditRowCount(db), countBefore);
  });

  test('a failing audit write rolls back the entity write', () async {
    final failingOwners = DriftOwnerRepository(
      db.ownersDao,
      _FailingAuditLogDao(db),
      clock: clock.call,
    );

    await expectLater(
      failingOwners.create(firstName: 'Mario'),
      throwsA(isA<StateError>()),
    );
    expect(await owners.getAll(), isEmpty);

    final owner = await owners.create(firstName: 'Luigi');
    await expectLater(
      failingOwners.update(owner.id, firstName: 'Changed'),
      throwsA(isA<StateError>()),
    );
    expect((await owners.getById(owner.id))!.firstName, 'Luigi');
  });
}

/// Total number of rows in `audit_log`.
Future<int> _auditRowCount(AppDatabase db) async {
  final row =
      await db.customSelect('SELECT COUNT(*) AS c FROM audit_log').getSingle();
  return row.read<int>('c');
}
