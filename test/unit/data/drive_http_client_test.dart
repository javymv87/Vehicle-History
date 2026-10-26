import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vehicle_history/data/drive/drive_http_client.dart';
import 'package:vehicle_history/data/drive/drive_models.dart';
import 'package:vehicle_history/data/models/backup_manifest.dart';

/// The bearer-token client under the Drive API: renewal and resend on 401,
/// including a chunk in the middle of a resumable upload.
void main() {
  late _Tokens tokens;
  late _Server server;
  late DriveHttpClient client;

  setUp(() {
    tokens = _Tokens();
    server = _Server();
    client = DriveHttpClient(tokens, inner: server, maxReplayableBytes: 64);
  });

  test('adds the bearer token', () async {
    final response = await client.get(Uri.parse('https://drive.test/files'));
    expect(response.statusCode, 200);
    expect(server.seen.single.auth, 'Bearer token-1');
  });

  test('on 401 renews the token and sends the request once more', () async {
    server.expiredTokens.add('token-1');
    final response = await client.get(Uri.parse('https://drive.test/files'));
    expect(response.statusCode, 200);
    expect(tokens.invalidated, ['token-1']);
    expect(
      server.seen.map((r) => r.auth),
      ['Bearer token-1', 'Bearer token-2'],
    );
  });

  test('a chunk of a resumable upload is resent with its body', () async {
    // The token expires in the middle of the upload: the second chunk gets
    // a 401 and must go again, whole.
    final first = http.StreamedRequest('PUT', Uri.parse('https://up.test/s'))
      ..headers['content-range'] = 'bytes 0-3/8'
      ..contentLength = 4;
    first.sink
      ..add([1, 2, 3, 4])
      ..close();
    expect((await client.send(first)).statusCode, 200);

    server.expiredTokens.add('token-2');
    final second = http.StreamedRequest('PUT', Uri.parse('https://up.test/s'))
      ..headers['content-range'] = 'bytes 4-7/8'
      ..contentLength = 4;
    second.sink
      ..add([5, 6, 7, 8])
      ..close();
    final response = await client.send(second);
    expect(response.statusCode, 200);
    expect(server.seen.map((r) => r.body), [
      [1, 2, 3, 4],
      [5, 6, 7, 8],
      [5, 6, 7, 8],
    ]);
    expect(server.seen.last.headers['content-range'], 'bytes 4-7/8');
    expect(server.seen.last.auth, 'Bearer token-3');
  });

  test('a body above the limit is streamed and a 401 returned as is', () async {
    server.expiredTokens.add('token-1');
    final big = http.StreamedRequest('PUT', Uri.parse('https://up.test/s'))
      ..contentLength = 100;
    big.sink
      ..add(List.filled(100, 7))
      ..close();
    final response = await client.send(big);
    expect(response.statusCode, 401);
    expect(server.seen, hasLength(1));
    expect(server.seen.single.body, hasLength(100));
  });

  test('a second 401 is returned, not retried forever', () async {
    server.expiredTokens.addAll(['token-1', 'token-2']);
    final response = await client.get(Uri.parse('https://drive.test/files'));
    expect(response.statusCode, 401);
    expect(server.seen, hasLength(2));
  });

  group('CloudBackup properties', () {
    const counts = BackupCounts(
      owners: 1,
      vehicles: 2,
      logEntries: 41,
      mileageReadings: 7,
      attachments: 3,
    );

    test('round-trip through Drive appProperties', () {
      final properties = CloudBackup.propertiesOf(
        uploadId: 'u1',
        stamp: '2026-10-18T12:00:00.000Z',
        schemaVersion: 7,
        appVersion: '0.9.0+10',
        deviceId: 'phone',
        counts: counts,
      );
      for (final entry in properties.entries) {
        expect(
          utf8.encode(entry.key).length + utf8.encode(entry.value).length,
          lessThanOrEqualTo(124),
          reason: 'Drive limit per property',
        );
      }
      final backup = CloudBackup.fromFile(
        fileId: 'f1',
        properties: properties,
        uploadedAt: DateTime.utc(2026, 10, 20),
        sizeBytes: 10,
      )!;
      expect(backup.uploadId, 'u1');
      expect(backup.stampInstant, DateTime.utc(2026, 10, 18, 12));
      expect(backup.schemaVersion, 7);
      expect(backup.counts, counts);
      expect(backup.deviceId, 'phone');
    });

    test('a file without the package role or a key is ignored', () {
      final properties = CloudBackup.propertiesOf(
        uploadId: 'u1',
        stamp: 'none',
        schemaVersion: 7,
        appVersion: '0.9.0+10',
        deviceId: 'phone',
        counts: counts,
      );
      CloudBackup? read(Map<String, String?> p) => CloudBackup.fromFile(
            fileId: 'f',
            properties: p,
            uploadedAt: DateTime.utc(2026),
            sizeBytes: 0,
          );
      expect(read(properties)?.stampInstant, isNull);
      expect(read({...properties, CloudBackup.roleKey: 'folder'}), isNull);
      expect(read({...properties}..remove('upload_id')), isNull);
      expect(read({...properties, 'schema_version': 'x'}), isNull);
      expect(read({...properties, 'vehicles': '-1'}), isNull);
      expect(read({...properties, 'last_modified_at': 'yesterday'}), isNull);
    });
  });
}

/// Numbered tokens, recording the invalidated ones.
class _Tokens implements AccessTokenSource {
  int _issued = 0;

  /// The tokens dropped after a 401.
  final List<String> invalidated = [];

  @override
  Future<String> token() async => 'token-${++_issued}';

  @override
  Future<void> invalidate(String token) async => invalidated.add(token);
}

/// A request as the server received it.
typedef _Seen = ({String? auth, List<int> body, Map<String, String> headers});

/// Answers 401 to the [expiredTokens], 200 otherwise.
class _Server extends http.BaseClient {
  /// The tokens refused.
  final Set<String> expiredTokens = {};

  /// Every request received.
  final List<_Seen> seen = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final auth = request.headers['authorization'];
    seen.add((auth: auth, body: body, headers: request.headers));
    final token = auth?.substring('Bearer '.length);
    final status = expiredTokens.contains(token) ? 401 : 200;
    return http.StreamedResponse(Stream.value(const []), status);
  }
}
