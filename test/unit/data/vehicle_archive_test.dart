import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/archive_reason.dart';
import 'package:vehicle_history/data/models/attachment.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/trashed_vehicle.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/drift_attachment_repository.dart';
import 'package:vehicle_history/data/repositories/drift_log_entry_repository.dart';
import 'package:vehicle_history/data/repositories/drift_mileage_reading_repository.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';
import 'package:vehicle_history/data/repositories/repository_exceptions.dart';
import 'package:vehicle_history/data/repositories/trash_cleanup_service.dart';

import 'test_support.dart';

/// Archived vehicles (schema v8): `archive` with its final reading,
/// `reactivate`, the active / archived lists, the read-only guard of the
/// entries, readings and attachments, and what the guard must leave alone
/// (the archive transaction itself, the Trash purge and the cleanup).
void main() {
  late AppDatabase db;
  late FakeClock clock;
  late MemoryAttachmentStore store;
  late DriftOwnerRepository owners;
  late DriftVehicleRepository vehicles;
  late DriftLogEntryRepository entries;
  late DriftMileageReadingRepository readings;
  late DriftAttachmentRepository attachments;
  late TrashCleanupService cleanup;
  late String ownerId;

  setUp(() async {
    db = openTestDatabase();
    // Noon UTC: the same local day in any timezone within ±11 hours.
    clock = FakeClock(DateTime.utc(2026, 10, 19, 12));
    store = MemoryAttachmentStore();
    final writer = attachmentWriterOf(db, store);
    owners =
        DriftOwnerRepository(db.ownersDao, db.auditLogDao, clock: clock.call);
    readings = DriftMileageReadingRepository(
      db.mileageReadingsDao,
      db.auditLogDao,
      clock: clock.call,
    );
    vehicles = DriftVehicleRepository(
      db.vehiclesDao,
      db.mileageReadingsDao,
      db.trashDao,
      db.auditLogDao,
      readingRepository: readings,
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

  /// Today's local day of the fake clock.
  CalendarDate today() => CalendarDate.localDayOf(clock());

  /// Creates a vehicle of Mario with [km] as its initial reading.
  Future<Vehicle> createVehicle(String plate, {double km = 1000}) =>
      vehicles.create(
        plate: plate,
        kind: VehicleKind.car,
        make: 'Fiat',
        model: 'Punto',
        ownerId: ownerId,
        currentOdometerKm: km,
        fuelType: FuelType.petrol,
      );

  /// Archives [vehicle] today as sold, with [km] when given.
  Future<Vehicle> archive(Vehicle vehicle, {double? km, String? note}) =>
      vehicles.archive(
        vehicle.id,
        reason: ArchiveReason.sold,
        date: today(),
        km: km,
        note: note,
      );

  /// Stages a one-byte file named [name].
  Future<StagedFile> staged(String name) => store.stage(
        'test',
        content: Stream.value([1]),
        fileName: name,
        mimeType: 'image/jpeg',
      );

  /// Operations recorded for the entity [id] of [type], oldest first.
  Future<List<AuditOperation>> auditOf(AuditEntityType type, String id) async =>
      [
        for (final e in await db.auditLogDao.getForEntity(type, id))
          e.operation,
      ];

  group('archive', () {
    test('stores the snapshot and inserts the final reading on that day',
        () async {
      final punto = await createVehicle('AB123CD');
      clock.advance(const Duration(days: 1));
      final day = today();

      final archived = await archive(punto, km: 1500, note: ' A Luca ');

      expect(archived.isArchived, isTrue);
      expect(archived.archivedAt, day);
      expect(archived.archiveReason, ArchiveReason.sold);
      expect(archived.archiveNote, 'A Luca');
      expect(archived.archivedKm, 1500);
      expect(archived.currentOdometerKm, 1500);
      expect(archived.updatedAt, clock());
      expect(await vehicles.getById(punto.id), archived);
      // The reading went through the reading repository: last, audited.
      final list = await readings.getByVehicle(punto.id);
      expect(list, hasLength(2));
      expect(list.first.km, 1500);
      expect(list.first.date, day);
      expect(
        await auditOf(AuditEntityType.mileageReading, list.first.id),
        [AuditOperation.create],
      );
      expect(
        await auditOf(AuditEntityType.vehicle, punto.id),
        [AuditOperation.create, AuditOperation.archive],
      );
    });

    test('accepts km equal to the last reading and still inserts it', () async {
      final punto = await createVehicle('AB123CD', km: 1000);
      clock.advance(const Duration(days: 3));

      final archived = await archive(punto, km: 1000);

      expect(archived.archivedKm, 1000);
      final list = await readings.getByVehicle(punto.id);
      expect(list, hasLength(2));
      expect(list.first.date, today());
      expect(list.first.km, 1000);
    });

    test(
        'rejects km below the last reading with the reading error and '
        'writes nothing', () async {
      final punto = await createVehicle('AB123CD', km: 1000);

      await expectLater(
        archive(punto, km: 999),
        throwsA(
          isA<InvalidFieldException>().having(
            (e) => e.reason,
            'reason',
            InvalidFieldException.belowLastReading,
          ),
        ),
      );

      final kept = (await vehicles.getById(punto.id))!;
      expect(kept.isArchived, isFalse);
      expect(kept.archivedKm, isNull);
      expect(await readings.getByVehicle(punto.id), hasLength(1));
      expect(
        await auditOf(AuditEntityType.vehicle, punto.id),
        [AuditOperation.create],
      );
    });

    test('rejects a day before the last reading when km is given', () async {
      final punto = await createVehicle('AB123CD');
      final created = today();
      clock.advance(const Duration(days: 2));
      await readings.create(vehicleId: punto.id, date: today(), km: 1200);

      await expectLater(
        vehicles.archive(
          punto.id,
          reason: ArchiveReason.sold,
          date: created,
          km: 1300,
        ),
        throwsA(
          isA<InvalidFieldException>().having(
            (e) => e.reason,
            'reason',
            InvalidFieldException.beforeLastReading,
          ),
        ),
      );
      expect((await vehicles.getById(punto.id))!.isArchived, isFalse);
    });

    test('rejects a day after today, with or without km', () async {
      final punto = await createVehicle('AB123CD');
      final tomorrow = CalendarDate.localDayOf(
        clock().add(const Duration(days: 1)),
      );
      for (final km in <double?>[null, 2000]) {
        await expectLater(
          vehicles.archive(
            punto.id,
            reason: ArchiveReason.none,
            date: tomorrow,
            km: km,
          ),
          throwsA(
            isA<InvalidFieldException>().having(
              (e) => e.reason,
              'reason',
              InvalidFieldException.inFuture,
            ),
          ),
        );
      }
      expect((await vehicles.getById(punto.id))!.isArchived, isFalse);
    });

    test('without km inserts no reading and keeps the odometer', () async {
      final punto = await createVehicle('AB123CD', km: 1000);
      clock.advance(const Duration(days: 1));

      final archived = await archive(punto);

      expect(archived.archivedKm, isNull);
      expect(archived.currentOdometerKm, 1000);
      expect(await readings.getByVehicle(punto.id), hasLength(1));
    });

    test('refuses an archived, a deleted and a missing vehicle', () async {
      final punto = await createVehicle('AB123CD');
      await archive(punto);
      await expectLater(
        archive(punto),
        throwsA(isA<VehicleArchivedException>()),
      );
      final gone = await createVehicle('XY987ZW');
      await vehicles.delete(gone.id);
      await expectLater(
        archive(gone),
        throwsA(isA<EntityNotFoundException>()),
      );
      await expectLater(
        vehicles.archive('nope', reason: ArchiveReason.none, date: today()),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });

  group('reactivate', () {
    test('clears the four fields and keeps the readings', () async {
      final punto = await createVehicle('AB123CD');
      clock.advance(const Duration(days: 1));
      await archive(punto, km: 1500, note: 'Nota');
      clock.advance();

      final active = await vehicles.reactivate(punto.id);

      expect(active.isArchived, isFalse);
      expect(active.archivedAt, isNull);
      expect(active.archiveReason, isNull);
      expect(active.archiveNote, isNull);
      expect(active.archivedKm, isNull);
      expect(active.currentOdometerKm, 1500);
      expect(active.updatedAt, clock());
      expect(await vehicles.getById(punto.id), active);
      expect(await readings.getByVehicle(punto.id), hasLength(2));
      expect(
        await auditOf(AuditEntityType.vehicle, punto.id),
        [
          AuditOperation.create,
          AuditOperation.archive,
          AuditOperation.reactivate,
        ],
      );
      // Writable again.
      await readings.create(vehicleId: punto.id, date: today(), km: 1600);
    });

    test('refuses an active, a deleted and a missing vehicle', () async {
      final punto = await createVehicle('AB123CD');
      await expectLater(
        vehicles.reactivate(punto.id),
        throwsA(isA<InvalidFieldException>()),
      );
      await archive(punto);
      await vehicles.delete(punto.id);
      await expectLater(
        vehicles.reactivate(punto.id),
        throwsA(isA<EntityNotFoundException>()),
      );
      await expectLater(
        vehicles.reactivate('nope'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });

  group('lists', () {
    test('active excludes archived, archived excludes trashed', () async {
      final active = await createVehicle('AA111AA');
      final archived = await archive(await createVehicle('BB222BB'));
      final trashed = await archive(await createVehicle('CC333CC'));
      await vehicles.delete(trashed.id);

      expect(
        [for (final v in await vehicles.watchActive().first) v.plate],
        [active.plate],
      );
      expect(
        [for (final v in await vehicles.watchArchived().first) v.plate],
        [archived.plate],
      );
      // The owner's vehicles: both live ones.
      expect(
        [for (final v in await vehicles.getByOwner(ownerId)) v.plate],
        [active.plate, archived.plate],
      );
      expect(await vehicles.watchById(archived.id).first, archived);
      expect(await vehicles.watchById(trashed.id).first, isNull);
      // The Trash shows the archived vehicle like any other.
      expect(
        [for (final t in await vehicles.watchTrashed().first) t.vehicle.id],
        [trashed.id],
      );
    });

    test('archived are ordered by archive day, newest first, then plate',
        () async {
      final older = await createVehicle('ZZ999ZZ');
      final newerA = await createVehicle('BB222BB');
      final newerB = await createVehicle('AA111AA');
      await archive(older);
      clock.advance(const Duration(days: 1));
      await archive(newerA);
      await archive(newerB);

      expect(
        [for (final v in await vehicles.watchArchived().first) v.plate],
        ['AA111AA', 'BB222BB', 'ZZ999ZZ'],
      );
    });

    test('restore from the Trash lands in the right list', () async {
      final wasActive = await createVehicle('AA111AA');
      final wasArchived = await archive(await createVehicle('BB222BB'));
      await vehicles.delete(wasActive.id);
      await vehicles.delete(wasArchived.id);
      expect(await vehicles.watchArchived().first, isEmpty);

      await vehicles.restore(wasActive.id);
      await vehicles.restore(wasArchived.id);

      expect(
        [for (final v in await vehicles.watchActive().first) v.plate],
        ['AA111AA'],
      );
      final archivedList = await vehicles.watchArchived().first;
      expect([for (final v in archivedList) v.plate], ['BB222BB']);
      // The archive state survived the Trash.
      expect(archivedList.single.archiveReason, ArchiveReason.sold);
    });
  });

  group('read-only guard', () {
    late Vehicle punto;
    late String entryId;
    late String readingId;
    late Attachment document;
    late Attachment entryFile;

    setUp(() async {
      punto = await createVehicle('AB123CD');
      entryId = (await entries.create(
        vehicleId: punto.id,
        date: today(),
        type: LogEntryType.note,
        description: 'Nota',
      ))
          .id;
      // A later instant: readings of the same day sort by creation.
      clock.advance();
      readingId = (await readings.create(
        vehicleId: punto.id,
        date: today(),
        km: 1200,
      ))
          .id;
      document = await attachments.create(
        AttachmentTarget.vehicle(punto.id),
        await staged('Libretto.jpg'),
      );
      entryFile = await attachments.create(
        AttachmentTarget.logEntry(entryId),
        await staged('Scontrino.jpg'),
      );
      clock.advance(const Duration(days: 1));
      await archive(punto);
    });

    final archivedError = throwsA(isA<VehicleArchivedException>());

    test('the vehicle itself cannot be edited, only deleted and restored',
        () async {
      await expectLater(
        vehicles.update(
          punto.id,
          plate: 'NEW',
          kind: VehicleKind.car,
          ownerId: ownerId,
          fuelType: FuelType.petrol,
        ),
        archivedError,
      );
      await vehicles.delete(punto.id);
      final restored = await vehicles.restore(punto.id);
      expect(restored.isArchived, isTrue);
    });

    test('entries refuse create, update, delete and restore', () async {
      await expectLater(
        entries.create(
          vehicleId: punto.id,
          date: today(),
          type: LogEntryType.note,
        ),
        archivedError,
      );
      await expectLater(
        entries.update(entryId, date: today(), type: LogEntryType.note),
        archivedError,
      );
      await expectLater(entries.delete(entryId), archivedError);
      // Deleted while active, restored once archived: refused.
      await vehicles.reactivate(punto.id);
      await entries.delete(entryId);
      await archive(punto);
      await expectLater(entries.restore(entryId), archivedError);
      // Still readable.
      expect(await entries.watchByVehicle(punto.id).first, isEmpty);
    });

    test('readings refuse create, correct, delete and restore', () async {
      await expectLater(
        readings.create(vehicleId: punto.id, date: today(), km: 1300),
        archivedError,
      );
      await expectLater(readings.deleteLast(readingId), archivedError);
      await expectLater(
        readings.updateInitial(readingId, date: today(), km: 1),
        archivedError,
      );
      await vehicles.reactivate(punto.id);
      await readings.deleteLast(readingId);
      await archive(punto);
      await expectLater(readings.restore(readingId), archivedError);
      // Still readable, with the one reading left.
      expect(await readings.getByVehicle(punto.id), hasLength(1));
    });

    test('attachments of the vehicle and of its entries refuse every write',
        () async {
      for (final target in [
        AttachmentTarget.vehicle(punto.id),
        AttachmentTarget.logEntry(entryId),
      ]) {
        await expectLater(
          attachments.create(target, await staged('Altro.jpg')),
          archivedError,
        );
        await expectLater(attachments.reorder(target, const []), archivedError);
      }
      for (final attachment in [document, entryFile]) {
        await expectLater(
          attachments.updateCaption(attachment.id, 'x'),
          archivedError,
        );
        await expectLater(attachments.delete(attachment.id), archivedError);
      }
      await vehicles.reactivate(punto.id);
      await attachments.delete(document.id);
      await archive(punto);
      await expectLater(attachments.restore(document.id), archivedError);
      // Still readable: the entry file, and the owner stays writable.
      expect(
        await attachments.getByTarget(AttachmentTarget.logEntry(entryId)),
        [entryFile],
      );
      await attachments.create(
        AttachmentTarget.owner(ownerId),
        await staged('Patente.jpg'),
      );
    });

    test('does not stop the Trash purge of an archived vehicle', () async {
      await vehicles.delete(punto.id);

      await vehicles.purge(punto.id);

      expect(await vehicles.getById(punto.id), isNull);
      expect(await db.customSelect('SELECT id FROM vehicles').get(), isEmpty);
      expect(
        await db.customSelect('SELECT id FROM log_entries').get(),
        isEmpty,
      );
      expect(
        await db.customSelect('SELECT id FROM mileage_readings').get(),
        isEmpty,
      );
      expect(
        await db.customSelect('SELECT id FROM attachments').get(),
        isEmpty,
      );
      expect(store.stored, isEmpty);
      expect(
        (await auditOf(AuditEntityType.vehicle, punto.id)).last,
        AuditOperation.purge,
      );
    });

    test('does not stop the startup cleanup of an archived vehicle', () async {
      await vehicles.delete(punto.id);
      final deletedAt = clock();

      final report = await cleanup.runStartupCleanup(
        deletedAt.add(trashRetention),
      );

      expect(report.vehicles, 1);
      expect(await db.customSelect('SELECT id FROM vehicles').get(), isEmpty);
      expect(
        await db.customSelect('SELECT id FROM attachments').get(),
        isEmpty,
      );
    });
  });
}
