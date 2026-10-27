import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/attachments/attachment_store.dart';
import 'package:vehicle_history/data/backup/backup_exceptions.dart';
import 'package:vehicle_history/data/backup/backup_files.dart';
import 'package:vehicle_history/data/backup/backup_package.dart';
import 'package:vehicle_history/data/backup/backup_service.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/archive_reason.dart';
import 'package:vehicle_history/data/models/attachment.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/backup_manifest.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/setting_key.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/attachment_writer.dart';
import 'package:vehicle_history/data/repositories/drift_attachment_repository.dart';
import 'package:vehicle_history/data/repositories/drift_log_entry_repository.dart';
import 'package:vehicle_history/data/repositories/drift_mileage_reading_repository.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';

import '../../drift/vehicle_history/generated/schema.dart';
import 'test_support.dart';

/// The backup package on real files: export, validation, and the import
/// with its safety net (`Docs/05_sync_and_storage.md`).
void main() {
  late Directory dir;
  late String dbPath;
  late FakeClock clock;
  late AppDatabase db;

  /// Opens a new connection on the database file, as the app does.
  AppDatabase openFile({OnUpgrade? upgradeSteps}) {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    return AppDatabase.forExecutor(
      NativeDatabase(File(dbPath)),
      upgradeSteps: upgradeSteps,
    );
  }

  /// Path of [name] next to the database file.
  String pathOf(String name) => '${dir.path}${Platform.pathSeparator}$name';

  /// Free space the service is told about; `null` = unknown.
  int? freeBytes;

  /// The service on the live [db], opening new connections with [open].
  BackupService serviceOf({AppDatabase Function()? open}) => BackupService(
        database: db,
        openDatabase: open ?? openFile,
        appVersion: '9.9.9+99',
        freeBytes: (_) async => freeBytes,
        clock: clock.call,
      );

  /// The attachment files next to the database, as the app keeps them.
  AttachmentStore storeOf() => IoAttachmentStore(dir.path);

  /// The attachment repository on [database] and the real files.
  DriftAttachmentRepository attachmentsOf(AppDatabase database) =>
      DriftAttachmentRepository(
        database.attachmentsDao,
        AttachmentWriter(
          database.attachmentsDao,
          database.auditLogDao,
          storeOf(),
        ),
        clock: clock.call,
      );

  /// Adds a file named [name] with [bytes] to [target] on [database],
  /// through the staging directory as the app does.
  Future<Attachment> attach(
    AppDatabase database,
    AttachmentTarget target,
    String name,
    List<int> bytes,
  ) async {
    final staged = await storeOf().stage(
      'test',
      content: Stream.value(bytes),
      fileName: name,
      mimeType: mimeTypeForFileName(name),
    );
    return attachmentsOf(database).create(target, staged);
  }

  /// Exports a package, copies it to `package.zip` next to the database
  /// (as if saved and picked again), deletes the temporary one and returns
  /// the copy's path.
  Future<String> exportToFile() async {
    final exported = await serviceOf().exportPackage();
    final path = pathOf('package.zip');
    File(exported.path).copySync(path);
    await serviceOf().deleteExport(exported);
    return path;
  }

  /// Writes [bytes] to `candidate.zip` and returns its path.
  String fileOf(List<int> bytes) {
    final path = pathOf('candidate.zip');
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// The entries of the zip at [path], read whole (fine for test sizes).
  Archive zipAt(String path) =>
      ZipDecoder().decodeBytes(File(path).readAsBytesSync());

  /// The vehicle ids on disk with their `deleted` flag, sorted by plate.
  Future<List<String>> vehiclesOn(AppDatabase database) async => [
        for (final row in await database
            .customSelect('SELECT plate, deleted FROM vehicles ORDER BY plate')
            .get())
          '${row.read<String>('plate')}:${row.read<bool>('deleted')}',
      ];

  /// Writes the test data through the repositories at the current [clock]:
  /// owner Mario; AB123CD with two entries and a second reading; OLD1 in
  /// the Trash since now. Returns the id of OLD1.
  Future<String> seed(AppDatabase database) async {
    final owners = DriftOwnerRepository(
      database.ownersDao,
      database.auditLogDao,
      clock: clock.call,
    );
    final vehicles = DriftVehicleRepository(
      database.vehiclesDao,
      database.mileageReadingsDao,
      database.trashDao,
      database.auditLogDao,
      readingRepository: DriftMileageReadingRepository(
        database.mileageReadingsDao,
        database.auditLogDao,
        clock: clock.call,
      ),
      attachmentFiles: storeOf(),
      clock: clock.call,
    );
    final entries = DriftLogEntryRepository(
      database.logEntriesDao,
      database.auditLogDao,
      attachments: attachmentWriterOf(database, storeOf()),
      clock: clock.call,
    );
    final readings = DriftMileageReadingRepository(
      database.mileageReadingsDao,
      database.auditLogDao,
      clock: clock.call,
    );
    final ownerId = (await owners.create(firstName: 'Mario')).id;
    Future<String> vehicle(String plate) async => (await vehicles.create(
          plate: plate,
          kind: VehicleKind.car,
          make: 'Fiat',
          model: 'Punto',
          ownerId: ownerId,
          currentOdometerKm: 1000,
          fuelType: FuelType.petrol,
        ))
            .id;
    final punto = await vehicle('AB123CD');
    final today = CalendarDate.localDayOf(clock());
    for (final description in ['Tagliando', 'Nota']) {
      await entries.create(
        vehicleId: punto,
        date: today,
        type: LogEntryType.note,
        description: description,
      );
    }
    await readings.create(vehicleId: punto, date: today, km: 1500);
    final old = await vehicle('OLD1');
    await vehicles.delete(old);
    return old;
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vehicle_history_backup_');
    dbPath = pathOf('vehicle_history.sqlite');
    // Noon UTC: the same local day in any timezone within ±11 hours.
    clock = FakeClock(DateTime.utc(2026, 10, 1, 12));
    db = openFile();
    await db.open();
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  group('export', () {
    test('builds a package with the manifest, the database and attachments/',
        () async {
      await seed(db);
      clock.advance(const Duration(hours: 2));

      final exported = await serviceOf().exportPackage();

      final archive = zipAt(exported.path);
      expect(
        [for (final f in archive) f.name],
        unorderedEquals([
          manifestEntryName,
          databaseEntryName,
          attachmentsEntryName,
        ]),
      );
      expect(archive.find(attachmentsEntryName)!.isDirectory, isTrue);

      final manifest = BackupManifest.fromJson(
        jsonDecode(utf8.decode(archive.find(manifestEntryName)!.content)),
      );
      expect(manifest, exported.manifest);
      expect(manifest.formatVersion, 1);
      expect(manifest.schemaVersion, db.schemaVersion);
      expect(manifest.appVersion, '9.9.9+99');
      expect(manifest.exportedAt, DateTime.utc(2026, 10, 1, 14));
      // OLD1 is in the Trash: not counted, but in the copy.
      expect(
        manifest.counts,
        const BackupCounts(
          owners: 1,
          vehicles: 1,
          logEntries: 2,
          mileageReadings: 2,
        ),
      );
      expect(manifest.attachmentsBytes, 0);
      expect(manifest.lastModifiedAt, DateTime.utc(2026, 10, 1, 12));
      expect(
        exported.fileName,
        backupFileName(DateTime.utc(2026, 10, 1, 14).toLocal()),
      );
    });

    test(
        'the database copy is consistent and complete, Trash and audit log '
        'included', () async {
      await seed(db);
      final exported = await serviceOf().exportPackage();

      final copyPath = pathOf('copy.sqlite');
      File(copyPath).writeAsBytesSync(
        zipAt(exported.path).find(databaseEntryName)!.content,
      );
      final copy = AppDatabase.forExecutor(NativeDatabase(File(copyPath)));
      addTearDown(copy.close);
      final check = await copy.customSelect('PRAGMA integrity_check').get();
      expect(check.single.read<String>('integrity_check'), 'ok');
      expect(await vehiclesOn(copy), ['AB123CD:false', 'OLD1:true']);
      Future<int> count(AppDatabase d, String table) async =>
          (await d.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
              .read<int>('c');
      for (final table in [
        'owners',
        'vehicles',
        'log_entries',
        'mileage_readings',
        'audit_log',
      ]) {
        expect(await count(copy, table), await count(db, table), reason: table);
      }
    });

    test(
        'leaves only the package on disk, as a file, until it is deleted '
        'after the save', () async {
      await seed(db);
      final exported = await serviceOf().exportPackage();
      List<String> names() => [
            for (final f in dir.listSync()) f.uri.pathSegments.last,
          ];
      // The database copy is gone; the zip is a file, not bytes in memory.
      expect(names().where((n) => n.contains('export')), isEmpty);
      expect(names().where((n) => n.endsWith('.tmp')), [
        'vehicle_history.package.zip.tmp',
      ]);
      expect(File(exported.path).existsSync(), isTrue);

      await serviceOf().deleteExport(exported);
      expect(names().where((n) => n.endsWith('.tmp')), isEmpty);
    });

    test(
        'writes last_export_at before the copy, so the package carries its '
        'own export date', () async {
      await seed(db);
      clock.advance(const Duration(hours: 2));

      final exported = await serviceOf().exportPackage();

      const exportedAt = '2026-10-01T14:00:00.000Z';
      expect(exported.previousLastExportAt, isNull);
      expect(
        await db.settingsDao.readValue(SettingKey.lastExportAt),
        exportedAt,
      );
      final copyPath = pathOf('copy.sqlite');
      File(copyPath).writeAsBytesSync(
        zipAt(exported.path).find(databaseEntryName)!.content,
      );
      final copy = AppDatabase.forExecutor(NativeDatabase(File(copyPath)));
      addTearDown(copy.close);
      expect(
        await copy.settingsDao.readValue(SettingKey.lastExportAt),
        exportedAt,
      );
    });

    test('discarding an unsaved package puts the previous date back', () async {
      await serviceOf().exportPackage();
      clock.advance(const Duration(days: 1));
      final unsaved = await serviceOf().exportPackage();
      expect(unsaved.previousLastExportAt, '2026-10-01T12:00:00.000Z');

      await serviceOf().discardExport(unsaved);
      expect(
        await db.settingsDao.readValue(SettingKey.lastExportAt),
        '2026-10-01T12:00:00.000Z',
      );
    });

    test('discarding the first package leaves no export date', () async {
      await serviceOf().discardExport(await serviceOf().exportPackage());
      expect(await db.settingsDao.readValue(SettingKey.lastExportAt), isNull);
    });

    test('a failed export puts the previous date back and leaves no package',
        () async {
      await seed(db);
      final owner = (await db.ownersDao.getLive()).single;
      await attach(db, AttachmentTarget.owner(owner.id), 'id.jpg', [1, 2, 3]);
      final service = BackupService(
        database: db,
        openDatabase: openFile,
        appVersion: '9.9.9+99',
        files: _UnreadableFiles(),
        clock: clock.call,
      );

      await expectLater(
        service.exportPackage(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await db.settingsDao.readValue(SettingKey.lastExportAt), isNull);
      expect(
        dir.listSync().where((f) => f.path.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('an empty database has no last modification', () async {
      final exported = await serviceOf().exportPackage();
      expect(exported.manifest.lastModifiedAt, isNull);
      expect(
        exported.manifest.counts,
        const BackupCounts(
          owners: 0,
          vehicles: 0,
          logEntries: 0,
          mileageReadings: 0,
        ),
      );
    });
  });

  group('validation', () {
    late Uint8List validPackage;
    late BackupManifest validManifest;
    late Uint8List validDatabase;

    setUp(() async {
      await seed(db);
      final exported = await serviceOf().exportPackage();
      validPackage = File(exported.path).readAsBytesSync();
      await serviceOf().deleteExport(exported);
      validManifest = exported.manifest;
      validDatabase = ZipDecoder()
          .decodeBytes(validPackage)
          .find(databaseEntryName)!
          .content;
    });

    /// A zip with exactly [entries] (name → bytes).
    Uint8List zipOf(Map<String, List<int>> entries) {
      final archive = Archive();
      entries.forEach((name, bytes) {
        archive.add(ArchiveFile.bytes(name, bytes));
      });
      return ZipEncoder().encodeBytes(archive);
    }

    /// The manifest JSON of [validManifest] with [changes] applied.
    List<int> manifestWith(Map<String, Object?> changes) =>
        utf8.encode(jsonEncode({...validManifest.toJson(), ...changes}));

    /// [validDatabase] with the header `user_version` set to [version].
    Uint8List databaseAtVersion(int version) {
      final bytes = Uint8List.fromList(validDatabase);
      ByteData.sublistView(bytes).setUint32(60, version);
      return bytes;
    }

    /// Expects [bytes] to be rejected for [reason], with the data untouched.
    Future<void> expectRejected(Uint8List bytes, BackupRejection reason) async {
      await expectLater(
        serviceOf().inspectPackage(fileOf(bytes)),
        throwsA(
          isA<BackupRejectedException>()
              .having((e) => e.reason, 'reason', reason),
        ),
      );
      await expectLater(
        serviceOf().importPackage(fileOf(bytes)),
        throwsA(isA<BackupRejectedException>()),
      );
      // Still open, still the same data, no file left behind.
      expect(await vehiclesOn(db), ['AB123CD:false', 'OLD1:true']);
      expect(
        File(pathOf('vehicle_history.pre_import.sqlite')).existsSync(),
        isFalse,
      );
      expect(
        dir.listSync().where((f) => f.path.endsWith('.tmp')),
        isEmpty,
      );
    }

    test('accepts its own package and returns the manifest', () async {
      final preview = await serviceOf().inspectPackage(fileOf(validPackage));
      expect(preview.manifest, validManifest);
      expect(preview.attachmentCount, 0);
      expect(preview.missingFiles, 0);
    });

    test('rejects a file that is not a zip', () async {
      await expectRejected(
        Uint8List.fromList(utf8.encode('not a zip at all')),
        BackupRejection.notAZip,
      );
    });

    test('rejects a zip without manifest', () async {
      await expectRejected(
        zipOf({databaseEntryName: validDatabase}),
        BackupRejection.missingManifest,
      );
    });

    test('rejects a manifest that is not valid', () async {
      await expectRejected(
        zipOf({
          manifestEntryName: utf8.encode('{"format_version": 1'),
          databaseEntryName: validDatabase,
        }),
        BackupRejection.invalidManifest,
      );
      await expectRejected(
        zipOf({
          manifestEntryName: manifestWith({'counts': null}),
          databaseEntryName: validDatabase,
        }),
        BackupRejection.invalidManifest,
      );
    });

    test('rejects an unknown format_version', () async {
      await expectRejected(
        zipOf({
          manifestEntryName: manifestWith({'format_version': 0}),
          databaseEntryName: validDatabase,
        }),
        BackupRejection.invalidManifest,
      );
      await expectRejected(
        zipOf({
          manifestEntryName: manifestWith({'format_version': 2}),
          databaseEntryName: validDatabase,
        }),
        BackupRejection.newerFormat,
      );
    });

    test('rejects a package without database', () async {
      await expectRejected(
        zipOf({manifestEntryName: manifestWith({})}),
        BackupRejection.missingDatabase,
      );
    });

    test(
        'rejects a database entry that is not SQLite, or at another version '
        'than the manifest says', () async {
      await expectRejected(
        zipOf({
          manifestEntryName: manifestWith({}),
          databaseEntryName: utf8.encode('SQLite? No. ' * 20),
        }),
        BackupRejection.notADatabase,
      );
      await expectRejected(
        zipOf({
          manifestEntryName: manifestWith({}),
          databaseEntryName: databaseAtVersion(validManifest.schemaVersion - 1),
        }),
        BackupRejection.notADatabase,
      );
    });

    test('rejects a corrupt database', () async {
      final corrupt = Uint8List.fromList(validDatabase);
      // Keep the header page, overwrite every page after it.
      corrupt.fillRange(4096, corrupt.length, 0x55);
      await expectRejected(
        zipOf({
          manifestEntryName: manifestWith({}),
          databaseEntryName: corrupt,
        }),
        BackupRejection.corruptDatabase,
      );
    });

    test('rejects a database from a newer app', () async {
      final newer = validManifest.schemaVersion + 1;
      await expectRejected(
        zipOf({
          manifestEntryName: manifestWith({'schema_version': newer}),
          databaseEntryName: databaseAtVersion(newer),
        }),
        BackupRejection.newerSchema,
      );
    });

    test('rejects a database without the tables of its version', () async {
      final foreignPath = pathOf('foreign.sqlite');
      final foreign = NativeDatabase(File(foreignPath));
      await foreign.ensureOpen(const _PlainUser(5));
      await foreign.runCustom('CREATE TABLE owners (id TEXT PRIMARY KEY)');
      await foreign.runCustom('PRAGMA user_version = 5');
      await foreign.close();
      await expectRejected(
        zipOf({
          manifestEntryName: manifestWith({'schema_version': 5}),
          databaseEntryName: File(foreignPath).readAsBytesSync(),
        }),
        BackupRejection.missingTables,
      );
    });
  });

  group('import', () {
    test(
        'replaces every row, keeps the previous data in pre_import, audits '
        'the import and runs the startup cleanup', () async {
      final old = await seed(db);
      // The package is taken while OLD1 has been in the Trash for a day.
      clock.advance(const Duration(days: 1));
      final package = await exportToFile();

      // Then the data changes: a new owner and vehicle.
      final owners =
          DriftOwnerRepository(db.ownersDao, db.auditLogDao, clock: clock.call);
      await owners.create(firstName: 'Lucia');

      // The import happens 40 days after OLD1 went to the Trash.
      clock.advance(const Duration(days: 39));
      final manifest = await serviceOf().importPackage(package);
      expect(manifest.counts.vehicles, 1);

      final imported = openFile();
      addTearDown(imported.close);
      // The cleanup removed OLD1, now past the 30 days, and audited it.
      expect(await vehiclesOn(imported), ['AB123CD:false']);
      final purge =
          await imported.auditLogDao.getForEntity(AuditEntityType.vehicle, old);
      expect(purge.last.operation, AuditOperation.purge);
      // Lucia is gone: the data is the package's.
      expect(
        [for (final o in await imported.ownersDao.getLive()) o.firstName],
        ['Mario'],
      );
      // One import row, after the import, in the imported database.
      final audit = await imported.auditLogDao.getForEntity(
        AuditEntityType.database,
        AuditEntry.databaseEntityId,
      );
      expect(audit.single.operation, AuditOperation.import);
      expect(audit.single.at, clock());

      // The data from before the import, Lucia included, is in pre_import.
      final previous = AppDatabase.forExecutor(
        NativeDatabase(File(pathOf('vehicle_history.pre_import.sqlite'))),
      );
      addTearDown(previous.close);
      expect(
        [for (final o in await previous.ownersDao.getLive()) o.firstName],
        unorderedEquals(['Mario', 'Lucia']),
      );
      expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    });

    test('an archived vehicle round-trips with its four columns', () async {
      await seed(db);
      final punto = (await db.vehiclesDao.getActive()).single;
      clock.advance(const Duration(days: 1));
      final day = CalendarDate.localDayOf(clock());
      await DriftVehicleRepository(
        db.vehiclesDao,
        db.mileageReadingsDao,
        db.trashDao,
        db.auditLogDao,
        readingRepository: DriftMileageReadingRepository(
          db.mileageReadingsDao,
          db.auditLogDao,
          clock: clock.call,
        ),
        attachmentFiles: storeOf(),
        clock: clock.call,
      ).archive(
        punto.id,
        reason: ArchiveReason.leaseEnded,
        date: day,
        km: 2000,
        note: 'Fine leasing',
      );
      final package = await exportToFile();
      // The manifest counts the live vehicles, archived ones included (OLD1
      // is in the Trash).
      expect(
        (await serviceOf().inspectPackage(package)).manifest.counts.vehicles,
        1,
      );

      await serviceOf().importPackage(package);

      final imported = openFile();
      addTearDown(imported.close);
      expect(await imported.vehiclesDao.getActive(), isEmpty);
      final archived = (await imported.vehiclesDao.getLiveById(punto.id))!;
      expect(archived.archivedAt, day);
      expect(archived.archiveReason, ArchiveReason.leaseEnded);
      expect(archived.archiveNote, 'Fine leasing');
      expect(archived.archivedKm, 2000);
      expect(archived.currentOdometerKm, 2000);
      // The final reading travelled too.
      final readings =
          await imported.mileageReadingsDao.getLiveByVehicle(punto.id);
      expect(readings.first.km, 2000);
      expect(readings.first.date, day);
    });

    test('a step-9 (v7) package imports with every vehicle active', () async {
      final package = await _v7Package(pathOf('v7.sqlite'));

      final preview = await serviceOf().inspectPackage(package);
      expect(preview.manifest.schemaVersion, 7);
      await serviceOf().importPackage(package);

      final imported = openFile();
      addTearDown(imported.close);
      final vehicle = (await imported.vehiclesDao.getActive()).single;
      expect(vehicle.plate, 'AB123CD');
      expect(vehicle.isArchived, isFalse);
      expect(vehicle.archiveReason, isNull);
      expect(vehicle.archiveNote, isNull);
      expect(vehicle.archivedKm, isNull);
      expect(await imported.vehiclesDao.watchArchived().first, isEmpty);
    });

    test('a second import replaces the older pre_import copy', () async {
      await seed(db);
      final package = await exportToFile();
      await serviceOf().importPackage(package);

      db = openFile();
      await DriftOwnerRepository(
        db.ownersDao,
        db.auditLogDao,
        clock: clock.call,
      ).create(firstName: 'Lucia');
      await serviceOf().importPackage(package);

      final previous = AppDatabase.forExecutor(
        NativeDatabase(File(pathOf('vehicle_history.pre_import.sqlite'))),
      );
      addTearDown(previous.close);
      expect(
        [for (final o in await previous.ownersDao.getLive()) o.firstName],
        contains('Lucia'),
      );
    });

    test('an older schema is migrated, with its own pre-upgrade copy',
        () async {
      await seed(db);
      final package = await _v4Package(pathOf('v4.sqlite'));

      expect(
        (await serviceOf().inspectPackage(package)).manifest.schemaVersion,
        4,
      );
      await serviceOf().importPackage(package);

      final imported = openFile();
      addTearDown(imported.close);
      final version =
          await imported.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), imported.schemaVersion);
      final vehicle = (await imported.vehiclesDao.getActive()).single;
      expect((vehicle.plate, vehicle.make), ('ZZ999ZZ', 'Lancia'));
      expect(vehicle.currentOdometerKm, 54321);
      final readings = await imported.mileageReadingsDao.getLiveByVehicle('v1');
      expect([for (final r in readings) r.km], [54321]);
      expect(
        await imported.settingsDao.readValue(SettingKey.lastExportAt),
        isNull,
      );
      // runSafeUpgrade copied the imported v4 file before migrating it.
      expect(
        File(pathOf('vehicle_history.pre_v4.sqlite')).existsSync(),
        isTrue,
      );
    });

    test('a failed migration puts the previous data back', () async {
      await seed(db);
      final package = await _v4Package(pathOf('v4.sqlite'));
      var opened = 0;

      await expectLater(
        serviceOf(
          open: () => ++opened == 1
              ? openFile(
                  upgradeSteps: (m, from, to) async =>
                      throw StateError('broken migration'),
                )
              : openFile(),
        ).importPackage(package),
        throwsA(isA<BackupImportFailedException>()),
      );

      expect(opened, 2, reason: 'import, then the check of the restore');
      final restored = openFile();
      addTearDown(restored.close);
      expect(await vehiclesOn(restored), ['AB123CD:false', 'OLD1:true']);
      final version =
          await restored.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), restored.schemaVersion);
      expect(
        await restored.auditLogDao.getForEntity(
          AuditEntityType.database,
          AuditEntry.databaseEntityId,
        ),
        isEmpty,
      );
      // The safety copy stays, the temporary file does not.
      expect(
        File(pathOf('vehicle_history.pre_import.sqlite')).existsSync(),
        isTrue,
      );
      expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    });

    test(
        'a failure while opening the imported file puts the previous data '
        'back', () async {
      await seed(db);
      final package = await exportToFile();
      await DriftOwnerRepository(
        db.ownersDao,
        db.auditLogDao,
        clock: clock.call,
      ).create(firstName: 'Lucia');
      var opened = 0;

      await expectLater(
        serviceOf(
          open: () {
            if (++opened == 1) throw StateError('cannot open');
            return openFile();
          },
        ).importPackage(package),
        throwsA(isA<BackupImportFailedException>()),
      );

      final restored = openFile();
      addTearDown(restored.close);
      expect(
        [for (final o in await restored.ownersDao.getLive()) o.firstName],
        unorderedEquals(['Mario', 'Lucia']),
      );
    });

    test('if putting the data back fails too, the pre_import copy is kept',
        () async {
      await seed(db);
      final package = await exportToFile();

      await expectLater(
        serviceOf(open: () => throw StateError('disk gone')).importPackage(
          package,
        ),
        throwsA(isA<BackupRestoreFailedException>()),
      );
      expect(
        File(pathOf('vehicle_history.pre_import.sqlite')).existsSync(),
        isTrue,
      );
    });
  });

  group('Drive', () {
    test(
        'the Drive package does not touch last_export_at and carries the '
        'local state it was built from', () async {
      await seed(db);
      final service = serviceOf();
      final package = await service.buildDrivePackage();
      addTearDown(service.deleteDrivePackage);
      expect(await db.settingsDao.readValue(SettingKey.lastExportAt), isNull);
      expect(File(package.path).existsSync(), isTrue);
      expect(package.local.stamp, await db.backupDao.lastModifiedAt());
      expect(package.local.counts.vehicles, 1);
      expect(package.local.counts.logEntries, 2);
      expect(package.manifest.lastModifiedAt, package.local.stamp);
      await service.deleteDrivePackage();
      expect(File(package.path).existsSync(), isFalse);
      expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    });

    test('localSyncState counts the attachment rows, deleted ones included',
        () async {
      await seed(db);
      final state = await serviceOf().localSyncState();
      expect(state.counts.attachments, 0);
      expect(state.counts.owners, 1);
      expect(state.stamp, await db.backupDao.lastModifiedAt());
    });

    test(
        'an import keeps the phone\'s Drive link and clears the last common '
        'point, whatever the package carries', () async {
      await seed(db);
      // The package comes from a phone linked to another account, with its
      // own common point.
      final now = clock();
      Future<void> put(SettingKey key, String value) =>
          db.settingsDao.writeValue(key, value, now);
      await put(SettingKey.driveAccount, 'other@example.com');
      await put(SettingKey.driveDeviceId, 'other-phone');
      await put(SettingKey.driveSyncUploadId, 'their-upload');
      await put(SettingKey.driveSyncLocalStamp, 'their-stamp');
      await put(SettingKey.driveSyncAccount, 'other@example.com');
      await put(SettingKey.driveSyncAt, now.toIso8601String());
      await put(SettingKey.driveSyncDirection, 'upload');
      await put(SettingKey.language, 'it');
      final package = await exportToFile();

      // This phone: linked to me, its own device id, mobile data allowed,
      // a common point of its own.
      await put(SettingKey.driveAccount, 'me@example.com');
      await put(SettingKey.driveDeviceId, 'this-phone');
      await put(SettingKey.driveMobileData, 'true');
      await put(SettingKey.driveSyncUploadId, 'my-upload');
      await put(SettingKey.language, 'es');

      await serviceOf().importPackage(package);
      final imported = openFile();
      addTearDown(imported.close);
      final settings = imported.settingsDao;
      expect(
        await settings.readValue(SettingKey.driveAccount),
        'me@example.com',
      );
      expect(await settings.readValue(SettingKey.driveDeviceId), 'this-phone');
      expect(await settings.readValue(SettingKey.driveMobileData), 'true');
      for (final key in SettingKey.values) {
        if (key.scope == SettingScope.syncPoint) {
          expect(await settings.readValue(key), isNull, reason: key.code);
        }
      }
      // Preferences travel with the data.
      expect(await settings.readValue(SettingKey.language), 'it');
    });
  });

  group('attachments', () {
    late String ownerId;

    setUp(() async {
      await seed(db);
      ownerId = (await db.ownersDao.getLive()).single.id;
    });

    /// The files under `attachments/` (or [subdir]) with their bytes.
    Map<String, List<int>> filesIn([String subdir = 'attachments']) {
      final folder = Directory(pathOf(subdir));
      if (!folder.existsSync()) return {};
      return {
        for (final f in folder.listSync().whereType<File>())
          f.uri.pathSegments.last: f.readAsBytesSync(),
      };
    }

    test(
        'the package carries every attachment file, deleted ones included, '
        'with their count and size in the manifest', () async {
      final repository = attachmentsOf(db);
      final kept = await attach(
        db,
        AttachmentTarget.owner(ownerId),
        'Patente.jpg',
        [1, 2, 3],
      );
      final deleted = await attach(
        db,
        AttachmentTarget.owner(ownerId),
        'Vecchio.pdf',
        [4, 5],
      );
      await repository.delete(deleted.id);

      final exported = await serviceOf().exportPackage();
      final archive = zipAt(exported.path);

      expect(
        {
          for (final f in archive)
            if (isAttachmentEntryName(f.name)) f.name,
        },
        {kept.relativePath, deleted.relativePath},
      );
      expect(archive.find(kept.relativePath)!.content, [1, 2, 3]);
      expect(exported.manifest.counts.attachments, 2);
      expect(exported.manifest.attachmentsBytes, 5);
      final written = BackupManifest.fromJson(
        jsonDecode(utf8.decode(archive.find(manifestEntryName)!.content)),
      );
      expect(written, exported.manifest);
    });

    test(
        'a package of several megabytes is written to a file on disk, '
        'never returned as bytes', () async {
      const megabyte = 1024 * 1024;
      for (var i = 0; i < 3; i++) {
        await attach(
          db,
          AttachmentTarget.owner(ownerId),
          'Foto$i.jpg',
          List.filled(2 * megabyte, i),
        );
      }

      final exported = await serviceOf().exportPackage();

      // The service hands over a path: the zip is streamed file to file by
      // archive's file encoder; ExportedPackage has no bytes to hold.
      final file = File(exported.path);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(6 * megabyte));
      expect(exported.manifest.attachmentsBytes, 6 * megabyte);
      await serviceOf().deleteExport(exported);
      expect(file.existsSync(), isFalse);
    });

    test(
        'an import puts the package files in place, keeps the old ones in '
        'attachments.pre_import and brings back the old captions', () async {
      final photo = await attach(
        db,
        AttachmentTarget.owner(ownerId),
        'Patente.jpg',
        [1, 2, 3],
      );
      await attachmentsOf(db).updateCaption(photo.id, 'Fronte');
      final package = await exportToFile();

      // After the export: a new caption and a new file.
      await attachmentsOf(db).updateCaption(photo.id, 'Retro');
      final later = await attach(
        db,
        AttachmentTarget.owner(ownerId),
        'Nuovo.pdf',
        [9],
      );

      final preview = await serviceOf().inspectPackage(package);
      expect((preview.attachmentCount, preview.attachmentBytes), (1, 3));
      expect(preview.missingFiles, 0);
      await serviceOf().importPackage(package);

      final imported = openFile();
      addTearDown(imported.close);
      final rows = await imported.attachmentsDao
          .getLiveOf(AttachmentTarget.owner(ownerId));
      expect([
        for (final r in rows) (r.id, r.caption),
      ], [
        (photo.id, 'Fronte'),
      ]);
      expect(filesIn(), {
        photo.relativePath.split('/').last: [1, 2, 3],
      });
      expect(
        filesIn('attachments.pre_import').keys,
        unorderedEquals([
          photo.relativePath.split('/').last,
          later.relativePath.split('/').last,
        ]),
      );
      expect(
        dir.listSync().where((f) => f.path.endsWith('.tmp')),
        isEmpty,
      );
    });

    test(
        'a step-6 package, without attachments, still imports: no rows, an '
        'empty attachments directory', () async {
      await attach(db, AttachmentTarget.owner(ownerId), 'Patente.jpg', [1]);
      final package = await _v6Package(pathOf('v6.sqlite'));

      final preview = await serviceOf().inspectPackage(package);
      expect(preview.manifest.schemaVersion, 6);
      expect(preview.attachmentCount, 0);
      await serviceOf().importPackage(package);

      final imported = openFile();
      addTearDown(imported.close);
      expect((await imported.ownersDao.getLive()).single.firstName, 'Ana');
      expect(
        (await imported.customSelect('SELECT id FROM attachments').get()),
        isEmpty,
      );
      expect(filesIn(), isEmpty);
      expect(Directory(pathOf('attachments')).existsSync(), isTrue);
      expect(filesIn('attachments.pre_import'), hasLength(1));
    });

    test(
        'a file missing from the package is tolerated and reported; its row '
        'is imported', () async {
      final kept = await attach(
        db,
        AttachmentTarget.owner(ownerId),
        'Patente.jpg',
        [1],
      );
      final lost = await attach(
        db,
        AttachmentTarget.owner(ownerId),
        'Perso.jpg',
        [2],
      );
      File(storeOf().absolutePath(lost.relativePath)).deleteSync();
      final package = await exportToFile();

      final preview = await serviceOf().inspectPackage(package);
      expect(preview.missingFiles, 1);
      expect(preview.attachmentCount, 1);
      await serviceOf().importPackage(package);

      final imported = openFile();
      addTearDown(imported.close);
      final rows = await imported.attachmentsDao
          .getLiveOf(AttachmentTarget.owner(ownerId));
      expect({for (final r in rows) r.id}, {kept.id, lost.id});
      expect(filesIn().keys, [kept.relativePath.split('/').last]);
    });

    test(
        'a failed import puts back both the database and the attachments '
        'directory', () async {
      final before = await attach(
        db,
        AttachmentTarget.owner(ownerId),
        'Patente.jpg',
        [1],
      );
      final package = await _v6Package(pathOf('v6.sqlite'));
      final filesBefore = filesIn();
      var opened = 0;

      await expectLater(
        serviceOf(
          open: () {
            if (++opened == 1) throw StateError('cannot open');
            return openFile();
          },
        ).importPackage(package),
        throwsA(isA<BackupImportFailedException>()),
      );

      expect(filesIn(), filesBefore);
      final restored = openFile();
      addTearDown(restored.close);
      expect(
        [
          for (final r in await restored.attachmentsDao
              .getLiveOf(AttachmentTarget.owner(ownerId)))
            r.id,
        ],
        [before.id],
      );
      expect(Directory(pathOf('attachments.pre_import')).existsSync(), isFalse);
      expect(
        Directory(pathOf('attachments.import.tmp')).existsSync(),
        isFalse,
      );
    });

    test(
        'after a successful import the material of the import before is '
        'deleted', () async {
      await attach(db, AttachmentTarget.owner(ownerId), 'Patente.jpg', [1]);
      final package = await exportToFile();
      await serviceOf().importPackage(package);
      db = openFile();
      await attach(db, AttachmentTarget.owner(ownerId), 'Secondo.jpg', [2]);

      await serviceOf().importPackage(package);

      expect(
        File(pathOf('vehicle_history.pre_import.previous.sqlite')).existsSync(),
        isFalse,
      );
      expect(
        Directory(pathOf('attachments.pre_import.previous')).existsSync(),
        isFalse,
      );
      // The latest pre_import holds the data from just before this import.
      expect(filesIn('attachments.pre_import'), hasLength(2));
    });

    test('a phone without room for the package refuses it, touching nothing',
        () async {
      await attach(
        db,
        AttachmentTarget.owner(ownerId),
        'Patente.jpg',
        List.filled(1000, 1),
      );
      final package = await exportToFile();
      freeBytes = 1000;

      await expectLater(
        serviceOf().inspectPackage(package),
        throwsA(
          isA<BackupRejectedException>().having(
            (e) => e.reason,
            'reason',
            BackupRejection.notEnoughSpace,
          ),
        ),
      );
      await expectLater(
        serviceOf().importPackage(package),
        throwsA(isA<BackupRejectedException>()),
      );
      expect(await vehiclesOn(db), ['AB123CD:false', 'OLD1:true']);
      expect(filesIn(), hasLength(1));
    });
  });
}

/// Opens a raw file as it is, with no migration, to build foreign files.
class _PlainUser implements QueryExecutorUser {
  /// Creates the user for a file at [schemaVersion].
  const _PlainUser(this.schemaVersion);

  @override
  final int schemaVersion;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

/// Writes a v4 database with one owner, one vehicle and its initial reading
/// to [path], as the step-5 app left it, and returns the path of a package
/// holding it.
Future<String> _v4Package(String path) async {
  const ts = '2025-06-15T12:00:00.000Z';
  final file = File(path);
  final helper = GeneratedHelper();
  final old = helper.databaseForVersion(NativeDatabase(file), 4);
  await old.customStatement(
    'INSERT INTO owners (id, created_at, updated_at, deleted, first_name) '
    "VALUES ('o1', '$ts', '$ts', 0, 'Ana')",
  );
  await old.customStatement(
    'INSERT INTO vehicles (id, created_at, updated_at, deleted, plate, '
    'kind, make, model, owner_id, current_odometer_km, fuel_type) VALUES '
    "('v1', '$ts', '$ts', 0, 'ZZ999ZZ', 'car', 'Lancia', 'Ypsilon', 'o1', "
    "54321, 'petrol')",
  );
  await old.customStatement(
    'INSERT INTO mileage_readings (id, created_at, updated_at, deleted, '
    "vehicle_id, reading_date, km) VALUES ('r1', '$ts', '$ts', 0, 'v1', "
    "'2025-06-15', 54321)",
  );
  await old.close();
  final manifest = BackupManifest(
    formatVersion: 1,
    schemaVersion: 4,
    appVersion: '0.5.0+5',
    exportedAt: DateTime.parse(ts),
    counts: const BackupCounts(
      owners: 1,
      vehicles: 1,
      logEntries: 0,
      mileageReadings: 1,
    ),
    lastModifiedAt: DateTime.parse(ts),
  );
  final zip = '$path.zip';
  await writeBackupPackage(
    zip,
    manifest: manifest,
    databasePath: path,
    attachments: const {},
  );
  return zip;
}

/// File operations that fail to read, to make an export fail after the
/// database copy.
/// [BackupFiles] that cannot tell the size of an attachment file.
class _UnreadableFiles extends IoBackupFiles {
  @override
  Future<int> sizeOf(String path) async => path.contains('attachments')
      ? throw FileSystemException('unreadable', path)
      : super.sizeOf(path);
}

/// Writes a v7 database (step 8 / 9 app) with one owner, one vehicle and
/// its initial reading to [path] and returns the path of a package holding
/// it, with an empty `attachments/`: a package from before the archive
/// columns existed.
Future<String> _v7Package(String path) async {
  const ts = '2026-10-20T16:30:00.000Z';
  final old =
      GeneratedHelper().databaseForVersion(NativeDatabase(File(path)), 7);
  await old.customStatement(
    'INSERT INTO owners (id, created_at, updated_at, deleted, first_name) '
    "VALUES ('o1', '$ts', '$ts', 0, 'Ana')",
  );
  await old.customStatement(
    'INSERT INTO vehicles (id, created_at, updated_at, deleted, plate, kind, '
    'make, model, owner_id, current_odometer_km, fuel_type) VALUES '
    "('v1', '$ts', '$ts', 0, 'AB123CD', 'car', 'Fiat', 'Punto', 'o1', 1000, "
    "'petrol')",
  );
  await old.customStatement(
    'INSERT INTO mileage_readings (id, created_at, updated_at, deleted, '
    "vehicle_id, reading_date, km) VALUES ('r1', '$ts', '$ts', 0, 'v1', "
    "'2026-10-20', 1000)",
  );
  await old.close();
  final manifestJson = {
    'format_version': 1,
    'schema_version': 7,
    'app_version': '0.9.1+11',
    'exported_at': ts,
    'counts': {
      'owners': 1,
      'vehicles': 1,
      'log_entries': 0,
      'mileage_readings': 1,
      'attachments': 0,
    },
    'attachments_bytes': 0,
    'last_modified_at': ts,
  };
  final zip = '$path.zip';
  final encoder = ZipFileEncoder()..create(zip);
  encoder
    ..addArchiveFile(
      ArchiveFile.bytes(
        manifestEntryName,
        utf8.encode(jsonEncode(manifestJson)),
      ),
    )
    ..addArchiveFile(ArchiveFile.directory(attachmentsEntryName));
  await encoder.addFile(File(path), databaseEntryName);
  await encoder.close();
  return zip;
}

/// Writes a v6 database (step 6 / 7 app) with one owner and its settings to
/// [path] and returns the path of a package holding it, with an empty
/// `attachments/` and a manifest without the attachment keys.
Future<String> _v6Package(String path) async {
  const ts = '2026-10-20T16:30:00.000Z';
  final old =
      GeneratedHelper().databaseForVersion(NativeDatabase(File(path)), 6);
  await old.customStatement(
    'INSERT INTO owners (id, created_at, updated_at, deleted, first_name) '
    "VALUES ('o1', '$ts', '$ts', 0, 'Ana')",
  );
  await old.customStatement(
    'INSERT INTO settings (key, value, updated_at) VALUES '
    "('language', 'es', '$ts')",
  );
  await old.close();
  final manifestJson = {
    'format_version': 1,
    'schema_version': 6,
    'app_version': '0.7.0+7',
    'exported_at': ts,
    'counts': {
      'owners': 1,
      'vehicles': 0,
      'log_entries': 0,
      'mileage_readings': 0,
    },
    'last_modified_at': ts,
  };
  final zip = '$path.zip';
  final encoder = ZipFileEncoder()..create(zip);
  encoder
    ..addArchiveFile(
      ArchiveFile.bytes(
        manifestEntryName,
        utf8.encode(jsonEncode(manifestJson)),
      ),
    )
    ..addArchiveFile(ArchiveFile.directory(attachmentsEntryName));
  await encoder.addFile(File(path), databaseEntryName);
  await encoder.close();
  return zip;
}
