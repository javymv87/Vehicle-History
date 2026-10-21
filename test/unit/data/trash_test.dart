import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/owner.dart';
import 'package:vehicle_history/data/models/trashed_vehicle.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/drift_log_entry_repository.dart';
import 'package:vehicle_history/data/repositories/drift_mileage_reading_repository.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';
import 'package:vehicle_history/data/repositories/repository_exceptions.dart';
import 'package:vehicle_history/data/repositories/trash_cleanup_service.dart';

import 'test_support.dart';

/// The Trash (schema v5): `deleted_at`, the trashed list, restore, purge,
/// and the 30-day startup cleanup.
void main() {
  late AppDatabase db;
  late FakeClock clock;
  late DriftOwnerRepository owners;
  late DriftVehicleRepository vehicles;
  late DriftLogEntryRepository entries;
  late DriftMileageReadingRepository readings;
  late TrashCleanupService cleanup;
  late String ownerId;

  setUp(() async {
    db = openTestDatabase();
    // Noon UTC: the same local day in any timezone within ±11 hours.
    clock = FakeClock(DateTime.utc(2026, 10, 19, 12));
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
    entries = DriftLogEntryRepository(
      db.logEntriesDao,
      db.auditLogDao,
      attachments: attachmentWriterOf(db),
      clock: clock.call,
    );
    readings = DriftMileageReadingRepository(
      db.mileageReadingsDao,
      db.auditLogDao,
      clock: clock.call,
    );
    cleanup = TrashCleanupService(
        db.trashDao, db.auditLogDao, MemoryAttachmentStore());
    ownerId = (await owners.create(firstName: 'Mario')).id;
  });

  tearDown(() => db.close());

  /// Creates a vehicle of the owner [owner] (default: Mario).
  Future<String> createVehicle(String plate, {String? owner}) async =>
      (await vehicles.create(
        plate: plate,
        kind: VehicleKind.car,
        make: 'Fiat',
        model: 'Punto',
        ownerId: owner ?? ownerId,
        currentOdometerKm: 1000,
        fuelType: FuelType.petrol,
      ))
          .id;

  /// Adds a note dated today to the vehicle [vehicleId].
  Future<String> addEntry(String vehicleId) async => (await entries.create(
        vehicleId: vehicleId,
        date: CalendarDate.localDayOf(clock()),
        type: LogEntryType.note,
        description: 'Nota',
      ))
          .id;

  /// Adds a reading dated today with [km] to the vehicle [vehicleId].
  Future<String> addReading(String vehicleId, int km) async =>
      (await readings.create(
        vehicleId: vehicleId,
        date: CalendarDate.localDayOf(clock()),
        km: km,
      ))
          .id;

  /// `deleted` and `deleted_at` of the row [id] of [table], raw.
  Future<(bool, String?)> flags(String table, String id) async {
    final row = await db.customSelect(
      'SELECT deleted, deleted_at FROM $table WHERE id = ?',
      variables: [Variable(id)],
    ).getSingle();
    return (row.read<bool>('deleted'), row.read<String?>('deleted_at'));
  }

  /// Number of rows of [table], whatever their flags.
  Future<int> countRows(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
          .read<int>('c');

  /// Operations recorded for the entity [id] of [type], oldest first.
  Future<List<AuditOperation>> auditOf(AuditEntityType type, String id) async =>
      [
        for (final e in await db.auditLogDao.getForEntity(type, id))
          e.operation,
      ];

  group('deleted_at', () {
    test('is set by every delete and cleared by every restore', () async {
      final vehicleId = await createVehicle('AB123CD');
      final entryId = await addEntry(vehicleId);
      clock.advance();
      final readingId = await addReading(vehicleId, 1500);
      final spare = (await owners.create(firstName: 'Spare')).id;

      clock.advance(const Duration(hours: 1));
      final at = clock().toIso8601String();
      await entries.delete(entryId);
      await readings.deleteLast(readingId);
      await owners.delete(spare);
      await vehicles.delete(vehicleId);
      for (final (table, id) in [
        ('log_entries', entryId),
        ('mileage_readings', readingId),
        ('owners', spare),
        ('vehicles', vehicleId),
      ]) {
        expect(await flags(table, id), (true, at), reason: table);
      }

      await vehicles.restore(vehicleId);
      await owners.restore(spare);
      await readings.restore(readingId);
      await entries.restore(entryId);
      for (final (table, id) in [
        ('log_entries', entryId),
        ('mileage_readings', readingId),
        ('owners', spare),
        ('vehicles', vehicleId),
      ]) {
        expect(await flags(table, id), (false, null), reason: table);
      }
    });
  });

  group('countContents', () {
    test('counts the live entries and readings of a live vehicle', () async {
      final id = await createVehicle('AB123CD');
      await addEntry(id);
      final deleted = await addEntry(id);
      await entries.delete(deleted);
      await addReading(id, 2000);

      expect(
        await vehicles.countContents(id),
        const VehicleContents(entryCount: 1, readingCount: 2),
      );
    });

    test('refuses a deleted vehicle', () async {
      final id = await createVehicle('AB123CD');
      await vehicles.delete(id);
      await expectLater(
        vehicles.countContents(id),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });

  group('watchTrashed', () {
    test('lists deleted vehicles only, newest deletion first, with counts',
        () async {
      final live = await createVehicle('LIVE1');
      final first = await createVehicle('AA111AA');
      await addEntry(first);
      await addEntry(first);
      final gone = await addEntry(first);
      await entries.delete(gone);
      clock.advance();
      await addReading(first, 1200);
      final second = await createVehicle('BB222BB');

      clock.advance(const Duration(hours: 1));
      await vehicles.delete(first);
      final firstDeletedAt = clock();
      clock.advance(const Duration(hours: 1));
      await vehicles.delete(second);

      final trashed = await vehicles.watchTrashed().first;
      expect([for (final t in trashed) t.vehicle.id], [second, first]);
      expect(trashed.every((t) => t.vehicle.id != live), isTrue);
      final punto = trashed.last;
      expect(punto.deletedAt, firstDeletedAt);
      expect(punto.owner.id, ownerId);
      expect(punto.owner.firstName, 'Mario');
      expect(
        punto.contents,
        const VehicleContents(entryCount: 2, readingCount: 2),
      );
      expect(
        trashed.first.contents,
        const VehicleContents(entryCount: 0, readingCount: 1),
      );
    });

    test('emits again after a delete, a restore and a purge', () async {
      final id = await createVehicle('AB123CD');
      final emissions = <int>[];
      final sub =
          vehicles.watchTrashed().listen((list) => emissions.add(list.length));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await vehicles.delete(id);
      await pumpEventQueue();
      await vehicles.restore(id);
      await pumpEventQueue();
      await vehicles.delete(id);
      await pumpEventQueue();
      await vehicles.purge(id);
      await pumpEventQueue();
      expect(emissions, [0, 1, 0, 1, 0]);
    });
  });

  group('TrashedVehicle.daysUntilPurge', () {
    final deletedAt = DateTime.utc(2026, 10, 3, 9);
    final item = TrashedVehicle(
      vehicle: _placeholderVehicle,
      owner: _placeholderOwner,
      deletedAt: deletedAt,
      contents: const VehicleContents(entryCount: 0, readingCount: 1),
    );

    test('is 30 right after the delete and counts whole days up', () {
      expect(item.daysUntilPurge(deletedAt), 30);
      expect(item.daysUntilPurge(deletedAt.add(const Duration(hours: 1))), 30);
      expect(item.daysUntilPurge(deletedAt.add(const Duration(days: 3))), 27);
      expect(
        item.daysUntilPurge(deletedAt.add(const Duration(days: 29, hours: 23))),
        1,
      );
    });

    test('is 0, never negative, once the 30 days are over', () {
      expect(item.daysUntilPurge(deletedAt.add(trashRetention)), 0);
      expect(item.daysUntilPurge(deletedAt.add(const Duration(days: 40))), 0);
    });
  });

  group('restore from the Trash', () {
    test('brings back the vehicle with its entries and readings', () async {
      final id = await createVehicle('AB123CD');
      await addEntry(id);
      clock.advance();
      await addReading(id, 1500);
      await vehicles.delete(id);
      expect(await entries.watchByVehicle(id).first, isEmpty);

      await vehicles.restore(id);
      expect(await vehicles.getById(id), isNotNull);
      expect(await entries.watchByVehicle(id).first, hasLength(1));
      expect(await readings.getByVehicle(id), hasLength(2));
      expect(await vehicles.watchTrashed().first, isEmpty);
    });

    test('is refused when a live vehicle took the plate', () async {
      final id = await createVehicle('AB123CD');
      await vehicles.delete(id);
      await createVehicle('AB123CD');

      await expectLater(
        vehicles.restore(id),
        throwsA(isA<DuplicatePlateException>()),
      );
      expect(await vehicles.watchTrashed().first, hasLength(1));
    });

    test('is refused when the owner is no longer live', () async {
      final id = await createVehicle('AB123CD');
      await vehicles.delete(id);
      // Only reachable with an owner deleted before schema v5.
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
      expect(await vehicles.watchTrashed().first, hasLength(1));
    });
  });

  group('purge', () {
    test('removes the vehicle and all its children, and nothing else',
        () async {
      final keep = await createVehicle('KEEP1');
      final keptEntry = await addEntry(keep);
      final id = await createVehicle('AB123CD');
      await addEntry(id);
      final deletedEntry = await addEntry(id);
      await entries.delete(deletedEntry);
      clock.advance();
      final deletedReading = await addReading(id, 1500);
      await readings.deleteLast(deletedReading);
      await vehicles.delete(id);
      final auditBefore = await auditOf(AuditEntityType.vehicle, id);

      clock.advance();
      await vehicles.purge(id);

      final left = await db.customSelect('SELECT id FROM vehicles').get();
      expect([for (final r in left) r.read<String>('id')], [keep]);
      final leftEntries =
          await db.customSelect('SELECT id, vehicle_id FROM log_entries').get();
      expect([for (final r in leftEntries) r.read<String>('id')], [keptEntry]);
      final leftReadings = await db
          .customSelect('SELECT vehicle_id FROM mileage_readings')
          .get();
      expect(
        [for (final r in leftReadings) r.read<String>('vehicle_id')],
        [keep],
      );
      expect(await countRows('owners'), 1);

      // One `purge` row for the vehicle; its earlier rows stay, and the
      // children get none.
      expect(await auditOf(AuditEntityType.vehicle, id), [
        ...auditBefore,
        AuditOperation.purge,
      ]);
      expect(
        await auditOf(AuditEntityType.logEntry, deletedEntry),
        [AuditOperation.create, AuditOperation.delete],
      );
      final purgeRows = await db
          .customSelect("SELECT * FROM audit_log WHERE operation = 'purge'")
          .get();
      expect(purgeRows, hasLength(1));
    });

    test('refuses a live vehicle and a missing one', () async {
      final id = await createVehicle('AB123CD');
      await expectLater(
        vehicles.purge(id),
        throwsA(isA<EntityNotFoundException>()),
      );
      await expectLater(
        vehicles.purge('missing'),
        throwsA(isA<EntityNotFoundException>()),
      );
      expect(await vehicles.getById(id), isNotNull);
      expect(await countRows('mileage_readings'), 1);
    });

    test('purgeAllTrashed empties the Trash and keeps live vehicles', () async {
      final live = await createVehicle('LIVE1');
      await addEntry(live);
      final a = await createVehicle('AA111AA');
      await addEntry(a);
      final b = await createVehicle('BB222BB');
      await vehicles.delete(a);
      await vehicles.delete(b);

      expect(await vehicles.purgeAllTrashed(), 2);
      expect(await vehicles.watchTrashed().first, isEmpty);
      expect(await countRows('vehicles'), 1);
      expect(await countRows('log_entries'), 1);
      expect(await countRows('mileage_readings'), 1);
      expect(
        await auditOf(AuditEntityType.vehicle, a),
        contains(AuditOperation.purge),
      );
      expect(
        await auditOf(AuditEntityType.vehicle, b),
        contains(AuditOperation.purge),
      );
      expect(await vehicles.purgeAllTrashed(), 0);
    });
  });

  group('startup cleanup', () {
    test('removes a vehicle deleted exactly 30 days ago, not 29 days 23 h',
        () async {
      final old = await createVehicle('OLD1');
      await addEntry(old);
      await vehicles.delete(old);
      clock.advance(const Duration(hours: 1));
      final recent = await createVehicle('NEW1');
      await addEntry(recent);
      await vehicles.delete(recent);
      final oldDeletedAt = clock().subtract(const Duration(hours: 1));

      // 30 days after the first delete: 29 days 23 h after the second.
      final report =
          await cleanup.runStartupCleanup(oldDeletedAt.add(trashRetention));

      expect(report.vehicles, 1);
      final left = await db.customSelect('SELECT id FROM vehicles').get();
      expect([for (final r in left) r.read<String>('id')], [recent]);
      // The recent one keeps its entry and its reading.
      expect(await countRows('log_entries'), 1);
      expect(await countRows('mileage_readings'), 1);
      expect(
        (await auditOf(AuditEntityType.vehicle, old)).last,
        AuditOperation.purge,
      );
      expect(
        (await auditOf(AuditEntityType.vehicle, recent)).last,
        AuditOperation.delete,
      );
    });

    test('removes old deleted entries and readings of live vehicles only',
        () async {
      final live = await createVehicle('LIVE1');
      final keptEntry = await addEntry(live);
      final oldEntry = await addEntry(live);
      clock.advance();
      final oldReading = await addReading(live, 1500);
      await entries.delete(oldEntry);
      await readings.deleteLast(oldReading);
      final deletedAt = clock();

      // A trashed but recent vehicle with an old deleted entry and reading.
      final trashed = await createVehicle('TRASH1');
      final trashedEntry = await addEntry(trashed);
      clock.advance();
      final trashedReading = await addReading(trashed, 2000);
      await entries.delete(trashedEntry);
      await readings.deleteLast(trashedReading);
      clock.advance(const Duration(days: 25));
      await vehicles.delete(trashed);

      // A recently deleted entry of the live vehicle.
      final recentEntry = await addEntry(live);
      await entries.delete(recentEntry);

      final report =
          await cleanup.runStartupCleanup(deletedAt.add(trashRetention));

      expect(
        (report.vehicles, report.entries, report.readings, report.owners),
        (0, 1, 1, 0),
      );
      final leftEntries =
          await db.customSelect('SELECT id FROM log_entries').get();
      expect(
        [for (final r in leftEntries) r.read<String>('id')],
        unorderedEquals([keptEntry, trashedEntry, recentEntry]),
      );
      expect(await readings.getByVehicle(live), hasLength(1));
      expect(await db.mileageReadingsDao.getDeletedById(oldReading), isNull);
      expect(
        await db.mileageReadingsDao.getDeletedById(trashedReading),
        isNotNull,
      );
      // Entries and readings get no audit row of their own.
      expect(
        await auditOf(AuditEntityType.logEntry, oldEntry),
        [AuditOperation.create, AuditOperation.delete],
      );
    });

    test('removes an old deleted owner only when no vehicle row refers to it',
        () async {
      final free = (await owners.create(firstName: 'Libre')).id;
      await owners.delete(free);
      // An owner deleted before v5 while its vehicle was deleted too.
      final legacy = (await owners.create(firstName: 'Legacy')).id;
      final legacyVehicle = await createVehicle('LEG1', owner: legacy);
      clock.advance(const Duration(days: 20));
      await vehicles.delete(legacyVehicle);
      await db.ownersDao.softDeleteLive(legacy, clock());
      final legacyDeletedAt = clock();
      // An old deleted owner still referenced by a recent trashed vehicle.
      final held = (await owners.create(firstName: 'Held')).id;
      final heldVehicle = await createVehicle('HELD1', owner: held);
      clock.advance(const Duration(days: 15));
      await vehicles.delete(heldVehicle);
      await db.ownersDao.softDeleteLive(held, clock());
      // Back-date `held` so only its vehicle keeps it.
      await db.customStatement(
        "UPDATE owners SET deleted_at = '2000-01-01T00:00:00.000Z' "
        'WHERE id = ?',
        [held],
      );

      // 30 days after the legacy owner and vehicle were deleted.
      final report =
          await cleanup.runStartupCleanup(legacyDeletedAt.add(trashRetention));

      expect(report.owners, 2);
      expect(report.vehicles, 1);
      final left = await db.customSelect('SELECT id FROM owners').get();
      expect(
        [for (final r in left) r.read<String>('id')],
        unorderedEquals([ownerId, held]),
      );
      expect(
        (await auditOf(AuditEntityType.owner, free)).last,
        AuditOperation.purge,
      );
      expect(
        (await auditOf(AuditEntityType.owner, legacy)).last,
        AuditOperation.purge,
      );
      expect(
        (await auditOf(AuditEntityType.owner, held)).last,
        isNot(AuditOperation.purge),
      );
    });

    test('a failure rolls back everything and never stops the start', () async {
      final old = await createVehicle('OLD1');
      await addEntry(old);
      await vehicles.delete(old);
      final free = (await owners.create(firstName: 'Libre')).id;
      await owners.delete(free);
      final now = clock().add(const Duration(days: 31));
      // Make the last step (removing the owner) fail.
      await db.customStatement(
        'CREATE TEMP TRIGGER fail_owner_delete BEFORE DELETE ON owners '
        "BEGIN SELECT RAISE(ABORT, 'disk on fire'); END",
      );
      final rowsBefore = [
        for (final t in ['owners', 'vehicles', 'log_entries', 'audit_log'])
          await countRows(t),
      ];

      await expectLater(
        cleanup.runStartupCleanup(now),
        throwsA(anything),
      );
      expect(await runStartupCleanupSafely(cleanup, now), isNull);

      final rowsAfter = [
        for (final t in ['owners', 'vehicles', 'log_entries', 'audit_log'])
          await countRows(t),
      ];
      expect(rowsAfter, rowsBefore);
      expect(await vehicles.watchTrashed().first, hasLength(1));
    });

    test('is idempotent: a second run removes nothing more', () async {
      final old = await createVehicle('OLD1');
      await vehicles.delete(old);
      final now = clock().add(trashRetention);

      final first = await runStartupCleanupSafely(cleanup, now);
      expect(first?.vehicles, 1);
      final auditRows = await countRows('audit_log');

      final second = await cleanup.runStartupCleanup(now);
      expect(
        (second.vehicles, second.entries, second.readings, second.owners),
        (0, 0, 0, 0),
      );
      expect(await countRows('audit_log'), auditRows);
    });

    test('refuses a local-time instant', () async {
      await expectLater(
        cleanup.runStartupCleanup(DateTime(2026, 10, 19)),
        throwsArgumentError,
      );
    });
  });
}

/// Any vehicle: [TrashedVehicle.daysUntilPurge] only reads `deletedAt`.
final Vehicle _placeholderVehicle = Vehicle(
  id: 'v',
  plate: 'AB123CD',
  kind: VehicleKind.car,
  ownerId: 'o',
  currentOdometerKm: 0,
  fuelType: FuelType.petrol,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

/// Any owner, for the same reason.
final Owner _placeholderOwner = Owner(
  id: 'o',
  firstName: 'Mario',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
