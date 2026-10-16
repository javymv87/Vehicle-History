import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/db/upgrade_safety.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';

/// Schema version of the app under test.
final int _current = () {
  final db = AppDatabase.forExecutor(NativeDatabase.memory());
  final version = db.schemaVersion;
  db.close();
  return version;
}();

/// The app as a future release would ship it: a higher [schemaVersion] and
/// the upgrade [steps] supplied by the test.
///
/// Only tests simulate versions this way; production code has no fake step.
class _FutureAppDatabase extends AppDatabase {
  _FutureAppDatabase(
    super.executor, {
    required OnUpgrade steps,
    int? version,
  })  : version = version ?? _current + 1,
        super.forExecutor(upgradeSteps: steps);

  /// The simulated app schema version.
  final int version;

  @override
  int get schemaVersion => version;
}

/// An upgrade step that changes nothing.
Future<void> _noopStep(Migrator m, int from, int to) async {}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  late File dbFile;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vehicle_history_upgrade_');
    dbFile = File('${dir.path}${Platform.pathSeparator}vehicle_history.sqlite');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Names of the files currently in the test directory, sorted.
  List<String> fileNames() => [
        for (final f in dir.listSync().whereType<File>())
          f.uri.pathSegments.last,
      ]..sort();

  /// Path of the pre-upgrade copy for [from].
  File copyFile(int from) => File(
        '${dir.path}${Platform.pathSeparator}vehicle_history.pre_v$from.sqlite',
      );

  /// Reads `PRAGMA user_version` from [db].
  Future<int> userVersion(GeneratedDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  /// Creates the database file at the current version with one owner and
  /// returns its id.
  Future<String> seedCurrent() async {
    final db = AppDatabase.forExecutor(NativeDatabase(dbFile));
    final owner = await DriftOwnerRepository(db.ownersDao, db.auditLogDao)
        .create(firstName: 'Mario');
    await db.close();
    return owner.id;
  }

  /// Opens the file with the current app and returns the owner names.
  Future<List<String>> readOwnersWithCurrent() async {
    final db = AppDatabase.forExecutor(NativeDatabase(dbFile));
    try {
      expect(await userVersion(db), _current);
      return [for (final o in await db.ownersDao.getLive()) o.firstName];
    } finally {
      await db.close();
    }
  }

  test('a fresh install creates no pre-upgrade copy', () async {
    await seedCurrent();
    expect(fileNames(), ['vehicle_history.sqlite']);
  });

  test('an upgrade first copies the database, then migrates it', () async {
    await seedCurrent();

    final db = _FutureAppDatabase(
      NativeDatabase(dbFile),
      steps: (m, from, to) => m.database.customStatement(
        'ALTER TABLE owners ADD COLUMN nickname TEXT NULL',
      ),
    );
    expect(await userVersion(db), _current + 1);
    await db.close();

    // The copy is a complete database at the old version, with the old data.
    expect(copyFile(_current).existsSync(), isTrue);
    final copy = AppDatabase.forExecutor(NativeDatabase(copyFile(_current)));
    expect(await userVersion(copy), _current);
    final copiedOwners = await copy.ownersDao.getLive();
    expect([for (final o in copiedOwners) o.firstName], ['Mario']);
    await copy.close();
  });

  test('only the latest copy is kept, and stale temporaries are removed',
      () async {
    await seedCurrent();
    copyFile(_current - 1).writeAsStringSync('older copy');
    File('${copyFile(_current).path}.tmp')
        .writeAsStringSync('interrupted copy');

    final db = _FutureAppDatabase(NativeDatabase(dbFile), steps: _noopStep);
    await userVersion(db);
    await db.close();

    expect(fileNames(), [
      'vehicle_history.pre_v$_current.sqlite',
      'vehicle_history.sqlite',
    ]);
  });

  test('a database newer than the app is refused and left untouched', () async {
    await seedCurrent();
    final future = _FutureAppDatabase(
      NativeDatabase(dbFile),
      steps: _noopStep,
      version: 5,
    );
    await userVersion(future);
    await future.close();
    final filesBefore = fileNames();

    final current = AppDatabase.forExecutor(NativeDatabase(dbFile));
    await expectLater(
      current.ownersDao.getLive(),
      throwsA(
        isA<DatabaseNewerThanAppException>()
            .having((e) => e.fileVersion, 'fileVersion', 5)
            .having((e) => e.appVersion, 'appVersion', _current),
      ),
    );
    await current.close();

    // Still v5 with its data, and no copy was made for a refused open.
    final reopened = _FutureAppDatabase(
      NativeDatabase(dbFile),
      steps: _noopStep,
      version: 5,
    );
    expect(await userVersion(reopened), 5);
    expect(await reopened.ownersDao.getLive(), hasLength(1));
    await reopened.close();
    expect(fileNames(), filesBefore);
  });

  test('a migration that breaks a foreign key is rolled back; copy kept',
      () async {
    final ownerId = await seedCurrent();

    final db = _FutureAppDatabase(
      NativeDatabase(dbFile),
      // Simulated faulty step: a vehicle pointing at an owner that does not
      // exist, plus a change to existing data that must be rolled back.
      steps: (m, from, to) async {
        await m.database.customStatement(
          "UPDATE owners SET first_name = 'Changed'",
        );
        await m.database.customStatement(
          'INSERT INTO vehicles (id, created_at, updated_at, plate, owner_id, '
          "current_odometer_km, fuel_type) VALUES ('v1', 'x', 'x', 'AB1', "
          "'no-such-owner', 0, 'petrol')",
        );
      },
    );
    await expectLater(
      db.ownersDao.getLive(),
      throwsA(
        isA<MigrationIntegrityException>()
            .having((e) => e.violations, 'violations', 1),
      ),
    );
    await db.close();

    expect(copyFile(_current).existsSync(), isTrue);
    // Still the current version, original data intact, nothing from the
    // failed step.
    expect(await readOwnersWithCurrent(), ['Mario']);
    final check = AppDatabase.forExecutor(NativeDatabase(dbFile));
    expect(await check.ownersDao.getLiveById(ownerId), isNotNull);
    expect(await check.vehiclesDao.getLive(), isEmpty);
    await check.close();
  });

  test('a failing step is rolled back and the version is unchanged', () async {
    await seedCurrent();

    final db = _FutureAppDatabase(
      NativeDatabase(dbFile),
      steps: (m, from, to) async {
        await m.database.customStatement('DELETE FROM owners');
        throw StateError('simulated step failure');
      },
    );
    await expectLater(db.ownersDao.getLive(), throwsA(isA<StateError>()));
    await db.close();

    expect(await readOwnersWithCurrent(), ['Mario']);
  });

  test('an in-memory database has no file to copy', () async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    expect(await PreUpgradeCopier.mainDatabasePath(db), isNull);
    expect(await const PreUpgradeCopier().copy(db, 1), isNull);
    await db.close();
  });
}
