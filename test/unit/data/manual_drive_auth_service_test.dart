import 'dart:convert';
import 'dart:io';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vehicle_history/data/drive/drive_auth_service.dart';
import 'package:vehicle_history/data/drive/drive_backup_client.dart';
import 'package:vehicle_history/data/drive/drive_config.dart';
import 'package:vehicle_history/data/drive/drive_models.dart';
import 'package:vehicle_history/data/drive/manual_drive_auth_service.dart';

/// Mode 2 of the Drive link on a fake `flutter_appauth`, an in-memory
/// secure storage and a fake revocation endpoint: link, refresh, the
/// `invalid_grant` relink, invalidate and unlink with revocation.
void main() {
  const yade = DriveAccount('javier@example.com', mode: DriveAuthMode.manual);
  late _FakeAppAuth appAuth;
  late _MemoryStore store;
  late _RevokeEndpoint revoke;
  late DateTime now;
  late ManualDriveAuthService service;

  setUp(() {
    appAuth = _FakeAppAuth(() => now);
    store = _MemoryStore();
    revoke = _RevokeEndpoint();
    now = DateTime.utc(2026, 10, 27, 9);
    service = ManualDriveAuthService(
      appAuth: appAuth,
      store: store,
      httpClient: () => MockClient(revoke.handle),
      clock: () => now,
    );
  });

  group('link', () {
    test('stores only the refresh token and reads the email', () async {
      final account = await service.link();
      expect(account, yade);
      expect(store.value, 'refresh-1');
      final request = appAuth.authorizeRequests.single;
      expect(request.clientId, driveAndroidClientId);
      expect(request.redirectUrl, driveRedirectUrl);
      expect(request.discoveryUrl, googleDiscoveryUrl);
      expect(request.scopes, ['openid', 'email', driveScope]);
      expect(request.promptValues, ['select_account']);
      expect(request.clientSecret, isNull);
      // The access token of the sign-in is used without a refresh.
      expect(await service.accessToken(yade), 'access-1');
      expect(appAuth.tokenRequests, isEmpty);
    });

    test('closing the browser is a cancellation, nothing stored', () async {
      appAuth.authorizeFailure = _cancelled();
      await expectLater(
        service.link(),
        throwsA(
          isA<DriveAuthException>()
              .having((e) => e.cancelled, 'cancelled', true),
        ),
      );
      expect(store.value, isNull);
    });

    test('no connection is an offline Drive failure', () async {
      appAuth.authorizeFailure = _networkError();
      await expectLater(
        service.link(),
        throwsA(
          isA<DriveRequestException>()
              .having((e) => e.offline, 'offline', true),
        ),
      );
      expect(store.value, isNull);
    });

    test('Drive unticked on the consent screen: refused and revoked', () async {
      appAuth.grantedScopes = ['openid', 'email'];
      await expectLater(service.link(), throwsA(isA<DriveAuthException>()));
      expect(store.value, isNull);
      expect(revoke.tokens, ['refresh-1']);
    });

    test('changing account revokes the previous token', () async {
      await service.link();
      await service.link();
      expect(store.value, 'refresh-2');
      expect(revoke.tokens, ['refresh-1']);
    });
  });

  group('access token', () {
    test('refreshed with the stored token once it is about to expire',
        () async {
      await service.link();
      now = now.add(const Duration(minutes: 59));
      expect(await service.accessToken(yade), 'access-2');
      final request = appAuth.tokenRequests.single;
      expect(request.refreshToken, 'refresh-1');
      expect(request.grantType, GrantType.refreshToken);
      expect(request.clientId, driveAndroidClientId);
      expect(request.clientSecret, isNull);
      expect(await service.accessToken(yade), 'access-2', reason: 'cached');
      expect(appAuth.tokenRequests, hasLength(1));
    });

    test('after a restart only the stored refresh token is needed', () async {
      store.value = 'refresh-old';
      expect(await service.accessToken(yade), 'access-1');
      expect(appAuth.tokenRequests.single.refreshToken, 'refresh-old');
    });

    test('concurrent callers share one refresh', () async {
      store.value = 'refresh-old';
      final tokens = await Future.wait([
        service.accessToken(yade),
        service.accessToken(yade),
        service.accessToken(yade),
      ]);
      expect(tokens, ['access-1', 'access-1', 'access-1']);
      expect(appAuth.tokenRequests, hasLength(1));
    });

    test('invalidate drops the refused token', () async {
      await service.link();
      await service.invalidate('access-1');
      expect(await service.accessToken(yade), 'access-2');
    });

    test('invalid_grant clears the storage and asks for a relink', () async {
      await service.link();
      now = now.add(const Duration(hours: 2));
      appAuth.tokenFailure = _oauthError(FlutterAppAuthOAuthError.invalidGrant);
      await expectLater(
        service.accessToken(yade),
        throwsA(isA<DriveAuthorizationRequiredException>()),
      );
      expect(store.value, isNull);
      appAuth.tokenFailure = null;
      await expectLater(
        service.accessToken(yade),
        throwsA(isA<DriveAuthorizationRequiredException>()),
        reason: 'no token left to refresh with',
      );
    });

    test('no connection keeps the refresh token', () async {
      store.value = 'refresh-old';
      appAuth.tokenFailure = _networkError();
      await expectLater(
        service.accessToken(yade),
        throwsA(
          isA<DriveRequestException>()
              .having((e) => e.offline, 'offline', true),
        ),
      );
      expect(store.value, 'refresh-old');
    });

    test('nothing stored asks for a relink without any request', () async {
      await expectLater(
        service.accessToken(yade),
        throwsA(isA<DriveAuthorizationRequiredException>()),
      );
      expect(appAuth.tokenRequests, isEmpty);
    });
  });

  group('unlink', () {
    test('revokes the refresh token, then clears the storage', () async {
      await service.link();
      await service.unlink();
      expect(revoke.tokens, ['refresh-1']);
      expect(store.value, isNull);
      await expectLater(
        service.accessToken(yade),
        throwsA(isA<DriveAuthorizationRequiredException>()),
        reason: 'the cached access token is gone too',
      );
    });

    test('a token Google already revoked counts as revoked', () async {
      await service.link();
      revoke.status = 400;
      await service.unlink();
      expect(store.value, isNull);
    });

    test('offline: clears the storage anyway and reports it', () async {
      await service.link();
      revoke.offline = true;
      await expectLater(
        service.unlink(),
        throwsA(isA<DriveRevocationFailedException>()),
      );
      expect(store.value, isNull);
    });

    test('Google refusing the revocation is reported too', () async {
      await service.link();
      revoke.status = 503;
      await expectLater(
        service.unlink(),
        throwsA(isA<DriveRevocationFailedException>()),
      );
      expect(store.value, isNull);
    });
  });

  group('emailFromIdToken', () {
    test('reads the email claim', () {
      expect(emailFromIdToken(_idToken('a@example.com')), 'a@example.com');
    });

    test('anything unreadable gives null', () {
      expect(emailFromIdToken(null), isNull);
      expect(emailFromIdToken('not-a-jwt'), isNull);
      expect(emailFromIdToken('a.%%%.c'), isNull);
      expect(emailFromIdToken(_idToken(null)), isNull);
    });
  });
}

