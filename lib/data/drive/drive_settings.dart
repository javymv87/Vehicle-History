import '../models/setting_key.dart';
import '../repositories/repository_support.dart';
import '../repositories/settings_repository.dart';
import 'drive_models.dart';

/// Typed access to the Drive settings (`SettingKey.drive…`).
extension DriveSettings on SettingsRepository {
  /// The linked account with its mode, or `null` when none.
  Future<DriveAccount?> readDriveAccount() async =>
      _accountOf(await read(SettingKey.driveAccount));

  /// Emits the linked account now and after every change. The mode is
  /// written before the email ([writeDriveAccount]), so it is read here
  /// when the email changes.
  Stream<DriveAccount?> watchDriveAccount() =>
      watch(SettingKey.driveAccount).asyncMap(_accountOf).distinct();

  /// The account of [email] with the stored mode, or `null` for none.
  Future<DriveAccount?> _accountOf(String? email) async {
    if (email == null || email.isEmpty) return null;
    final mode = DriveAuthMode.fromCode(await read(SettingKey.driveAuthMode));
    return DriveAccount(email, mode: mode);
  }

  /// Stores [account] as the linked one with its mode (`null` unlinks and
  /// clears the mode too).
  Future<void> writeDriveAccount(DriveAccount? account) async {
    if (account == null) {
      await write(SettingKey.driveAccount, null);
      await write(SettingKey.driveAuthMode, null);
      return;
    }
    // The mode first: watchDriveAccount reads it when the email changes.
    await write(SettingKey.driveAuthMode, account.mode.code);
    await write(SettingKey.driveAccount, account.email);
  }

  /// This phone's id in the copies it uploads, created on first use.
  Future<String> driveDeviceId() async {
    final existing = await read(SettingKey.driveDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = newId();
    await write(SettingKey.driveDeviceId, created);
    return created;
  }

  /// Emits whether the automatic copy may use mobile data (default `false`).
  Stream<bool> watchDriveMobileData() =>
      watch(SettingKey.driveMobileData).map((v) => v == 'true').distinct();

  /// Whether the automatic copy may use mobile data (default `false`).
  Future<bool> readDriveMobileData() async =>
      await read(SettingKey.driveMobileData) == 'true';

  /// Stores whether the automatic copy may use mobile data.
  Future<void> writeDriveMobileData({required bool allowed}) =>
      write(SettingKey.driveMobileData, '$allowed');

  /// The last common point, or `null` when there is none or it is
  /// incomplete (an interrupted write never counts as a point).
  Future<SyncPoint?> readSyncPoint() async {
    final account = await read(SettingKey.driveSyncAccount);
    final localStamp = await read(SettingKey.driveSyncLocalStamp);
    final uploadId = await read(SettingKey.driveSyncUploadId);
    final at = DateTime.tryParse(await read(SettingKey.driveSyncAt) ?? '');
    final direction = SyncDirection.fromCode(
      await read(SettingKey.driveSyncDirection),
    );
    if (account == null ||
        localStamp == null ||
        uploadId == null ||
        at == null ||
        direction == null) {
      return null;
    }
    return SyncPoint(
      account: account,
      localStamp: localStamp,
      uploadId: uploadId,
      at: at.toUtc(),
      direction: direction,
    );
  }

  /// Emits when the last common point was reached and how, now and after
  /// every change; `null` when there is none.
  Stream<({DateTime at, SyncDirection direction})?> watchSyncPointSummary() =>
      watch(SettingKey.driveSyncAt).asyncMap((_) async {
        final point = await readSyncPoint();
        return point == null
            ? null
            : (at: point.at, direction: point.direction);
      });

  /// Records [point] as the last common point. The old one is cleared
  /// first, so an interrupted write leaves no point rather than a mixed one.
  Future<void> writeSyncPoint(SyncPoint point) async {
    await clearSyncPoint();
    await write(SettingKey.driveSyncAccount, point.account);
    await write(SettingKey.driveSyncLocalStamp, point.localStamp);
    await write(SettingKey.driveSyncUploadId, point.uploadId);
    await write(SettingKey.driveSyncDirection, point.direction.code);
    // Written last: watchSyncPointSummary listens to it.
    await write(SettingKey.driveSyncAt, point.at.toUtc().toIso8601String());
  }

  /// Forgets the last common point (account change, unlink).
  Future<void> clearSyncPoint() async {
    for (final key in SettingKey.values) {
      if (key.scope == SettingScope.syncPoint) await write(key, null);
    }
  }
}
