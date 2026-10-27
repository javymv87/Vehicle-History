import 'dart:async';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'drive_auth_service.dart';
import 'drive_config.dart';
import 'drive_http_client.dart';
import 'drive_models.dart';

/// A Drive request failed: no network, a server error, a refused request.
class DriveRequestException implements Exception {
  /// Creates the exception; [offline] when the phone could not reach Drive.
  const DriveRequestException(this.message, {this.offline = false});

  /// What went wrong, for the log. Never contains a token.
  final String message;

  /// The request never reached Drive (no network, DNS, timeout).
  final bool offline;

  @override
  String toString() => 'DriveRequestException($message, offline: $offline)';
}

/// Follows the progress of one upload or download.
class DriveTransfer {
  /// Creates the control; [onProgress] gets the bytes moved so far and the
  /// total.
  DriveTransfer({this.onProgress});

  /// Called as bytes move, with the bytes so far and the total.
  final void Function(int done, int total)? onProgress;
}

/// The packages in the linked account's Drive (`drive.file` scope: only
/// files this app created are visible).
///
/// Packages are found by their `appProperties` (role `backup`), never by
/// name or folder, so moving or renaming them in Drive changes nothing.
/// Uploads and downloads are streamed from and to files: a package is never
/// held in memory.
abstract interface class DriveBackupClient {
  /// The packages of [account], newest first. Reads metadata only.
  Future<List<CloudBackup>> listBackups(DriveAccount account);

  /// Uploads the package at [path] as [fileName] with [properties]
  /// (`CloudBackup.propertiesOf`), resumable, and returns it as Drive now
  /// describes it.
  Future<CloudBackup> upload(
    DriveAccount account, {
    required String path,
    required String fileName,
    required Map<String, String> properties,
    DriveTransfer? transfer,
  });

  /// Downloads [backup] to the new file [targetPath]. A failure deletes
  /// what was written.
  Future<void> download(
    DriveAccount account,
    CloudBackup backup,
    String targetPath, {
    DriveTransfer? transfer,
  });

  /// Deletes the package [fileId] for good (keeping the last copies).
  Future<void> delete(DriveAccount account, String fileId);
}

/// [DriveBackupClient] on the Drive v3 API (`googleapis`).
class GoogleDriveBackupClient implements DriveBackupClient {
  /// Creates the client; tokens come from [_auth].
  GoogleDriveBackupClient(this._auth, {http.Client Function()? httpClient})
      : _httpClient = httpClient ?? http.Client.new;

  /// Hands out the access tokens.
  final DriveTokenProvider _auth;

  /// Creates the client under the bearer-token wrapper.
  final http.Client Function() _httpClient;

  /// Bytes per chunk of a resumable upload: a multiple of 256 KB, small
  /// enough to be kept for a resend after a 401.
  static const int _chunkSize = 4 * 1024 * 1024;

  /// MIME type of a package.
  static const String _zipMimeType = 'application/zip';

  /// MIME type of a Drive folder.
  static const String _folderMimeType = 'application/vnd.google-apps.folder';

  /// Fields read for a package.
  static const String _packageFields = 'id,appProperties,createdTime,size';

  /// Runs [action] on a Drive API for [account], closing its client after
  /// and turning failures into [DriveRequestException].
  Future<T> _withApi<T>(
    DriveAccount account,
    Future<T> Function(drive.DriveApi api) action,
  ) async {
    final client = DriveHttpClient(
      _AccountTokens(_auth, account),
      inner: _httpClient(),
    );
    try {
      return await action(drive.DriveApi(client));
    } on DriveAuthException {
      rethrow;
    } on drive.DetailedApiRequestError catch (error) {
      if (error.status == 401 || error.status == 403) {
        // Still refused with a fresh token: the access was withdrawn.
        throw const DriveAuthorizationRequiredException();
      }
      throw DriveRequestException('Drive answered ${error.status}');
    } on SocketException catch (error) {
      throw DriveRequestException(
        'No connection: ${error.osError?.message}',
        offline: true,
      );
    } on http.ClientException catch (error) {
      throw DriveRequestException(
        'Connection failed: ${error.message}',
        offline: true,
      );
    } on TimeoutException {
      throw const DriveRequestException('Timed out', offline: true);
    } finally {
      client.close();
    }
  }

