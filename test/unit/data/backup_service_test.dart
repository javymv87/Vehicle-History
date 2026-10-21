import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/backup/backup_exceptions.dart';
import 'package:vehicle_history/data/backup/backup_files.dart';
import 'package:vehicle_history/data/backup/backup_package.dart';
import 'package:vehicle_history/data/backup/backup_service.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/backup_manifest.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/setting_key.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
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

  /// The service on the live [db], opening new connections with [open].
  BackupService serviceOf({AppDatabase Function()? open}) => BackupService(
        database: db,
        openDatabase: open ?? openFile,
        appVersion: '9.9.9+99',
        clock: clock.call,
      );

  /// Path of [name] next to the database file.
  String pathOf(String name) => '${dir.path}${Platform.pathSeparator}$name';

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
      clock: clock.call,
    );
    final entries = DriftLogEntryRepository(
      database.logEntriesDao,
      database.auditLogDao,
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

      final archive = ZipDecoder().decodeBytes(exported.bytes);
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
        ZipDecoder()
            .decodeBytes(exported.bytes)
            .find(databaseEntryName)!
            .content,
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

    test('leaves no temporary file behind', () async {
      await seed(db);
      await serviceOf().exportPackage();
      final names = [
        for (final f in dir.listSync()) f.uri.pathSegments.last,
      ];
      expect(names.where((n) => n.contains('.tmp')), isEmpty);
      expect(names.where((n) => n.contains('export')), isEmpty);
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
        ZipDecoder()
            .decodeBytes(exported.bytes)
            .find(databaseEntryName)!
            .content,
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

    test('a failed export puts the previous date back', () async {
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
      validPackage = exported.bytes;
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
        serviceOf().inspectPackage(bytes),
        throwsA(
          isA<BackupRejectedException>()
              .having((e) => e.reason, 'reason', reason),
        ),
      );
      await expectLater(
        serviceOf().importPackage(bytes),
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
      expect(await serviceOf().inspectPackage(validPackage), validManifest);
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
      final package = (await serviceOf().exportPackage()).bytes;

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

    test('a second import replaces the older pre_import copy', () async {
      await seed(db);
      final package = (await serviceOf().exportPackage()).bytes;
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

      expect((await serviceOf().inspectPackage(package)).schemaVersion, 4);
      await serviceOf().importPackage(package);

      final imported = openFile();
      addTearDown(imported.close);
      final version =
          await imported.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), imported.schemaVersion);
      final vehicle = (await imported.vehiclesDao.getLive()).single;
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
      final package = (await serviceOf().exportPackage()).bytes;
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
      final package = (await serviceOf().exportPackage()).bytes;

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
/// to [path], as the step-5 app left it, and returns it as a package.
Future<Uint8List> _v4Package(String path) async {
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
  return encodeBackupPackage(manifest, file.readAsBytesSync());
}

/// File operations that fail to read, to make an export fail after the
/// database copy.
class _UnreadableFiles extends IoBackupFiles {
  @override
  Future<Uint8List> readBytes(String path) async =>
      throw FileSystemException('unreadable', path);
}
