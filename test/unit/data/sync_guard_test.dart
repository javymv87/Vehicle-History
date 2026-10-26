import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/drive/drive_models.dart';
import 'package:vehicle_history/data/drive/sync_guard.dart';
import 'package:vehicle_history/data/models/backup_manifest.dart';

/// The version guard of the Drive copy (`Docs/05_sync_and_storage.md`):
/// every state and edge, as a pure function.
void main() {
  const account = DriveAccount('me@example.com');
  const counts = BackupCounts(
    owners: 1,
    vehicles: 2,
    logEntries: 41,
    mileageReadings: 7,
    attachments: 3,
  );
  final stampA = DateTime.utc(2026, 10, 18, 12);
  final stampB = DateTime.utc(2026, 10, 19, 9, 30);

  LocalSyncState local(DateTime? stamp, [BackupCounts c = counts]) =>
      LocalSyncState(stamp: stamp, counts: c);

  CloudBackup cloud({
    String uploadId = 'u1',
    DateTime? stamp,
    bool empty = false,
    int schema = 7,
    BackupCounts c = counts,
  }) =>
      CloudBackup(
        fileId: 'f-$uploadId',
        uploadId: uploadId,
        stamp: empty ? noStampCode : stampCode(stamp ?? stampA),
        schemaVersion: schema,
        appVersion: '0.9.0+10',
        deviceId: 'phone',
        counts: c,
        uploadedAt: DateTime.utc(2026, 10, 20),
        sizeBytes: 1,
      );

  SyncPoint point({
    String uploadId = 'u1',
    DateTime? localStamp,
    bool emptyLocal = false,
    String email = 'me@example.com',
  }) =>
      SyncPoint(
        account: email,
        localStamp: emptyLocal ? noStampCode : stampCode(localStamp ?? stampA),
        uploadId: uploadId,
        at: DateTime.utc(2026, 10, 20),
        direction: SyncDirection.upload,
      );

  SyncVerdict guard({
    DriveAccount? acc = account,
    required LocalSyncState localState,
    CloudBackup? cloudCopy,
    SyncPoint? commonPoint,
    int appSchema = 7,
  }) =>
      evaluateSync(
        account: acc,
        local: localState,
        cloud: cloudCopy,
        commonPoint: commonPoint,
        appSchemaVersion: appSchema,
      );

  group('no account', () {
    test('is noAccount whatever else is known', () {
      expect(
        guard(
          acc: null,
          localState: local(stampA),
          cloudCopy: cloud(),
          commonPoint: point(),
        ),
        const SyncVerdict(SyncState.noAccount),
      );
    });
  });

  group('no cloud copy', () {
    test('first link: noCloudCopy (automatic first upload)', () {
      expect(
        guard(localState: local(stampA)).state,
        SyncState.noCloudCopy,
      );
    });

    test('an empty database with no copy is noCloudCopy too', () {
      expect(guard(localState: local(null)).state, SyncState.noCloudCopy);
    });

    test('a common point whose copy was deleted in Drive is noCloudCopy', () {
      expect(
        guard(localState: local(stampA), commonPoint: point()).state,
        SyncState.noCloudCopy,
      );
    });
  });

  group('cloud copy from a newer schema', () {
    test('is cloudTooNew even when only local changed', () {
      expect(
        guard(
          localState: local(stampB),
          cloudCopy: cloud(schema: 8),
          commonPoint: point(),
        ).state,
        SyncState.cloudTooNew,
      );
    });

    test('is cloudTooNew with no common point and equal data', () {
      expect(
        guard(localState: local(stampA), cloudCopy: cloud(schema: 8)).state,
        SyncState.cloudTooNew,
      );
    });

    test('an older schema in the cloud is compared normally', () {
      expect(
        guard(
          localState: local(stampA),
          cloudCopy: cloud(schema: 6),
          commonPoint: point(),
        ).state,
        SyncState.aligned,
      );
    });
  });

  group('no common point', () {
    test('first link with an existing copy: noCommonPoint', () {
      expect(
        guard(localState: local(stampB), cloudCopy: cloud()).state,
        SyncState.noCommonPoint,
      );
    });

    test('new phone with an empty database: noCommonPoint', () {
      expect(
        guard(localState: local(null), cloudCopy: cloud()).state,
        SyncState.noCommonPoint,
      );
    });

    test('two empty databases are not "the same data"', () {
      expect(
        guard(localState: local(null), cloudCopy: cloud(empty: true)).state,
        SyncState.noCommonPoint,
      );
    });

    test('same non-empty stamp and same counts: aligned, adopted', () {
      expect(
        guard(localState: local(stampA), cloudCopy: cloud()),
        const SyncVerdict(SyncState.aligned, sameContent: true),
      );
    });

    test('same stamp but different counts: noCommonPoint', () {
      const other = BackupCounts(
        owners: 1,
        vehicles: 2,
        logEntries: 40,
        mileageReadings: 7,
        attachments: 3,
      );
      expect(
        guard(localState: local(stampA, other), cloudCopy: cloud()).state,
        SyncState.noCommonPoint,
      );
    });

    test('a different attachment count alone is a difference', () {
      const other = BackupCounts(
        owners: 1,
        vehicles: 2,
        logEntries: 41,
        mileageReadings: 7,
        attachments: 4,
      );
      expect(
        guard(localState: local(stampA, other), cloudCopy: cloud()).state,
        SyncState.noCommonPoint,
      );
    });

    test('a point recorded with another account does not count', () {
      expect(
        guard(
          localState: local(stampB),
          cloudCopy: cloud(),
          commonPoint: point(email: 'old@example.com'),
        ).state,
        SyncState.noCommonPoint,
      );
    });
  });

  group('with a common point', () {
    test('nothing changed: aligned', () {
      expect(
        guard(
          localState: local(stampA),
          cloudCopy: cloud(),
          commonPoint: point(),
        ),
        const SyncVerdict(SyncState.aligned),
      );
    });

    test('an empty database at the point and still empty: aligned', () {
      expect(
        guard(
          localState: local(null),
          cloudCopy: cloud(empty: true),
          commonPoint: point(emptyLocal: true),
        ).state,
        SyncState.aligned,
      );
    });

    test('only local changed: localChanged', () {
      expect(
        guard(
          localState: local(stampB),
          cloudCopy: cloud(),
          commonPoint: point(),
        ).state,
        SyncState.localChanged,
      );
    });

    test('a local stamp that went back is a change too', () {
      expect(
        guard(
          localState: local(DateTime.utc(2026, 1, 1)),
          cloudCopy: cloud(),
          commonPoint: point(),
        ).state,
        SyncState.localChanged,
      );
    });

    test('only the cloud changed: cloudChanged', () {
      expect(
        guard(
          localState: local(stampA),
          cloudCopy: cloud(uploadId: 'u2', stamp: stampB),
          commonPoint: point(),
        ).state,
        SyncState.cloudChanged,
      );
    });

    test('both changed: diverged', () {
      expect(
        guard(
          localState: local(stampB),
          cloudCopy: cloud(uploadId: 'u2', stamp: DateTime.utc(2026, 10, 21)),
          commonPoint: point(),
        ).state,
        SyncState.diverged,
      );
    });

    test('clock skew is irrelevant: an "older" cloud stamp still counts', () {
      // The other phone's clock is behind: its newer upload carries an
      // earlier stamp. The upload id tells the change, not the time.
      expect(
        guard(
          localState: local(stampA),
          cloudCopy: cloud(uploadId: 'u2', stamp: DateTime.utc(2020)),
          commonPoint: point(),
        ).state,
        SyncState.cloudChanged,
      );
    });

    test('a new cloud upload holding exactly the local data: aligned', () {
      expect(
        guard(
          localState: local(stampB),
          cloudCopy: cloud(uploadId: 'u2', stamp: stampB),
          commonPoint: point(),
        ),
        const SyncVerdict(SyncState.aligned, sameContent: true),
      );
    });

    test('a new cloud upload with the same stamp but other counts', () {
      const other = BackupCounts(
        owners: 2,
        vehicles: 2,
        logEntries: 41,
        mileageReadings: 7,
        attachments: 3,
      );
      expect(
        guard(
          localState: local(stampB),
          cloudCopy: cloud(uploadId: 'u2', stamp: stampB, c: other),
          commonPoint: point(),
        ).state,
        SyncState.diverged,
      );
    });
  });

  group('stampCode', () {
    test('is ISO-8601 UTC, or none for an empty database', () {
      expect(stampCode(null), noStampCode);
      expect(
        stampCode(DateTime.utc(2026, 10, 18, 12)),
        '2026-10-18T12:00:00.000Z',
      );
      expect(
        stampCode(DateTime.utc(2026, 10, 18, 12).toLocal()),
        '2026-10-18T12:00:00.000Z',
      );
    });
  });
}