/// An unsigned ID token whose payload carries [email].
String _idToken(String? email) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.'
      '${part({'sub': '1', if (email != null) 'email': email})}.sig';
}

/// What AppAuth-Android reports when the user closes the browser.
FlutterAppAuthUserCancelledException _cancelled() =>
    FlutterAppAuthUserCancelledException(
      code: 'authorize_and_exchange_code_failed',
      platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
        type: '0',
        code: '1',
      ),
    );

/// AppAuth-Android's general network error.
FlutterAppAuthPlatformException _networkError() =>
    FlutterAppAuthPlatformException(
      code: 'token_failed',
      platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
        type: '0',
        code: '3',
      ),
    );

/// An OAuth error answered by Google's token endpoint.
FlutterAppAuthPlatformException _oauthError(String error) =>
    FlutterAppAuthPlatformException(
      code: 'token_failed',
      platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
        type: '2',
        code: '2002',
        error: error,
      ),
    );

/// `flutter_appauth` answering like Google: numbered tokens, recording the
/// requests.
class _FakeAppAuth implements FlutterAppAuth {
  /// Creates the fake; tokens last one hour from [_clock].
  _FakeAppAuth(this._clock);

  /// The test's clock.
  final DateTime Function() _clock;

  /// The sign-in requests.
  final List<AuthorizationTokenRequest> authorizeRequests = [];

  /// The refresh requests.
  final List<TokenRequest> tokenRequests = [];

  /// When set, the sign-in throws it.
  Exception? authorizeFailure;

  /// When set, the refresh throws it.
  Exception? tokenFailure;

  /// The scopes the sign-in reports as granted.
  List<String> grantedScopes = const ['openid', 'email', driveScope];

  int _refresh = 0;
  int _access = 0;

  @override
  Future<AuthorizationTokenResponse> authorizeAndExchangeCode(
    AuthorizationTokenRequest request,
  ) async {
    authorizeRequests.add(request);
    final failure = authorizeFailure;
    if (failure != null) throw failure;
    return AuthorizationTokenResponse(
      'access-${++_access}',
      'refresh-${++_refresh}',
      _clock().add(const Duration(hours: 1)),
      _idToken('javier@example.com'),
      'Bearer',
      grantedScopes,
      null,
      null,
    );
  }

  @override
  Future<TokenResponse> token(TokenRequest request) async {
    tokenRequests.add(request);
    final failure = tokenFailure;
    if (failure != null) throw failure;
    return TokenResponse(
      'access-${++_access}',
      null,
      _clock().add(const Duration(hours: 1)),
      null,
      'Bearer',
      null,
      null,
    );
  }

  @override
  Future<AuthorizationResponse> authorize(AuthorizationRequest request) =>
      throw UnimplementedError();

  @override
  Future<EndSessionResponse> endSession(EndSessionRequest request) =>
      throw UnimplementedError();
}

/// An in-memory [RefreshTokenStore].
class _MemoryStore implements RefreshTokenStore {
  /// The stored token.
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> delete() async => value = null;
}

/// Google's revocation endpoint.
class _RevokeEndpoint {
  /// The tokens revoked, in order.
  final List<String> tokens = [];

  /// The status to answer; 400 means "already revoked".
  int status = 200;

  /// The phone is offline.
  bool offline = false;

  Future<http.Response> handle(http.Request request) async {
    if (offline) throw const SocketException('offline');
    expect(request.url.toString(), googleRevokeUrl);
    expect(request.method, 'POST');
    if (status == 200) tokens.add(request.bodyFields['token']!);
    return http.Response(
      status == 400 ? '{"error": "invalid_token"}' : '',
      status,
    );
  }
}
