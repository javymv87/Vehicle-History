import 'package:vehicle_history/data/drive/drive_auth_service.dart';
import 'package:vehicle_history/data/drive/drive_backup_client.dart';
import 'package:vehicle_history/data/drive/drive_models.dart';
import 'package:vehicle_history/data/models/backup_manifest.dart';
import 'package:vehicle_history/data/platform/network_state.dart';

/// [DriveAuthService] that links [nextAccount] and hands out numbered
/// tokens, recording what it was asked.
class FakeDriveAuthService implements DriveAuthService {
  /// What the next [link] returns; `null` makes it a cancellation.
  DriveAccount? nextAccount = const DriveAccount('me@example.com');

  /// When set, [link] throws it.
  DriveAuthException? linkFailure;

  /// When set, [accessToken] throws it.
  Exception? tokenFailure;

  /// How many times [unlink] ran.
  int unlinks = 0;

  /// When set, [unlink] throws it (after counting).
  Exception? unlinkFailure;

  /// The tokens invalidated.
  final List<String> invalidated = [];

  /// Counter behind the tokens: `token-1`, `token-2`, …
  int _issued = 0;

  @override
  Future<DriveAccount> link() async {
    final failure = linkFailure;
    if (failure != null) throw failure;
    return nextAccount ??
        (throw const DriveAuthException('cancelled', cancelled: true));
  }

  @override
  Future<String> accessToken(DriveAccount account) async {
    final failure = tokenFailure;
    if (failure != null) throw failure;
    return 'token-${++_issued}';
  }

  @override
  Future<void> invalidate(String token) async => invalidated.add(token);

  @override
  Future<void> unlink() async {
    unlinks++;
    final failure = unlinkFailure;
    if (failure != null) throw failure;
  }
}

/// In-memory Drive: the packages of each account, newest first.
class FakeDriveBackupClient implements DriveBackupClient {
  /// The packages, by account email.
  final Map<String, List<CloudBackup>> files = {};

  /// When set, listing throws it.
  Exception? listFailure;

  /// When set, uploading throws it (after the listing).
  Exception? uploadFailure;

  /// When set, downloading throws it.
  Exception? downloadFailure;

  /// Runs at the start of [upload], before anything is stored: lets a test
  /// simulate another phone uploading meanwhile.
  void Function()? onUpload;

  /// How many listings ran.
  int listings = 0;

  /// The properties of each upload, in order.
  final List<Map<String, String>> uploads = [];

  /// The downloads: file id and target path.
  final List<({String fileId, String path})> downloads = [];

  /// The deleted file ids.
  final List<String> deleted = [];

  /// Upload time of the next package; one minute later each time.
  DateTime nextUploadAt = DateTime.utc(2026, 10, 20, 10);

  /// The packages of [account], newest first.
  List<CloudBackup> of(String account) => files[account] ?? [];

  /// Stores a package for [account] as another phone would have uploaded
  /// it, and returns it.
  CloudBackup put(
    String account, {
    required String uploadId,
    required String stamp,
    int schemaVersion = 7,
    BackupCounts counts = const BackupCounts(
      owners: 1,
      vehicles: 1,
      logEntries: 3,
      mileageReadings: 1,
      attachments: 0,
    ),
    String deviceId = 'other-phone',
  }) {
    final backup = CloudBackup.fromFile(
      fileId: 'file-$uploadId',
      properties: CloudBackup.propertiesOf(
        uploadId: uploadId,
        stamp: stamp,
        schemaVersion: schemaVersion,
        appVersion: '0.9.0+10',
        deviceId: deviceId,
        counts: counts,
      ),
      uploadedAt: _tick(),
      sizeBytes: 1000,
    )!;
    files.putIfAbsent(account, () => []).insert(0, backup);
    return backup;
  }

  /// The next upload time, moving the clock on.
  DateTime _tick() {
    final at = nextUploadAt;
    nextUploadAt = at.add(const Duration(minutes: 1));
    return at;
  }

  @override
  Future<List<CloudBackup>> listBackups(DriveAccount account) async {
    listings++;
    final failure = listFailure;
    if (failure != null) throw failure;
    return [...of(account.email)];
  }

  @override
  Future<CloudBackup> upload(
    DriveAccount account, {
    required String path,
    required String fileName,
    required Map<String, String> properties,
    DriveTransfer? transfer,
  }) async {
    onUpload?.call();
    final failure = uploadFailure;
    if (failure != null) throw failure;
    transfer?.onProgress?.call(500, 1000);
    transfer?.onProgress?.call(1000, 1000);
    final backup = CloudBackup.fromFile(
      fileId: 'file-${properties['upload_id']}',
      properties: properties,
      uploadedAt: _tick(),
      sizeBytes: 1000,
    )!;
    uploads.add(properties);
    files.putIfAbsent(account.email, () => []).insert(0, backup);
    return backup;
  }

  @override
  Future<void> download(
    DriveAccount account,
    CloudBackup backup,
    String targetPath, {
    DriveTransfer? transfer,
  }) async {
    final failure = downloadFailure;
    if (failure != null) throw failure;
    downloads.add((fileId: backup.fileId, path: targetPath));
  }

  @override
  Future<void> delete(DriveAccount account, String fileId) async {
    deleted.add(fileId);
    files[account.email]?.removeWhere((b) => b.fileId == fileId);
  }
}

/// [NetworkState] answering [kind].
class FakeNetworkState implements NetworkState {
  /// What [current] answers.
  NetworkKind kind = NetworkKind.unmetered;

  @override
  Future<NetworkKind> current() async => kind;
}
