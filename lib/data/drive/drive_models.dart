import '../models/backup_manifest.dart';

/// The Google account the Drive copy is linked to.
class DriveAccount {
  /// Creates the account with its [email].
  const DriveAccount(this.email);

  /// The account's email, shown as "Copy linked to: …".
  final String email;

  @override
  bool operator ==(Object other) =>
      other is DriveAccount && other.email == email;

  @override
  int get hashCode => email.hashCode;

  @override
  String toString() => 'DriveAccount($email)';
}

/// The text form of a version stamp (`BackupDao.lastModifiedAt`), as
/// recorded in the last common point and in the Drive file's properties:
/// ISO-8601 UTC, or `none` for a database with no data.
///
/// Stamps are compared as these recorded values, never as clock readings,
/// so a phone whose clock is wrong cannot make a copy look newer.
String stampCode(DateTime? stamp) =>
    stamp == null ? noStampCode : stamp.toUtc().toIso8601String();

/// [stampCode] of an empty database.
const String noStampCode = 'none';

/// The data on this phone, as the guard compares it.
class LocalSyncState {
  /// Creates the state.
  const LocalSyncState({required this.stamp, required this.counts});

  /// `BackupDao.lastModifiedAt`, or `null` for an empty database.
  final DateTime? stamp;

  /// Live owners, vehicles, entries and readings, and the number of
  /// attachment rows (live or deleted) as [BackupCounts.attachments].
  final BackupCounts counts;
}

/// One package in Drive: its file and the properties written with it, read
/// without downloading it.
class CloudBackup {
  /// Creates the description of a Drive copy.
  const CloudBackup({
    required this.fileId,
    required this.uploadId,
    required this.stamp,
    required this.schemaVersion,
    required this.appVersion,
    required this.deviceId,
    required this.counts,
    required this.uploadedAt,
    required this.sizeBytes,
  });

  /// The Drive file id.
  final String fileId;

  /// A random UUID written by the upload: two uploads never share it, so
  /// it tells whether the cloud copy changed since the last common point.
  final String uploadId;

  /// [stampCode] of the uploaded data.
  final String stamp;

  /// Drift `schemaVersion` of the uploaded database.
  final int schemaVersion;

  /// Version of the app that uploaded it.
  final String appVersion;

  /// `drive_device_id` of the phone that uploaded it.
  final String deviceId;

  /// The same figures as [LocalSyncState.counts], for the uploaded data.
  final BackupCounts counts;

  /// When the upload finished (the Drive file's creation time, UTC).
  final DateTime uploadedAt;

  /// Size of the package in bytes.
  final int sizeBytes;

  /// The stamp as an instant, or `null` for an empty database.
  DateTime? get stampInstant =>
      stamp == noStampCode ? null : DateTime.tryParse(stamp)?.toUtc();

  /// Property telling the app's packages apart from any other file.
  static const String roleKey = 'vh_role';

  /// [roleKey] value of a package.
  static const String packageRole = 'backup';

  /// [roleKey] value of the folder holding the packages.
  static const String folderRole = 'folder';

  /// The Drive `appProperties` of an upload. Each key and value stays far
  /// below Drive's 124-byte limit.
  static Map<String, String> propertiesOf({
    required String uploadId,
    required String stamp,
    required int schemaVersion,
    required String appVersion,
    required String deviceId,
    required BackupCounts counts,
  }) =>
      {
        roleKey: packageRole,
        'upload_id': uploadId,
        'last_modified_at': stamp,
        'schema_version': '$schemaVersion',
        'app_version': appVersion,
        'device_id': deviceId,
        'owners': '${counts.owners}',
        'vehicles': '${counts.vehicles}',
        'log_entries': '${counts.logEntries}',
        'mileage_readings': '${counts.mileageReadings}',
        'attachments': '${counts.attachments}',
      };

  /// Reads a copy from its Drive file: [properties] as written by
  /// [propertiesOf], or `null` when they are not those of a package (a
  /// file the app cannot read is ignored, never trusted).
  static CloudBackup? fromFile({
    required String fileId,
    required Map<String, String?> properties,
    required DateTime uploadedAt,
    required int sizeBytes,
  }) {
    int? number(String key) {
      final value = int.tryParse(properties[key] ?? '');
      return value == null || value < 0 ? null : value;
    }

    final uploadId = properties['upload_id'];
    final stamp = properties['last_modified_at'];
    final schema = number('schema_version');
    final owners = number('owners');
    final vehicles = number('vehicles');
    final entries = number('log_entries');
    final readings = number('mileage_readings');
    final attachments = number('attachments');
    if (properties[roleKey] != packageRole ||
        uploadId == null ||
        uploadId.isEmpty ||
        stamp == null ||
        (stamp != noStampCode && DateTime.tryParse(stamp) == null) ||
        schema == null ||
        owners == null ||
        vehicles == null ||
        entries == null ||
        readings == null ||
        attachments == null) {
      return null;
    }
    return CloudBackup(
      fileId: fileId,
      uploadId: uploadId,
      stamp: stamp,
      schemaVersion: schema,
      appVersion: properties['app_version'] ?? '',
      deviceId: properties['device_id'] ?? '',
      counts: BackupCounts(
        owners: owners,
        vehicles: vehicles,
        logEntries: entries,
        mileageReadings: readings,
        attachments: attachments,
      ),
      uploadedAt: uploadedAt.toUtc(),
      sizeBytes: sizeBytes,
    );
  }

  @override
  String toString() => 'CloudBackup($fileId, upload $uploadId, stamp $stamp, '
      'schema $schemaVersion, uploaded $uploadedAt)';
}

/// How the last common point was reached.
enum SyncDirection {
  /// This phone uploaded its data.
  upload('upload'),

  /// This phone downloaded the Drive copy.
  download('download');

  const SyncDirection(this.code);

  /// Text stored in `drive_sync_direction`.
  final String code;

  /// The direction stored as [code], or `null` when unknown.
  static SyncDirection? fromCode(String? code) {
    for (final direction in values) {
      if (direction.code == code) return direction;
    }
    return null;
  }
}

/// The last common point: the state of both sides after the last
/// successful upload or download.
class SyncPoint {
  /// Creates the point.
  const SyncPoint({
    required this.account,
    required this.localStamp,
    required this.uploadId,
    required this.at,
    required this.direction,
  });

  /// The account it was reached with.
  final String account;

  /// [stampCode] of the local data right after it.
  final String localStamp;

  /// [CloudBackup.uploadId] of the Drive copy at that moment.
  final String uploadId;

  /// When it was reached, UTC.
  final DateTime at;

  /// Whether it was an upload or a download.
  final SyncDirection direction;
}
