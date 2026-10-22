import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/attachment.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/trashed_vehicle.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/drift_attachment_repository.dart';
import 'package:vehicle_history/data/repositories/drift_log_entry_repository.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';
import 'package:vehicle_history/data/repositories/trash_cleanup_service.dart';

import 'test_support.dart';

/// The physical deletes of attachments (`Docs/02_data_model.md`): the
/// 30-day cleanup, the purge of a vehicle from the Trash and of an owner,
/// with their files; and the attachment counts of the Trash.
void main() {
  late AppDatabase db;
  late FakeClock clock;
  late MemoryAttachmentStore store;
  late DriftOwnerRepository owners;
  late DriftVehicleRepository vehicles;
  late DriftLogEntryRepository entries;
  late DriftAttachmentRepository attachments;
  late TrashCleanupService cleanup;
  late String ownerId;

  setUp(() async {
    db = openTestDatabase();
    clock = FakeClock(DateTime.utc(2026, 10, 19, 12));
    store = MemoryAttachmentStore();
    final writer = attachmentWriterOf(db, store);
    owners =
        DriftOwnerRepository(db.ownersDao, db.auditLogDao, clock: clock.call);
    vehicles = DriftVehicleRepository(
      db.vehiclesDao,
      db.mileageReadingsDao,
      db.trashDao,
      db.auditLogDao,
      attachmentFiles: store,
      clock: clock.call,
    );
    entries = DriftLogEntryRepository(
      db.logEntriesDao,
      db.auditLogDao,
      attachments: writer,
      clock: clock.call,
    );
    attachments =
        DriftAttachmentRepository(db.attachmentsDao, writer, clock: clock.call);
    cleanup = TrashCleanupService(db.trashDao, db.auditLogDao, store);
    ownerId = (await owners.create(firstName: 'Mario')).id;
  });

  tearDown(() => db.close());

  /// Creates a vehicle of Mario with the plate [plate].
  Future<String> createVehicle(String plate) async => (await vehicles.create(
        plate: plate,
        kind: VehicleKind.car,
        make: 'Fiat',
        model: 'Punto',
        ownerId: ownerId,
        currentOdometerKm: 1000,
        fuelType: FuelType.petrol,
      ))
          .id;

  /// Adds a note to [vehicleId] with [files] attachments.
  Future<String> addEntry(String vehicleId, {int files = 0}) async =>
      (await entries.create(
        vehicleId: vehicleId,
        date: CalendarDate.localDayOf(clock()),
        type: LogEntryType.note,
        attachments: [
          for (var i = 0; i < files; i++) await store.stageBytes([i]),
        ],
      ))
          .id;

  /// Attaches a file to [target].
  Future<Attachment> attach(AttachmentTarget target) async =>
      attachments.create(target, await store.stageBytes([1, 2]));

  /// Ids of every attachment row on disk, whatever its flag.
  Future<Set<String>> rowIds() async => {
        for (final row
            in await db.customSelect('SELECT id FROM attachments').get())
          row.read<String>('id'),
      };

  group('Trash counts', () {
    test('count the live attachments of the vehicle and of its live entries',
        () async {
      final punto = await createVehicle('AB123CD');
      final other = await createVehicle('ZZ999ZZ');
      await attach(AttachmentTarget.vehicle(punto));
      final deleted = await attach(AttachmentTarget.vehicle(punto));
      await attachments.delete(deleted.id);
      await addEntry(punto, files: 2);
      final gone = await addEntry(punto, files: 1);
      await entries.delete(gone);
      await attach(AttachmentTarget.vehicle(other));

      expect(
        await vehicles.countContents(punto),
        const VehicleContents(
          entryCount: 1,
          readingCount: 1,
          attachmentCount: 3,
        ),
      );

      await vehicles.delete(punto);
      final trashed = (await vehicles.watchTrashed().first).single;
      expect(trashed.contents.attachmentCount, 3);
    });
  });

  group('purge', () {
    test(
        "removes the files of the vehicle and of its entries, whatever "
        "their flags, and nobody else's", () async {
      final punto = await createVehicle('AB123CD');
      final other = await createVehicle('ZZ999ZZ');
      await attach(AttachmentTarget.vehicle(punto));
      final deletedOwn = await attach(AttachmentTarget.vehicle(punto));
      await attachments.delete(deletedOwn.id);
      await addEntry(punto, files: 1);
      final deletedEntry = await addEntry(punto, files: 1);
      await entries.delete(deletedEntry);
      final kept = await attach(AttachmentTarget.vehicle(other));
      final ownerFile = await attach(AttachmentTarget.owner(ownerId));
      expect(store.stored, hasLength(6));

      await vehicles.delete(punto);
      await vehicles.purge(punto);

      expect(await rowIds(), {kept.id, ownerFile.id});
      expect(
        store.stored.keys.toSet(),
        {kept.relativePath, ownerFile.relativePath},
      );
    });

    test('purgeAllTrashed removes the files of every trashed vehicle',
        () async {
      final a = await createVehicle('AA111AA');
      final b = await createVehicle('BB222BB');
      await attach(AttachmentTarget.vehicle(a));
      await addEntry(b, files: 2);
      await vehicles.delete(a);
      await vehicles.delete(b);

      await vehicles.purgeAllTrashed();
      expect(await rowIds(), isEmpty);
      expect(store.stored, isEmpty);
    });
  });

  group('30-day cleanup', () {
    test(
        'removes attachments deleted 30 days ago with their files, keeps '
        'younger ones and those travelling with a trashed vehicle', () async {
      final live = await createVehicle('AB123CD');
      final trashed = await createVehicle('ZZ999ZZ');
      final old = await attach(AttachmentTarget.vehicle(live));
      final oldOfTrashed = await attach(AttachmentTarget.vehicle(trashed));
      final entryOfTrashed = await addEntry(trashed, files: 1);
      final oldOfTrashedEntry = (await attachments.getByTarget(
        AttachmentTarget.logEntry(entryOfTrashed),
      ))
          .single;
      for (final a in [old, oldOfTrashed, oldOfTrashedEntry]) {
        await attachments.delete(a.id);
      }
      clock.advance(const Duration(days: 20));
      final young = await attach(AttachmentTarget.vehicle(live));
      await attachments.delete(young.id);
      // The vehicle went to the Trash 25 days after its files were deleted.
      clock.advance(const Duration(days: 5));
      await vehicles.delete(trashed);
      final liveFile = await attach(AttachmentTarget.vehicle(live));

      clock.advance(const Duration(days: 5));
      final report = await cleanup.runStartupCleanup(clock());

      expect(report.attachments, 1);
      expect(
        await rowIds(),
        {oldOfTrashed.id, oldOfTrashedEntry.id, young.id, liveFile.id},
      );
      expect(store.stored.containsKey(old.relativePath), isFalse);
      expect(store.stored, hasLength(4));
    });

    test(
        'an expired deleted entry and an expired deleted owner take their '
        'attachments with them', () async {
      final punto = await createVehicle('AB123CD');
      final entry = await addEntry(punto, files: 2);
      await entries.delete(entry);
      final ana = (await owners.create(firstName: 'Ana')).id;
      await attach(AttachmentTarget.owner(ana));
      await owners.delete(ana);
      final mine = await attach(AttachmentTarget.owner(ownerId));

      clock.advance(const Duration(days: 30));
      final report = await cleanup.runStartupCleanup(clock());

      expect((report.entries, report.owners), (1, 1));
      expect(await rowIds(), {mine.id});
      expect(store.stored.keys, [mine.relativePath]);
    });

    test('a vehicle purged by the cleanup takes all its files', () async {
      final punto = await createVehicle('AB123CD');
      await attach(AttachmentTarget.vehicle(punto));
      await addEntry(punto, files: 1);
      await vehicles.delete(punto);

      clock.advance(const Duration(days: 30));
      await cleanup.runStartupCleanup(clock());

      expect(await rowIds(), isEmpty);
      expect(store.stored, isEmpty);
    });

    test('a failed cleanup removes no file', () async {
      final punto = await createVehicle('AB123CD');
      final file = await attach(AttachmentTarget.vehicle(punto));
      await vehicles.delete(punto);
      await db.customStatement(
        'CREATE TEMP TRIGGER fail_vehicle_delete BEFORE DELETE ON vehicles '
        "BEGIN SELECT RAISE(ABORT, 'disk on fire'); END",
      );

      clock.advance(const Duration(days: 30));
      await expectLater(
        cleanup.runStartupCleanup(clock()),
        throwsA(anything),
      );
      expect(await rowIds(), {file.id});
      expect(store.stored.keys, [file.relativePath]);
    });
  });
}
