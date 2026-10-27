/// Where a setting belongs, which decides what an import does with it.
///
/// The whole `settings` table travels inside a backup package. Preferences
/// travel with the data; what describes this phone's link to Google Drive
/// must not, or an import would bring another device's account and last
/// common point.
enum SettingScope {
  /// Travels with the data: an import brings the package's value.
  shared,

  /// Belongs to this phone: an import keeps the phone's value.
  device,

  /// The last common point with the Drive copy: an import clears it, since
  /// the local data are no longer those of that point. A Drive download
  /// records the new point once the import has succeeded.
  syncPoint,
}

/// A key of the `settings` table.
///
/// Stored through its explicit [code], never through `Enum.name` or the
/// index, so renaming a Dart value cannot change what is on disk.
enum SettingKey {
  /// When the last backup package was exported successfully: an instant as
  /// ISO-8601 UTC text, absent until the first export.
  lastExportAt('last_export_at'),

  /// The interface language: an `AppLanguage` code (`system`, `it`, `es`,
  /// `en`); absent means `system`.
  language('language'),

  /// The light / dark mode: an `AppThemeMode` code (`system`, `light`,
  /// `dark`); absent means `system`.
  theme('theme'),

  /// The email of the Google account the Drive copy is linked to; absent
  /// when no account is linked. Not a secret: tokens never go into this
  /// table.
  driveAccount('drive_account', SettingScope.device),

  /// How [driveAccount] was linked: a `DriveAuthMode` code (`system`,
  /// `manual`); absent means `system`. Mode 2's refresh token is in the
  /// secure storage, never here.
  driveAuthMode('drive_auth_mode', SettingScope.device),

  /// A random UUID naming this phone in the Drive copies it uploads, made
  /// on first use.
  driveDeviceId('drive_device_id', SettingScope.device),

  /// Whether the automatic Drive copy may use a metered network (mobile
  /// data): `true` or `false`; absent means `false`.
  driveMobileData('drive_mobile_data', SettingScope.device),

  /// The local version stamp (`BackupDao.lastModifiedAt`, ISO-8601 UTC, or
  /// `none` for an empty database) at the last common point; absent when
  /// there is none.
  driveSyncLocalStamp('drive_sync_local_stamp', SettingScope.syncPoint),

  /// The `upload_id` of the Drive copy at the last common point.
  driveSyncUploadId('drive_sync_upload_id', SettingScope.syncPoint),

  /// The account of the last common point, so a point recorded with
  /// another account never counts.
  driveSyncAccount('drive_sync_account', SettingScope.syncPoint),

  /// When the last common point was reached (ISO-8601 UTC).
  driveSyncAt('drive_sync_at', SettingScope.syncPoint),

  /// How it was reached: `upload` or `download`.
  driveSyncDirection('drive_sync_direction', SettingScope.syncPoint);

  const SettingKey(this.code, [this.scope = SettingScope.shared]);

  /// Text stored in `settings.key`.
  final String code;

  /// What an import does with this key.
  final SettingScope scope;
}
