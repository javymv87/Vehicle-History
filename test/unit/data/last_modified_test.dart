import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/app_preferences.dart';
import 'package:vehicle_history/data/models/attachment.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/audit_log_repository.dart';
import 'package:vehicle_history/data/repositories/drift_attachment_repository.dart';
import 'package:vehicle_history/data/repositories/drift_log_entry_repository.dart';
import 'package:vehicle_history/data/repositories/drift_mileage_reading_repository.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';
import 'package:vehicle_history/data/repositories/settings_repository.dart';
import 'package:vehicle_history/data/repositories/trash_cleanup_service.dart';

import 'test_support.dart';

/// `BackupDao.lastModifiedAt`, the version stamp of the backup guard: it
/// moves forward with every change to what the user records, attachments
/// and physical deletions included, never with settings or imports, and
/// never goes backwards.
void main() {
  late AppDatabase db;
  late FakeClock clock;
  late MemoryAttachmentStore store;
  late DriftOwnerRepository owners;
  late DriftVehicleRepository vehicles;
  late DriftLogEntryRepository entries;
  late DriftMileageReadingRepository readings;
  late DriftAttachmentRepository attachments;
  late DriftSettingsRepository settings;
  late DriftAuditLogRepository audit;
  late TrashCleanupService cleanup;
  late String ownerId;
  late String vehicleId;

  setUp(() async {
    db = openTestDatabase();
    clock = FakeClock(DateTime.utc(2026, 10, 1, 12));
    store = MemoryAttachmentStore();
    final writer = attachmentWriterOf(db, store);
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
      attachmentFiles: store,
      clock: clock.call,
    );
    entries = DriftLogEntryRepository(
      db.logEntriesDao,
      db.auditLogDao,
      attachments: writer,
      clock: clock.call,
    );
    readings = DriftMileageReadingRepository(
      db.mileageReadingsDao,
      db.auditLogDao,
      clock: clock.call,
    );
    attachments =
        DriftAttachmentRepository(db.attachmentsDao, writer, clock: clock.call);
    settings = DriftSettingsRepository(db.settingsDao, clock: clock.call);
    audit = DriftAuditLogRepository(db.auditLogDao);
    cleanup = TrashCleanupService(db.trashDao, db.auditLogDao, store);
    ownerId = (await owners.create(firstName: 'Mario')).id;
    vehicleId = (await vehicles.create(
      plate: 'AB123CD',
      kind: VehicleKind.car,
      ownerId: ownerId,
      currentOdometerKm: 1000,
      fuelType: FuelType.petrol,
    ))
        .id;
    clock.advance();
  });

  tearDown(() => db.close());

  /// The value under test.
  Future<DateTime?> lastModified() => db.backupDao.lastModifiedAt();

  /// Adds a vehicle of Mario with [plate] and returns its id.
  Future<String> addVehicle(String plate) async => (await vehicles.create(
        plate: plate,
        kind: VehicleKind.car,
        ownerId: ownerId,
        currentOdometerKm: 1000,
        fuelType: FuelType.petrol,
      ))
          .id;

  /// Adds a note dated today to the vehicle and returns its id.
  Future<String> addEntry() async => (await entries.create(
        vehicleId: vehicleId,
        date: CalendarDate.localDayOf(clock()),
        type: LogEntryType.note,
        description: 'Tagliando',
      ))
          .id;

  /// Adds an attachment to Mario and returns it.
  Future<Attachment> addAttachment() async => attachments.create(
        AttachmentTarget.owner(ownerId),
        await store.stageBytes([1, 2, 3], fileName: 'Patente.jpg'),
      );

  /// Moves the clock past the 30 days of the Trash and runs the cleanup.
  Future<CleanupReport> cleanUpLater() async {
    clock.advance(const Duration(days: 31));
    return cleanup.runStartupCleanup(clock());
  }

  /// Whether [id] of [type] has a `purge` audit row.
  Future<bool> purgeAudited(AuditEntityType type, String id) async => [
        for (final e in await audit.getForEntity(type, id)) e.operation,
      ].contains(AuditOperation.purge);

  test('an empty database has no stamp', () async {
    final empty = openTestDatabase();
    addTearDown(empty.close);
    expect(await empty.backupDao.lastModifiedAt(), isNull);
  });

  group('attachments alone move it forward', () {
    test('adding, captioning, reordering, deleting and undoing', () async {
      final first = await addAttachment();
      expect(await lastModified(), clock());

      clock.advance();
      final second = await addAttachment();
      expect(await lastModified(), clock());

      clock.advance();
      await attachments.updateCaption(first.id, 'Fronte');
      expect(await lastModified(), clock());

      clock.advance();
      await attachments.reorder(
        AttachmentTarget.owner(ownerId),
        [second.id, first.id],
      );
      expect(await lastModified(), clock());

      clock.advance();
      await attachments.delete(first.id);
      expect(await lastModified(), clock());

      clock.advance();
      await attachments.restore(first.id);
      expect(await lastModified(), clock());

      clock.advance();
      await attachments.deleteMany([first.id, second.id]);
      expect(await lastModified(), clock());
    });
  });

  group('every physical deletion moves it forward', () {
    test('purging a vehicle from the Trash', () async {
      final spare = await addVehicle('ZZ999ZZ');
      await vehicles.delete(spare);
      clock.advance();
      await vehicles.purge(spare);
      expect(await lastModified(), clock());
      expect(await purgeAudited(AuditEntityType.vehicle, spare), isTrue);
    });

    test('emptying the Trash', () async {
      final spare = await addVehicle('ZZ999ZZ');
      await vehicles.delete(spare);
      clock.advance();
      expect(await vehicles.purgeAllTrashed(), 1);
      expect(await lastModified(), clock());
    });

    test('the cleanup of a vehicle 30 days in the Trash', () async {
      final spare = await addVehicle('ZZ999ZZ');
      await vehicles.delete(spare);
      final report = await cleanUpLater();
      expect(report.vehicles, 1);
      expect(await lastModified(), clock());
      expect(await purgeAudited(AuditEntityType.vehicle, spare), isTrue);
    });

    test('the cleanup of a deleted entry, with a purge row of its own',
        () async {
      final entry = await addEntry();
      await entries.delete(entry);
      final report = await cleanUpLater();
      expect(report.entries, 1);
      expect(await lastModified(), clock());
      expect(await purgeAudited(AuditEntityType.logEntry, entry), isTrue);
    });

    test('the cleanup of a deleted reading, with a purge row of its own',
        () async {
      final reading = await readings.create(
        vehicleId: vehicleId,
        date: CalendarDate.localDayOf(clock()),
        km: 2000,
      );
      await readings.deleteLast(reading.id);
      final report = await cleanUpLater();
      expect(report.readings, 1);
      expect(await lastModified(), clock());
      expect(
        await purgeAudited(AuditEntityType.mileageReading, reading.id),
        isTrue,
      );
    });

    test('the cleanup of a deleted owner', () async {
      final ana = (await owners.create(firstName: 'Ana')).id;
      await owners.delete(ana);
      final report = await cleanUpLater();
      expect(report.owners, 1);
      expect(await lastModified(), clock());
      expect(await purgeAudited(AuditEntityType.owner, ana), isTrue);
    });

    test('the cleanup of a deleted attachment, with a purge row of its own',
        () async {
      final photo = await addAttachment();
      await attachments.delete(photo.id);
      final report = await cleanUpLater();
      expect(report.attachments, 1);
      expect(await lastModified(), clock());
      expect(
        await purgeAudited(AuditEntityType.attachment, photo.id),
        isTrue,
      );
    });

    test(
        'the attachments that go with their entry get no row of their own: '
        "the entry's covers them", () async {
      final entry = (await entries.create(
        vehicleId: vehicleId,
        date: CalendarDate.localDayOf(clock()),
        type: LogEntryType.note,
        attachments: [
          await store.stageBytes([1], fileName: 'Fattura.pdf'),
        ],
      ))
          .id;
      final photo =
          (await attachments.getByTarget(AttachmentTarget.logEntry(entry)))
              .single;
      await entries.delete(entry);
      final report = await cleanUpLater();
      expect(report.entries, 1);
      expect(report.attachments, 0);
      expect(await purgeAudited(AuditEntityType.logEntry, entry), isTrue);
      expect(
        await purgeAudited(AuditEntityType.attachment, photo.id),
        isFalse,
      );
    });
  });

  test(
      'it never goes backwards: an entry deleted as the last change, then '
      'removed by the cleanup 31 days later', () async {
    final entry = await addEntry();
    clock.advance();
    await entries.delete(entry);
    final beforeCleanup = await lastModified();
    expect(beforeCleanup, clock());

    await cleanUpLater();
    final afterCleanup = await lastModified();
    expect(afterCleanup!.isBefore(beforeCleanup!), isFalse);
    expect(afterCleanup, clock());
  });

  test('settings and imports leave it where it is', () async {
    await addEntry();
    final stamp = await lastModified();

    clock.advance();
    await settings.writeLanguage(AppLanguage.italian);
    await settings.writeThemeMode(AppThemeMode.dark);
    await settings.writeLastExportAt(clock());
    expect(await lastModified(), stamp);

    // The audit row an import writes, later than anything else.
    clock.advance();
    await db.auditLogDao.insertEntry(
      AuditEntry(
        id: 'import-1',
        entityType: AuditEntityType.database,
        entityId: 'vehicle_history.sqlite',
        operation: AuditOperation.import,
        at: clock(),
      ),
    );
    expect(await lastModified(), stamp);
  });
}