  @override
  Future<List<CloudBackup>> listBackups(DriveAccount account) =>
      _withApi(account, (api) async {
        final backups = <CloudBackup>[];
        String? pageToken;
        do {
          final page = await api.files.list(
            q: "appProperties has { key='${CloudBackup.roleKey}' and "
                "value='${CloudBackup.packageRole}' } and trashed = false",
            spaces: 'drive',
            orderBy: 'createdTime desc',
            pageSize: 100,
            pageToken: pageToken,
            $fields: 'nextPageToken,files($_packageFields)',
          );
          for (final file in page.files ?? const <drive.File>[]) {
            final backup = _backupOf(file);
            if (backup != null) backups.add(backup);
          }
          pageToken = page.nextPageToken;
        } while (pageToken != null);
        backups.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
        return backups;
      });

  @override
  Future<CloudBackup> upload(
    DriveAccount account, {
    required String path,
    required String fileName,
    required Map<String, String> properties,
    DriveTransfer? transfer,
  }) =>
      _withApi(account, (api) async {
        final folderId = await _folderId(api);
        final file = File(path);
        final length = await file.length();
        final created = await api.files.create(
          drive.File(
            name: fileName,
            mimeType: _zipMimeType,
            parents: [folderId],
            appProperties: properties,
          ),
          uploadMedia: drive.Media(
            _counted(file.openRead(), length, transfer),
            length,
            contentType: _zipMimeType,
          ),
          uploadOptions: drive.ResumableUploadOptions(chunkSize: _chunkSize),
          $fields: _packageFields,
        );
        final backup = _backupOf(created);
        if (backup == null) {
          throw const DriveRequestException('Upload returned no package');
        }
        return backup;
      });

  @override
  Future<void> download(
    DriveAccount account,
    CloudBackup backup,
    String targetPath, {
    DriveTransfer? transfer,
  }) =>
      _withApi(account, (api) async {
        final target = File(targetPath);
        try {
          final media = await api.files.get(
            backup.fileId,
            downloadOptions: drive.DownloadOptions.fullMedia,
          ) as drive.Media;
          final sink = target.openWrite();
          try {
            await sink.addStream(
              _counted(media.stream, backup.sizeBytes, transfer),
            );
          } finally {
            await sink.close();
          }
        } on Object {
          if (await target.exists()) await target.delete();
          rethrow;
        }
      });

  @override
  Future<void> delete(DriveAccount account, String fileId) =>
      _withApi(account, (api) => api.files.delete(fileId));

  /// The id of the app's folder, found by its role property, created when
  /// missing (first upload, or the user deleted it).
  Future<String> _folderId(drive.DriveApi api) async {
    final found = await api.files.list(
      q: "mimeType = '$_folderMimeType' and appProperties has "
          "{ key='${CloudBackup.roleKey}' and "
          "value='${CloudBackup.folderRole}' } and trashed = false",
      spaces: 'drive',
      pageSize: 1,
      $fields: 'files(id)',
    );
    final existing = found.files?.firstOrNull?.id;
    if (existing != null) return existing;
    final folder = await api.files.create(
      drive.File(
        name: driveFolderName,
        mimeType: _folderMimeType,
        appProperties: {CloudBackup.roleKey: CloudBackup.folderRole},
      ),
      $fields: 'id',
    );
    return folder.id!;
  }

  /// The package described by [file], or `null` when it is not one.
  static CloudBackup? _backupOf(drive.File file) {
    final id = file.id;
    if (id == null) return null;
    return CloudBackup.fromFile(
      fileId: id,
      properties: file.appProperties ?? const {},
      uploadedAt: file.createdTime ?? DateTime.fromMillisecondsSinceEpoch(0),
      sizeBytes: int.tryParse(file.size ?? '') ?? 0,
    );
  }

  /// [source] passed through, reporting progress to [transfer].
  static Stream<List<int>> _counted(
    Stream<List<int>> source,
    int total,
    DriveTransfer? transfer,
  ) async* {
    var done = 0;
    await for (final chunk in source) {
      done += chunk.length;
      transfer?.onProgress?.call(done, total);
      yield chunk;
    }
  }
}

/// The tokens of one account, for [DriveHttpClient].
class _AccountTokens implements AccessTokenSource {
  /// Creates the source for [_account].
  _AccountTokens(this._auth, this._account);

  /// Hands out the tokens.
  final DriveTokenProvider _auth;

  /// Whose tokens.
  final DriveAccount _account;

  @override
  Future<String> token() => _auth.accessToken(_account);

  @override
  Future<void> invalidate(String token) => _auth.invalidate(token);
}
