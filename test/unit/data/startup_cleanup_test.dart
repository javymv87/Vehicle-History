import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/data_providers.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';

import 'test_support.dart';

/// The cleanup wired into the app start (`databaseReadyProvider`).
void main() {
  late AppDatabase db;
  late String oldVehicle;
  late String recentVehicle;

  setUp(() async {
    db = openTestDatabase();
    final longAgo = FakeClock(DateTime.utc(2020, 1, 1, 12));
    final owners =
        DriftOwnerRepository(db.ownersDao, db.auditLogDao, clock: longAgo.call);
    final vehicles = DriftVehicleRepository(
      db.vehiclesDao,
      db.mileageReadingsDao,
      db.trashDao,
      db.auditLogDao,
      clock: longAgo.call,
    );
    final ownerId = (await owners.create(firstName: 'Mario')).id;
    Future<String> create(String plate) async => (await vehicles.create(
          plate: plate,
          kind: VehicleKind.car,
          ownerId: ownerId,
          currentOdometerKm: 0,
          fuelType: FuelType.petrol,
        ))
            .id;
    oldVehicle = await create('OLD1');
    await vehicles.delete(oldVehicle);
    // Deleted with the real clock: still in its 30 days.
    recentVehicle = await create('NEW1');
    await DriftVehicleRepository(
      db.vehiclesDao,
      db.mileageReadingsDao,
      db.trashDao,
      db.auditLogDao,
    ).delete(recentVehicle);
  });

  tearDown(() => db.close());

  /// Ids of every vehicle row on disk.
  Future<List<String>> vehicleIds() async => [
        for (final row
            in await db.customSelect('SELECT id FROM vehicles').get())
          row.read<String>('id'),
      ];

  /// Reads `databaseReadyProvider` on [db] (the database is never closed by
  /// the container: the test owns it).
  Future<void> startApp() async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await container.read(databaseReadyProvider.future);
  }

  test('the app start removes what expired and keeps the rest', () async {
    await startApp();
    expect(await vehicleIds(), [recentVehicle]);
  });

  test('a failing cleanup never stops the app start', () async {
    await db.customStatement(
      'CREATE TEMP TRIGGER fail_vehicle_delete BEFORE DELETE ON vehicles '
      "BEGIN SELECT RAISE(ABORT, 'disk on fire'); END",
    );

    await startApp();
    expect(await vehicleIds(), unorderedEquals([oldVehicle, recentVehicle]));
  });
}
