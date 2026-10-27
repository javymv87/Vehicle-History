import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/backup/backup_lock.dart';
import 'package:vehicle_history/data/drive/drive_auth_service.dart';
import 'package:vehicle_history/data/drive/drive_auto_backup.dart';
import 'package:vehicle_history/data/drive/drive_backup_client.dart';
import 'package:vehicle_history/data/drive/drive_models.dart';
import 'package:vehicle_history/data/drive/drive_settings.dart';
import 'package:vehicle_history/data/drive/drive_sync_service.dart';
import 'package:vehicle_history/data/drive/sync_guard.dart';
import 'package:vehicle_history/data/models/backup_manifest.dart';
import 'package:vehicle_history/data/models/setting_key.dart';
import 'package:vehicle_history/data/platform/network_state.dart';

import '../../support/fake_backup.dart';
import '../../support/fake_drive.dart';

/// The Drive copy's orchestration on fakes: link and unlink, upload and
/// restore with the last common point, the history of 3 copies, and the one
/// automatic upload at start.
void main() {
  const me = DriveAccount('me@example.com');
  late FakeSettingsRepository settings;
  late FakeBackupService backup;
  late FakeDriveAuthService auth;
  late FakeDriveBackupClient drive;
  late FakeNetworkState network;
  late BackupLock lock;
  late DriveSyncService service;

  setUp(() {
    settings = FakeSettingsRepository();
    backup = FakeBackupService(settings)..local = sampleLocal;
    auth = FakeDriveAuthService();
    drive = FakeDriveBackupClient();
    network = FakeNetworkState();
    lock = BackupLock();
    service = DriveSyncService(
      backup: backup,
      settings: settings,
      auth: auth,
      client: drive,
      schemaVersion: 7,
      appVersion: '0.9.0+10',
      clock: () => DateTime.utc(2026, 10, 23, 8),
    );
  });

  /// The local state with a different stamp: a change on this phone.
  LocalSyncState changedLocal() => LocalSyncState(
        stamp: DateTime.utc(2026, 10, 22, 18),
        counts: sampleLocal.counts,
      );

  /// Links [me] and records a common point with a copy holding the
  /// current local data, as after a successful upload.
  Future<CloudBackup> alignedWithCloud() async {
    await service.link();
    await service.upload(expectedUploadId: null);
    return drive.of(me.email).first;
  }

  Future<AutoUploadOutcome> startup() => runStartupAutoUpload(
        service: service,
        network: network,
        lock: lock,
      );

  group('link and unlink', () {
    test('link stores the account and clears an old common point', () async {
      await alignedWithCloud();
      auth.nextAccount = const DriveAccount('other@example.com');
      await service.link();
      expect(
        await settings.readDriveAccount(),
        const DriveAccount('other@example.com'),
      );
      expect(await settings.readSyncPoint(), isNull);
    });

    test('a cancelled link changes nothing', () async {
      await alignedWithCloud();
      final pointBefore = await settings.readSyncPoint();
      auth.nextAccount = null;
      await expectLater(service.link(), throwsA(isA<DriveAuthException>()));
      expect(await settings.readDriveAccount(), me);
      expect((await settings.readSyncPoint())?.uploadId, pointBefore?.uploadId);
    });

    test('unlink forgets the account and the common point', () async {
      await alignedWithCloud();
      await service.unlink();
      expect(await settings.readDriveAccount(), isNull);
      expect(await settings.readSyncPoint(), isNull);
      expect(auth.unlinks, 1);
      expect(drive.of(me.email), hasLength(1), reason: 'copies stay');
    });

    test('changing account never treats its existing copy as known', () async {
      await alignedWithCloud();
      drive.put('other@example.com', uploadId: 'theirs', stamp: 'none');
      auth.nextAccount = const DriveAccount('other@example.com');
      await service.link();
      final status = await service.check();
      expect(status.state, SyncState.noCommonPoint);
      expect(drive.uploads, hasLength(1), reason: 'only the first one');
    });
  });

  group('upload', () {
    test('records the common point once Drive confirmed it', () async {
      await service.link();
      final uploaded = await service.upload(expectedUploadId: null);
      final point = await settings.readSyncPoint();
      expect(point?.uploadId, uploaded.uploadId);
      expect(point?.localStamp, stampCode(sampleLocal.stamp));
      expect(point?.direction, SyncDirection.upload);
      expect(point?.account, me.email);
      expect(backup.driveDeletes, 1, reason: 'temporary zip deleted');
      final props = drive.uploads.single;
      expect(props['last_modified_at'], stampCode(sampleLocal.stamp));
      expect(props['schema_version'], '7');
      expect(props['app_version'], '0.9.0+10');
      expect(props['vehicles'], '1');
      expect(props['device_id'], await settings.driveDeviceId());
      expect((await service.check()).state, SyncState.aligned);
    });

    test('a failed upload leaves the last common point untouched', () async {
      final first = await alignedWithCloud();
      backup.local = changedLocal();
      drive.uploadFailure = const DriveRequestException('boom');
      await expectLater(
        service.upload(expectedUploadId: first.uploadId),
        throwsA(isA<DriveRequestException>()),
      );
      final point = await settings.readSyncPoint();
      expect(point?.uploadId, first.uploadId);
      expect(point?.localStamp, stampCode(sampleLocal.stamp));
      expect(backup.driveDeletes, 2, reason: 'temporary zip deleted anyway');
    });

    test('a failed package build uploads nothing', () async {
      final first = await alignedWithCloud();
      backup.buildFailure = Exception('disk');
      await expectLater(
        service.upload(expectedUploadId: first.uploadId),
        throwsA(isA<Exception>()),
      );
      expect(drive.uploads, hasLength(1));
      expect((await settings.readSyncPoint())?.uploadId, first.uploadId);
    });

    test('stops when the Drive copy is not the expected one', () async {
      final first = await alignedWithCloud();
      drive.put(me.email, uploadId: 'other', stamp: 'none');
      await expectLater(
        service.upload(expectedUploadId: first.uploadId),
        throwsA(isA<DriveCloudChangedException>()),
      );
      expect(drive.uploads, hasLength(1));
      expect(backup.driveBuilds, 1, reason: 'stopped before building');
    });

    test('never replaces a copy from a newer schema', () async {
      await service.link();
      final newer = drive.put(
        me.email,
        uploadId: 'newer',
        stamp: 'none',
        schemaVersion: 8,
      );
      await expectLater(
        service.upload(expectedUploadId: newer.uploadId),
        throwsA(isA<DriveCloudTooNewException>()),
      );
      expect(drive.uploads, isEmpty);
    });

    test('Drive keeps the last 3 copies: the 4th upload prunes the 1st',
        () async {
      await service.link();
      String? expected;
      for (var i = 0; i < 4; i++) {
        expected = (await service.upload(expectedUploadId: expected)).uploadId;
      }
      final kept = drive.of(me.email);
      expect(kept, hasLength(3));
      expect(drive.deleted, ['file-${drive.uploads.first['upload_id']}']);
      expect(kept.first.uploadId, expected);
    });

    test('a failed pruning does not fail the upload', () async {
      await service.link();
      final client = _FailingDelete(drive);
      final svc = DriveSyncService(
        backup: backup,
        settings: settings,
        auth: auth,
        client: client,
        schemaVersion: 7,
        appVersion: '0.9.0+10',
      );
      String? expected;
      for (var i = 0; i < 4; i++) {
        expected = (await svc.upload(expectedUploadId: expected)).uploadId;
      }
      expect((await settings.readSyncPoint())?.uploadId, expected);
    });
  });

  group('packagesToPrune', () {
    CloudBackup at(int minute) => CloudBackup(
          fileId: 'f$minute',
          uploadId: 'u$minute',
          stamp: noStampCode,
          schemaVersion: 7,
          appVersion: '',
          deviceId: '',
          counts: const BackupCounts(
            owners: 0,
            vehicles: 0,
            logEntries: 0,
            mileageReadings: 0,
          ),
          uploadedAt: DateTime.utc(2026, 10, 20, 10, minute),
          sizeBytes: 0,
        );

    test('keeps the 3 newest, whatever the order given', () {
      final pruned = packagesToPrune([at(2), at(5), at(1), at(4), at(3)]);
      expect(pruned.map((b) => b.fileId), ['f2', 'f1']);
    });

    test('prunes nothing with 3 or fewer', () {
      expect(packagesToPrune([at(1), at(2), at(3)]), isEmpty);
      expect(packagesToPrune([]), isEmpty);
    });
  });

  group('check', () {
    test('records the point when both sides hold the same data', () async {
      await service.link();
      final theirs = drive.put(
        me.email,
        uploadId: 'theirs',
        stamp: stampCode(sampleLocal.stamp),
        counts: sampleLocal.counts,
      );
      final status = await service.check();
      expect(status.verdict.sameContent, isTrue);
      expect((await settings.readSyncPoint())?.uploadId, theirs.uploadId);
      expect(
        (await service.check()).verdict,
        const SyncVerdict(SyncState.aligned),
      );
    });

    test('reads metadata only, never a package', () async {
      await alignedWithCloud();
      await service.check();
      expect(drive.downloads, isEmpty);
    });
  });

  group('restore', () {
    test('downloads the latest copy and checks it before anything', () async {
      await service.link();
      drive.put(me.email, uploadId: 'old', stamp: 'none');
      final latest = drive.put(me.email, uploadId: 'latest', stamp: 'none');
      final prepared = await service.prepareRestore();
      expect(prepared.backup.uploadId, latest.uploadId);
      expect(drive.downloads.single.fileId, latest.fileId);
      expect(drive.downloads.single.path, '/fake/downloaded.zip.tmp');
      expect(backup.imports, 0);
    });

    test('goes through the import and records the point afterwards', () async {
      await service.link();
      final latest = drive.put(
        me.email,
        uploadId: 'latest',
        stamp: stampCode(sampleLocal.stamp),
      );
      backup.local = emptyLocal;
      final prepared = await service.prepareRestore();
      await service.importDownload(prepared);
      expect(backup.imports, 1);
      expect(backup.downloadDeletes, greaterThanOrEqualTo(2));
      // The import cleared the point; the new connection records it.
      expect(await settings.readSyncPoint(), isNull);
      await service.recordDownload(prepared);
      final point = await settings.readSyncPoint();
      expect(point?.uploadId, latest.uploadId);
      expect(point?.direction, SyncDirection.download);
      expect(point?.localStamp, stampCode(backup.localAfterImport.stamp));
      expect((await service.check()).state, SyncState.aligned);
    });

    test('a failed download leaves the data and the point untouched', () async {
      final first = await alignedWithCloud();
      drive.downloadFailure =
          const DriveRequestException('lost', offline: true);
      await expectLater(
        service.prepareRestore(),
        throwsA(isA<DriveRequestException>()),
      );
      expect(backup.imports, 0);
      expect((await settings.readSyncPoint())?.uploadId, first.uploadId);
      expect(backup.downloadDeletes, greaterThanOrEqualTo(2));
    });

    test('a rejected package is deleted and nothing is imported', () async {
      final first = await alignedWithCloud();
      backup.rejectWith = notAPackage;
      await expectLater(service.prepareRestore(), throwsA(anything));
      expect(backup.imports, 0);
      expect((await settings.readSyncPoint())?.uploadId, first.uploadId);
    });

    test('a failed import keeps the previous point out of the way', () async {
      await alignedWithCloud();
      final prepared = await service.prepareRestore();
      backup.importFailure = Exception('import failed');
      await expectLater(service.importDownload(prepared), throwsA(anything));
      // The real import restores the previous database (with its point);
      // nothing here records a new one.
      expect(backup.imports, 0);
    });

    test('refuses a copy from a newer schema', () async {
      await service.link();
      drive.put(me.email, uploadId: 'newer', stamp: 'none', schemaVersion: 8);
      await expectLater(
        service.prepareRestore(),
        throwsA(isA<DriveCloudTooNewException>()),
      );
      expect(drive.downloads, isEmpty);
    });
  });

  group('the automatic upload at start', () {
    test('no account: nothing at all', () async {
      final outcome = await startup();
      expect(outcome.status?.state, SyncState.noAccount);
      expect(drive.listings, 0);
      expect(drive.uploads, isEmpty);
    });

    test('no cloud copy: uploads', () async {
      await settings.writeDriveAccount(me);
      final outcome = await startup();
      expect(outcome.uploaded, isTrue);
      expect(outcome.status?.state, SyncState.aligned);
      expect(drive.uploads, hasLength(1));
    });

    test('only local changed: uploads', () async {
      await alignedWithCloud();
      backup.local = changedLocal();
      final outcome = await startup();
      expect(outcome.uploaded, isTrue);
      expect(drive.uploads, hasLength(2));
      expect(outcome.status?.state, SyncState.aligned);
    });

    test('aligned: nothing uploaded', () async {
      await alignedWithCloud();
      final outcome = await startup();
      expect(outcome.uploaded, isFalse);
      expect(outcome.status?.state, SyncState.aligned);
      expect(drive.uploads, hasLength(1));
    });

    for (final (name, arrange, expected)
        in <(String, Future<void> Function(), SyncState)>[
      (
        'cloud changed',
        () async {
          await alignedWithCloud();
          drive.put(me.email, uploadId: 'theirs', stamp: 'none');
        },
        SyncState.cloudChanged,
      ),
      (
        'diverged',
        () async {
          await alignedWithCloud();
          backup.local = changedLocal();
          drive.put(me.email, uploadId: 'theirs', stamp: 'none');
        },
        SyncState.diverged,
      ),
      (
        'no common point',
        () async {
          await settings.writeDriveAccount(me);
          drive.put(me.email, uploadId: 'theirs', stamp: 'none');
        },
        SyncState.noCommonPoint,
      ),
      (
        'cloud too new',
        () async {
          await alignedWithCloud();
          backup.local = changedLocal();
          drive.put(
            me.email,
            uploadId: 'newer',
            stamp: 'none',
            schemaVersion: 8,
          );
        },
        SyncState.cloudTooNew,
      ),
    ]) {
      test('$name: never uploads, only reports', () async {
        await arrange();
        final uploadsBefore = drive.uploads.length;
        final pointBefore = await settings.readSyncPoint();
        final outcome = await startup();
        expect(outcome.status?.state, expected);
        expect(outcome.uploaded, isFalse);
        expect(outcome.failure, isNull);
        expect(drive.uploads, hasLength(uploadsBefore));
        expect(
          (await settings.readSyncPoint())?.uploadId,
          pointBefore?.uploadId,
        );
      });
    }

    test('re-reads the metadata right before uploading', () async {
      final first = await alignedWithCloud();
      backup.local = changedLocal();
      // Another phone uploads between the check and the upload.
      drive.onUpload = null;
      var listingsAtCheck = 0;
      final checking = _ListHook(drive, () {
        listingsAtCheck++;
        if (listingsAtCheck == 2) {
          drive.put(me.email, uploadId: 'theirs', stamp: 'none');
        }
      });
      final svc = DriveSyncService(
        backup: backup,
        settings: settings,
        auth: auth,
        client: checking,
        schemaVersion: 7,
        appVersion: '0.9.0+10',
      );
      final outcome = await runStartupAutoUpload(
        service: svc,
        network: network,
        lock: lock,
      );
      expect(outcome.uploaded, isFalse);
      expect(outcome.status?.state, SyncState.diverged);
      expect(drive.uploads, hasLength(1));
      expect((await settings.readSyncPoint())?.uploadId, first.uploadId);
    });

    test('a failed upload sets the error and leaves the point', () async {
      final first = await alignedWithCloud();
      backup.local = changedLocal();
      drive.uploadFailure = const DriveRequestException('500');
      final outcome = await startup();
      expect(outcome.failure, DriveFailure.failed);
      expect(outcome.uploaded, isFalse);
      expect(outcome.status?.state, SyncState.localChanged);
      expect((await settings.readSyncPoint())?.uploadId, first.uploadId);
      // The next start tries again and succeeds.
      drive.uploadFailure = null;
      final next = await startup();
      expect(next.uploaded, isTrue);
      expect(next.failure, isNull);
    });

    test('offline: error status, nothing uploaded', () async {
      await alignedWithCloud();
      backup.local = changedLocal();
      network.kind = NetworkKind.none;
      final outcome = await startup();
      expect(outcome.failure, DriveFailure.offline);
      expect(drive.uploads, hasLength(1));
    });

    test('Drive unreachable at the check: error status', () async {
      await alignedWithCloud();
      drive.listFailure = const DriveRequestException('dns', offline: true);
      final outcome = await startup();
      expect(outcome.status, isNull);
      expect(outcome.failure, DriveFailure.offline);
    });

    test('authorisation withdrawn: needs relink', () async {
      await alignedWithCloud();
      drive.listFailure = const DriveAuthorizationRequiredException();
      final outcome = await startup();
      expect(outcome.failure, DriveFailure.needsRelink);
    });

    test('mobile data not allowed: waits for Wi-Fi', () async {
      await alignedWithCloud();
      backup.local = changedLocal();
      network.kind = NetworkKind.metered;
      final outcome = await startup();
      expect(outcome.waitingForUnmetered, isTrue);
      expect(outcome.failure, isNull);
      expect(drive.uploads, hasLength(1));
    });

    test('mobile data allowed: uploads on a metered network', () async {
      await alignedWithCloud();
      backup.local = changedLocal();
      network.kind = NetworkKind.metered;
      await settings.writeDriveMobileData(allowed: true);
      final outcome = await startup();
      expect(outcome.uploaded, isTrue);
    });

    test('another backup operation running: nothing uploaded', () async {
      await alignedWithCloud();
      backup.local = changedLocal();
      late Future<AutoUploadOutcome> outcome;
      await lock.run(() async {
        outcome = startup();
        await outcome;
      });
      expect((await outcome).uploaded, isFalse);
      expect(drive.uploads, hasLength(1));
    });
  });

  group('settings scopes', () {
    test('the Drive link belongs to the phone, the point is cleared', () {
      expect(SettingKey.driveAccount.scope, SettingScope.device);
      expect(SettingKey.driveDeviceId.scope, SettingScope.device);
      expect(SettingKey.driveMobileData.scope, SettingScope.device);
      expect(SettingKey.driveSyncUploadId.scope, SettingScope.syncPoint);
      expect(SettingKey.language.scope, SettingScope.shared);
      expect(SettingKey.lastExportAt.scope, SettingScope.shared);
    });

    test('an incomplete point does not count', () async {
      await settings.write(SettingKey.driveSyncUploadId, 'u1');
      expect(await settings.readSyncPoint(), isNull);
    });
  });

  group('link modes', () {
    const manual = DriveAccount('me@example.com', mode: DriveAuthMode.manual);
    late FakeDriveAuthService manualAuth;

    setUp(() {
      manualAuth = FakeDriveAuthService()..nextAccount = manual;
      service = DriveSyncService(
        backup: backup,
        settings: settings,
        auth: auth,
        manualAuth: manualAuth,
        client: drive,
        schemaVersion: 7,
        appVersion: '0.9.0+10',
        clock: () => DateTime.utc(2026, 10, 23, 8),
      );
    });

    test('the mode is a phone setting, absent means system', () async {
      expect(SettingKey.driveAuthMode.scope, SettingScope.device);
      await settings.write(SettingKey.driveAccount, me.email);
      expect(await settings.readDriveAccount(), me, reason: '0.9.0 link');
    });

    test('a manual link stores the mode with the account', () async {
      expect(await service.link(mode: DriveAuthMode.manual), manual);
      expect(await settings.read(SettingKey.driveAuthMode), 'manual');
      expect(await settings.readDriveAccount(), manual);
    });

    test('the copies belong to the email, whatever the mode', () async {
      await service.link(mode: DriveAuthMode.manual);
      await service.upload(expectedUploadId: null);
      expect(drive.of(me.email), hasLength(1));
      expect((await service.check()).state, SyncState.aligned);
    });

    test('linking in the other mode needs an unlink first', () async {
      await service.link();
      await expectLater(
        service.link(mode: DriveAuthMode.manual),
        throwsA(isA<DriveAuthException>()),
      );
      expect(await settings.readDriveAccount(), me);
      await service.unlink();
      expect(await service.link(mode: DriveAuthMode.manual), manual);
    });

    test('unlink goes to the service of the linked mode', () async {
      await service.link(mode: DriveAuthMode.manual);
      expect(await service.unlink(), isTrue);
      expect(manualAuth.unlinks, 1);
      expect(auth.unlinks, 0);
      expect(await settings.read(SettingKey.driveAuthMode), isNull);
    });

    test('a failed revocation unlinks anyway and says so', () async {
      await service.link(mode: DriveAuthMode.manual);
      manualAuth.unlinkFailure = const DriveRevocationFailedException('x');
      expect(await service.unlink(), isFalse);
      expect(await settings.readDriveAccount(), isNull);
      expect(await settings.readSyncPoint(), isNull);
    });

    test('the router asks the service of the account mode', () async {
      final router = DriveAuthRouter({
        DriveAuthMode.system: auth,
        DriveAuthMode.manual: manualAuth,
      });
      await router.accessToken(manual);
      await router.invalidate('token-1');
      expect(manualAuth.invalidated, ['token-1']);
      expect(auth.invalidated, isEmpty);
      manualAuth.tokenFailure = const DriveAuthorizationRequiredException();
      await expectLater(
        router.accessToken(manual),
        throwsA(isA<DriveAuthorizationRequiredException>()),
      );
      expect(await router.accessToken(me), 'token-1', reason: 'mode 1');
    });
  });
}

/// A client whose deletes fail.
class _FailingDelete implements DriveBackupClient {
  _FailingDelete(this._inner);

  final FakeDriveBackupClient _inner;

  @override
  Future<void> delete(DriveAccount account, String fileId) async =>
      throw const DriveRequestException('delete failed');

  @override
  Future<void> download(
    DriveAccount account,
    CloudBackup backup,
    String targetPath, {
    DriveTransfer? transfer,
  }) =>
      _inner.download(account, backup, targetPath, transfer: transfer);

  @override
  Future<List<CloudBackup>> listBackups(DriveAccount account) =>
      _inner.listBackups(account);

  @override
  Future<CloudBackup> upload(
    DriveAccount account, {
    required String path,
    required String fileName,
    required Map<String, String> properties,
    DriveTransfer? transfer,
  }) =>
      _inner.upload(
        account,
        path: path,
        fileName: fileName,
        properties: properties,
        transfer: transfer,
      );
}

/// A client that runs [_onList] before each listing.
class _ListHook extends _FailingDelete {
  _ListHook(super.inner, this._onList);

  final void Function() _onList;

  @override
  Future<List<CloudBackup>> listBackups(DriveAccount account) {
    _onList();
    return super.listBackups(account);
  }
}
