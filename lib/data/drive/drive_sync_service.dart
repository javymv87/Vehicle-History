import 'package:flutter/foundation.dart' show debugPrint;

import '../backup/backup_service.dart';
import '../models/backup_manifest.dart';
import '../repositories/repository_support.dart';
import '../repositories/settings_repository.dart';
import 'drive_auth_service.dart';
import 'drive_backup_client.dart';
import 'drive_config.dart';
import 'drive_models.dart';
import 'drive_settings.dart';
import 'sync_guard.dart';

/// The Drive copy changed between the check and the upload (another phone
/// uploaded meanwhile): the upload is stopped, nothing was replaced.
class DriveCloudChangedException implements Exception {
  /// Creates the exception.
  const DriveCloudChangedException();

  @override
  String toString() => 'DriveCloudChangedException';
}

/// The Drive copy comes from a newer schema: it is never replaced by an
/// upload of this app and cannot be downloaded.
class DriveCloudTooNewException implements Exception {
  /// Creates the exception.
  const DriveCloudTooNewException();

  @override
  String toString() => 'DriveCloudTooNewException';
}

/// Where the local data and the Drive copy stand, as read by
/// [DriveSyncService.check].
class DriveStatus {
  /// Creates the status.
  const DriveStatus({
    required this.account,
    required this.verdict,
    required this.local,
    required this.history,
    required this.commonPoint,
  });

  /// The linked account, `null` when none.
  final DriveAccount? account;

  /// What the guard concluded.
  final SyncVerdict verdict;

  /// The local data.
  final LocalSyncState local;

  /// The packages in Drive, newest first (empty without an account).
  final List<CloudBackup> history;

  /// The last common point (after a [SyncVerdict.sameContent] check, the one
  /// just recorded); `null` when there is none.
  final SyncPoint? commonPoint;

  /// The latest Drive copy, the one the guard compared.
  CloudBackup? get latest => history.isEmpty ? null : history.first;

  /// Shortcut to the verdict's state.
  SyncState get state => verdict.state;
}

/// A Drive package downloaded and checked, waiting for the user's
/// confirmation before it replaces the local data.
class PreparedDownload {
  /// Creates the prepared download.
  const PreparedDownload({
    required this.backup,
    required this.path,
    required this.preview,
  });

  /// The Drive copy.
  final CloudBackup backup;

  /// The downloaded file, next to the database.
  final String path;

  /// What it holds, as for a manual import.
  final ImportPreview preview;
}

/// The Drive copy's operations on top of the backup package of step 8
/// (`Docs/05_sync_and_storage.md`): link and unlink, the version guard,
/// upload (keeping the last `driveKeptCopies` copies) and restore of the
/// latest copy, always through the import safety net.
///
/// The last common point is recorded only after an upload is confirmed by
/// Drive or an import has succeeded; any failure in between leaves the
/// previous point untouched.
///
/// Bound to one database connection: after an import, the caller uses the
/// service of the new connection (the provider is rebuilt).
class DriveSyncService {
  /// Creates the service.
  DriveSyncService({
    required BackupService backup,
    required SettingsRepository settings,
    required DriveAuthService auth,
    required DriveBackupClient client,
    required int schemaVersion,
    required String appVersion,
    UtcClock clock = systemUtcClock,
  })  : _backup = backup,
        _settings = settings,
        _auth = auth,
        _client = client,
        _schemaVersion = schemaVersion,
        _appVersion = appVersion,
        _clock = clock;

  final BackupService _backup;
  final SettingsRepository _settings;
  final DriveAuthService _auth;
  final DriveBackupClient _client;

  /// This app's database schema version.
  final int _schemaVersion;

  /// This app's version, written with each upload.
  final String _appVersion;

  /// Source of the common point instants.
  final UtcClock _clock;

  /// The linked account, from the settings.
  Future<DriveAccount?> linkedAccount() => _settings.readDriveAccount();

  /// Links an account through the system picker and consent screen.
  ///
  /// The last common point is cleared: it belonged to the previous account
  /// (or to none), and an existing copy in the new account must never be
  /// treated as known.
  Future<DriveAccount> link() async {
    final account = await _auth.link();
    await _settings.clearSyncPoint();
    await _settings.writeDriveAccount(account);
    return account;
  }

  /// Unlinks the account on this phone and clears the last common point.
  /// The copies stay in that account's Drive.
  Future<void> unlink() async {
    await _settings.clearSyncPoint();
    await _settings.writeDriveAccount(null);
    try {
      await _auth.unlink();
    } on Exception catch (error) {
      // The local link is gone, which is what matters; the sign-out is a
      // courtesy.
      debugPrint('Drive sign-out failed: $error');
    }
  }

  /// Reads the Drive metadata (never a package) and runs the guard.
  ///
  /// When both sides turn out to hold the same data, that state is recorded
  /// as the new common point.
  Future<DriveStatus> check() async {
    final account = await linkedAccount();
    final local = await _backup.localSyncState();
    var point = await _settings.readSyncPoint();
    final history = account == null
        ? const <CloudBackup>[]
        : await _client.listBackups(account);
    final verdict = evaluateSync(
      account: account,
      local: local,
      cloud: history.isEmpty ? null : history.first,
      commonPoint: point,
      appSchemaVersion: _schemaVersion,
    );
    if (verdict.sameContent) {
      point = SyncPoint(
        account: account!.email,
        localStamp: stampCode(local.stamp),
        uploadId: history.first.uploadId,
        at: utcNow(_clock),
        direction: point?.direction ?? SyncDirection.download,
      );
      await _settings.writeSyncPoint(point);
    }
    return DriveStatus(
      account: account,
      verdict: verdict,
      local: local,
      history: history,
      commonPoint: point,
    );
  }

