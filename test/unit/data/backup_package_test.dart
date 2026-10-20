import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/backup/backup_package.dart';
import 'package:vehicle_history/data/backup/backup_service.dart';
import 'package:vehicle_history/data/models/backup_manifest.dart';
import 'package:vehicle_history/shared/constants/app_version.dart';

/// The pure parts of the backup package: manifest, file name, header.
void main() {
  final manifest = BackupManifest(
    formatVersion: 1,
    schemaVersion: 6,
    appVersion: '0.6.0+6',
    exportedAt: DateTime.utc(2026, 10, 20, 16, 30, 5, 123),
    counts: const BackupCounts(
      owners: 1,
      vehicles: 2,
      logEntries: 41,
      mileageReadings: 7,
    ),
    lastModifiedAt: DateTime.utc(2026, 10, 18, 9),
  );

  test('the manifest survives a JSON round trip', () {
    expect(BackupManifest.fromJson(manifest.toJson()), manifest);
    final empty = BackupManifest(
      formatVersion: 1,
      schemaVersion: 6,
      appVersion: '0.6.0+6',
      exportedAt: DateTime.utc(2026),
      counts: const BackupCounts(
        owners: 0,
        vehicles: 0,
        logEntries: 0,
        mileageReadings: 0,
      ),
      lastModifiedAt: null,
    );
    expect(BackupManifest.fromJson(empty.toJson()), empty);
  });

  test('the manifest JSON uses the documented keys and UTC instants', () {
    expect(manifest.toJson(), {
      'format_version': 1,
      'schema_version': 6,
      'app_version': '0.6.0+6',
      'exported_at': '2026-10-20T16:30:05.123Z',
      'counts': {
        'owners': 1,
        'vehicles': 2,
        'log_entries': 41,
        'mileage_readings': 7,
      },
      'last_modified_at': '2026-10-18T09:00:00.000Z',
    });
  });

  test('a manifest with a missing or mistyped key is refused', () {
    for (final change in <String, Object?>{
      'format_version': '1',
      'schema_version': null,
      'app_version': 6,
      'exported_at': 'yesterday',
      'counts': {'owners': 1},
      'last_modified_at': 12,
    }.entries) {
      expect(
        () => BackupManifest.fromJson({
          ...manifest.toJson(),
          change.key: change.value,
        }),
        throwsFormatException,
        reason: change.key,
      );
    }
  });

  test('the file name carries the local date and time', () {
    expect(
      backupFileName(DateTime(2026, 10, 20, 18, 5)),
      'vehicle-history-20261020-1805.zip',
    );
  });

  test('the SQLite header gives the user_version without opening the file', () {
    final header = Uint8List(100)
      ..setAll(0, 'SQLite format 3'.codeUnits)
      ..[15] = 0;
    ByteData.sublistView(header).setUint32(60, 6);
    expect(sqliteUserVersion(header), 6);
    expect(sqliteUserVersion(Uint8List(100)), isNull);
    expect(sqliteUserVersion(Uint8List(10)), isNull);
  });

  test('every schema version requires the tables it introduced', () {
    expect(requiredTablesAt(1), {'owners', 'vehicles', 'audit_log'});
    expect(requiredTablesAt(3), contains('log_entries'));
    expect(requiredTablesAt(4), contains('mileage_readings'));
    expect(requiredTablesAt(5), isNot(contains('settings')));
    expect(requiredTablesAt(6), contains('settings'));
  });

  test('appVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.singleWhere((l) => l.startsWith('version:'));
    expect(line.substring('version:'.length).trim(), appVersion);
  });
}
