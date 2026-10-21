import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/data_providers.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/attachment.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/drift_attachment_repository.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';

import 'test_support.dart';

/// The cleanup wired into the app start (`databaseReadyProvider`).
void main() {
  late AppDatabase db;
  late String oldVehicle;
  late String recentVehicle;
  late MemoryAttachmentStore store;

  setUp(() async {
    db = openTestDatabase();
    store = MemoryAttachmentStore();
    final longAgo = FakeClock(DateTime.utc(2020, 1, 1, 12));
    final owners =
        DriftOwnerRepository(db.ownersDao, db.auditLogDao, clock: longAgo.call);
    final vehicles = DriftVehicleRepository(
      db.vehiclesDao,
      db.mileageReadingsDao,
      db.trashDao,
      db.auditLogDao,
      attachmentFiles: MemoryAttachmentStore(),
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
      attachmentFiles: MemoryAttachmentStore(),
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
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ...memoryFileOverrides(store),
      ],
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

  test(
      'the app start wipes the staging directory and deletes orphan files, '
      'keeping rows whose file is missing', () async {
    final attachments = DriftAttachmentRepository(
      db.attachmentsDao,
      attachmentWriterOf(db, store),
    );
    final owner =
        AttachmentTarget.owner((await db.ownersDao.getLive()).single.id);
    final kept = await attachments.create(
      owner,
      await store.stageBytes([1, 2, 3]),
    );
    final missing = await attachments.create(
      owner,
      await store.stageBytes([4]),
    );
    await store.delete(missing.relativePath);
    store.stored['attachments/orphan.jpg'] = Uint8List(4);
    await store.stageBytes([5], sessionId: 'left-over-form');

    await startApp();

    expect(store.stored.keys, [kept.relativePath]);
    expect(store.staged, isEmpty);
    // The row of the missing file is kept: the UI shows "File not found".
    expect(
      [
        for (final a in await attachments.getByTarget(owner)) a.id,
      ],
      [kept.id, missing.id],
    );
  });
}