  /// Uploads the local data as a new package and records the common point
  /// once Drive has confirmed it, then prunes the history.
  ///
  /// [expectedUploadId] is the latest Drive copy the caller's decision was
  /// based on (`null` when there was none): if the latest copy is another
  /// one now, the upload stops with [DriveCloudChangedException] before
  /// anything is sent. A copy from a newer schema is never replaced
  /// ([DriveCloudTooNewException]).
  Future<CloudBackup> upload({
    required String? expectedUploadId,
    DriveTransfer? transfer,
  }) async {
    final account = await _requireAccount();
    final before = await _client.listBackups(account);
    final latest = before.isEmpty ? null : before.first;
    if (latest?.uploadId != expectedUploadId) {
      throw const DriveCloudChangedException();
    }
    if (latest != null && latest.schemaVersion > _schemaVersion) {
      throw const DriveCloudTooNewException();
    }

    final package = await _backup.buildDrivePackage();
    try {
      final uploaded = await _client.upload(
        account,
        path: package.path,
        fileName: package.fileName,
        properties: CloudBackup.propertiesOf(
          uploadId: newId(),
          stamp: stampCode(package.local.stamp),
          schemaVersion: _schemaVersion,
          appVersion: _appVersion,
          deviceId: await _settings.driveDeviceId(),
          counts: package.local.counts,
        ),
        transfer: transfer,
      );
      await _settings.writeSyncPoint(
        SyncPoint(
          account: account.email,
          localStamp: stampCode(package.local.stamp),
          uploadId: uploaded.uploadId,
          at: utcNow(_clock),
          direction: SyncDirection.upload,
        ),
      );
      await _pruneHistory(account, [uploaded, ...before]);
      return uploaded;
    } finally {
      await _backup.deleteDrivePackage();
    }
  }

  /// Whether the automatic copy may use a metered network.
  Future<bool> mobileDataAllowed() => _settings.readDriveMobileData();

  /// Downloads the latest Drive copy next to the database and checks it as
  /// a manual import would, without touching the data. A rejection or
  /// failure deletes the file.
  ///
  /// Throws [DriveCloudChangedException] when there is no copy any more
  /// and [DriveCloudTooNewException] for a copy of a newer schema.
  Future<PreparedDownload> prepareRestore({DriveTransfer? transfer}) async {
    final account = await _requireAccount();
    final history = await _client.listBackups(account);
    if (history.isEmpty) throw const DriveCloudChangedException();
    final backup = history.first;
    if (backup.schemaVersion > _schemaVersion) {
      throw const DriveCloudTooNewException();
    }
    final path = await _backup.downloadedPackagePath();
    await _backup.deleteDownloadedPackage();
    try {
      await _client.download(account, backup, path, transfer: transfer);
      final preview = await _backup.inspectPackage(path);
      return PreparedDownload(backup: backup, path: path, preview: preview);
    } on Object {
      await _backup.deleteDownloadedPackage();
      rethrow;
    }
  }

  /// Replaces the local data with [download] through the import safety
  /// net (`BackupService.importPackage`), which closes this connection.
  /// The downloaded file is deleted in any case.
  ///
  /// The caller reopens the database and then calls [recordDownload] on
  /// the service of the new connection.
  Future<BackupManifest> importDownload(PreparedDownload download) async {
    try {
      return await _backup.importPackage(download.path);
    } finally {
      await _backup.deleteDownloadedPackage();
    }
  }

  /// Deletes a downloaded package the user decided not to import.
  Future<void> discardDownload() => _backup.deleteDownloadedPackage();

  /// Records the common point after [download] was imported successfully,
  /// on the new connection. The local stamp is read now, after the
  /// reopening, whose cleanup may have purged rows.
  Future<void> recordDownload(PreparedDownload download) async {
    final account = await _requireAccount();
    final local = await _backup.localSyncState();
    await _settings.writeSyncPoint(
      SyncPoint(
        account: account.email,
        localStamp: stampCode(local.stamp),
        uploadId: download.backup.uploadId,
        at: utcNow(_clock),
        direction: SyncDirection.download,
      ),
    );
  }

  /// The linked account, or a [DriveAuthorizationRequiredException].
  Future<DriveAccount> _requireAccount() async =>
      await linkedAccount() ??
      (throw const DriveAuthorizationRequiredException());

  /// Deletes the packages [packagesToPrune] names among [all]. A failure is
  /// logged: the upload itself succeeded, and the next one prunes again.
  Future<void> _pruneHistory(
    DriveAccount account,
    List<CloudBackup> all,
  ) async {
    for (final backup in packagesToPrune(all)) {
      try {
        await _client.delete(account, backup.fileId);
      } on Exception catch (error) {
        debugPrint('Pruning a Drive package failed: $error');
      }
    }
  }
}

/// The packages of [backups] beyond the newest [keep]: Drive keeps the last
/// [keep] copies, silently, and older ones are deleted after each upload.
List<CloudBackup> packagesToPrune(
  List<CloudBackup> backups, {
  int keep = driveKeptCopies,
}) {
  final sorted = [...backups]
    ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
  return sorted.length <= keep ? const [] : sorted.sublist(keep);
}
