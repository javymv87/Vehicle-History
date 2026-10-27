import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../repositories/repository_support.dart';
import 'drive_auth_service.dart';
import 'drive_backup_client.dart';
import 'drive_config.dart';
import 'drive_models.dart';

/// Where mode 2 keeps its refresh token: the only secret the app stores.
abstract interface class RefreshTokenStore {
  /// The stored refresh token, or `null` when there is none.
  Future<String?> read();

  /// Stores [token], replacing any previous one.
  Future<void> write(String token);

  /// Deletes the stored token, if any.
  Future<void> delete();
}

/// [RefreshTokenStore] on `flutter_secure_storage`: encrypted with a key
/// kept in the Android Keystore. Its files are excluded from Android's own
/// backup (`res/xml/backup_rules.xml`, `data_extraction_rules.xml`).
class SecureRefreshTokenStore implements RefreshTokenStore {
  /// Creates the store on [_storage].
  const SecureRefreshTokenStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  /// The plugin.
  final FlutterSecureStorage _storage;

  /// The one key the app writes.
  static const String _key = 'drive_refresh_token';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// The email claim of a Google ID token, read from its payload without a
/// network call; `null` when missing or unreadable.
///
/// The signature is not checked: the token comes straight from Google's
/// token endpoint over TLS (OpenID Connect Core 3.1.3.7), and the email is
/// only shown, never trusted for access.
String? emailFromIdToken(String? idToken) {
  final parts = idToken?.split('.');
  if (parts == null || parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final email = payload is Map<String, dynamic> ? payload['email'] : null;
    return email is String && email.isNotEmpty ? email : null;
  } on FormatException {
    return null;
  }
}

/// An access token in memory, with the instant it stops being valid.
class _AccessToken {
  /// Creates the cached token.
  const _AccessToken(this.token, this.expiresAt);

  /// The bearer token.
  final String token;

  /// When Google stops accepting it, UTC.
  final DateTime expiresAt;
}

/// Mode 2's [DriveAuthService] (`Docs/05_sync_and_storage.md`, "Modalidad
/// 2"): OAuth 2.0 Authorization Code + PKCE (S256) in the system browser
/// through `flutter_appauth`, for an account that is never added to
/// Android.
///
/// The refresh token is the only thing stored, in the [RefreshTokenStore].
/// Access tokens live in memory and are refreshed when they are about to
/// expire. Nothing secret is logged: only event names and error codes.
class ManualDriveAuthService implements DriveAuthService {
  /// Creates the service.
  ManualDriveAuthService({
    FlutterAppAuth appAuth = const FlutterAppAuth(),
    RefreshTokenStore store = const SecureRefreshTokenStore(),
    http.Client Function()? httpClient,
    UtcClock clock = systemUtcClock,
  })  : _appAuth = appAuth,
        _store = store,
        _httpClient = httpClient ?? http.Client.new,
        _clock = clock;

  final FlutterAppAuth _appAuth;
  final RefreshTokenStore _store;

  /// Creates the client of the revocation request.
  final http.Client Function() _httpClient;

  /// Source of "now" for the expiry of the access token.
  final UtcClock _clock;

  /// The scopes asked for: the email to show which account is linked, and
  /// the Drive files the app creates.
  @visibleForTesting
  static const List<String> scopes = ['openid', 'email', driveScope];

  /// A token this close to its expiry is refreshed before use.
  static const Duration _expiryMargin = Duration(minutes: 2);

  /// How long the revocation request may take.
  static const Duration _revokeTimeout = Duration(seconds: 15);

  /// The current access token, in memory only.
  _AccessToken? _cached;

  /// The refresh running now, shared by concurrent callers.
  Future<String>? _refreshing;

  /// Opens Google's sign-in page in a Custom Tab with the account chooser
  /// (`prompt=select_account`), exchanges the code with PKCE and keeps the
  /// refresh token. A previous mode 2 token (change of account) is revoked
  /// once the new one is stored.
  ///
  /// Throws [DriveAuthException] (`cancelled` when the browser was closed)
  /// or [DriveRequestException] (`offline`) when Google cannot be reached.
  @override
  Future<DriveAccount> link() async {
    final AuthorizationTokenResponse response;
    try {
      response = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          driveAndroidClientId,
          driveRedirectUrl,
          discoveryUrl: googleDiscoveryUrl,
          scopes: scopes,
          promptValues: const [Prompt.selectAccount],
        ),
      );
    } on FlutterAppAuthUserCancelledException {
      debugPrint('Drive manual auth: sign-in cancelled');
      throw const DriveAuthException('Sign-in cancelled', cancelled: true);
    } on FlutterAppAuthPlatformException catch (error) {
      throw _failureOf(error, 'Sign-in');
    } on PlatformException catch (error) {
      throw DriveAuthException('Sign-in failed: ${error.code}');
    }

    final refreshToken = response.refreshToken;
    final accessToken = response.accessToken;
    final email = emailFromIdToken(response.idToken);
    final granted = response.scopes;
    if (refreshToken == null || accessToken == null || email == null) {
      debugPrint('Drive manual auth: incomplete token response');
      throw const DriveAuthException('Incomplete token response');
    }
    if (granted != null && !granted.contains(driveScope)) {
      // Google's granular consent lets the user untick Drive.
      debugPrint('Drive manual auth: Drive access not granted');
      await _revokeQuietly(refreshToken);
      throw const DriveAuthException('Drive access not granted');
    }

    final previous = await _readStored();
    await _store.write(refreshToken);
    _cached = _AccessToken(
      accessToken,
      _expiryOf(response.accessTokenExpirationDateTime),
    );
    if (previous != null && previous != refreshToken) {
      await _revokeQuietly(previous);
    }
    debugPrint('Drive manual auth: linked');
    return DriveAccount(email, mode: DriveAuthMode.manual);
  }

  /// The cached access token, or a refreshed one.
  ///
  /// When Google refuses the refresh token (`invalid_grant`: revoked,
  /// expired, password changed) it is deleted and
  /// [DriveAuthorizationRequiredException] is thrown: the account must be
  /// linked again. No connection is a [DriveRequestException] (`offline`).
  @override
  Future<String> accessToken(DriveAccount account) {
    final cached = _cached;
    if (cached != null &&
        cached.expiresAt.isAfter(utcNow(_clock).add(_expiryMargin))) {
      return Future.value(cached.token);
    }
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  /// Asks Google for a new access token with the stored refresh token.
  Future<String> _refresh() async {
    final refreshToken = await _readStored();
    if (refreshToken == null) {
      throw const DriveAuthorizationRequiredException();
    }
    final TokenResponse response;
    try {
      response = await _appAuth.token(
        TokenRequest(
          driveAndroidClientId,
          driveRedirectUrl,
          discoveryUrl: googleDiscoveryUrl,
          refreshToken: refreshToken,
          grantType: GrantType.refreshToken,
        ),
      );
    } on FlutterAppAuthPlatformException catch (error) {
      if (error.platformErrorDetails.error ==
          FlutterAppAuthOAuthError.invalidGrant) {
        debugPrint('Drive manual auth: refresh token refused, relink needed');
        _cached = null;
        await _store.delete();
        throw const DriveAuthorizationRequiredException();
      }
      throw _failureOf(error, 'Token refresh');
    } on PlatformException catch (error) {
      throw DriveAuthException('Token refresh failed: ${error.code}');
    }

    final accessToken = response.accessToken;
    if (accessToken == null) {
      throw const DriveAuthException('Token refresh gave no access token');
    }
    // Google normally keeps the same refresh token; store a rotated one.
    final rotated = response.refreshToken;
    if (rotated != null && rotated != refreshToken) await _store.write(rotated);
    _cached = _AccessToken(
      accessToken,
      _expiryOf(response.accessTokenExpirationDateTime),
    );
    return accessToken;
  }

  @override
  Future<void> invalidate(String token) async {
    if (_cached?.token == token) _cached = null;
  }

  /// Revokes the refresh token at Google (which also revokes its access
  /// tokens), then deletes it from the secure storage **in any case**.
  ///
  /// Throws [DriveRevocationFailedException] after the deletion when Google
  /// could not be told (typically offline).
  @override
  Future<void> unlink() async {
    _cached = null;
    final refreshToken = await _readStored();
    DriveRevocationFailedException? failure;
    if (refreshToken != null) {
      try {
        await _revoke(refreshToken);
        debugPrint('Drive manual auth: revoked');
      } on DriveRevocationFailedException catch (error) {
        failure = error;
      }
    }
    await _store.delete();
    debugPrint('Drive manual auth: unlinked');
    if (failure != null) throw failure;
  }

  /// Sends [token] to Google's revocation endpoint. An `invalid_token`
  /// answer means it was already revoked, which is what was wanted.
  Future<void> _revoke(String token) async {
    final client = _httpClient();
    try {
      final response = await client.post(
        Uri.parse(googleRevokeUrl),
        headers: const {'content-type': 'application/x-www-form-urlencoded'},
        body: {'token': token},
      ).timeout(_revokeTimeout);
      if (response.statusCode == 200) return;
      if (response.statusCode == 400 &&
          response.body.contains('invalid_token')) {
        return;
      }
      throw DriveRevocationFailedException(
        'Revocation answered ${response.statusCode}',
      );
    } on SocketException {
      throw const DriveRevocationFailedException('No connection');
    } on http.ClientException {
      throw const DriveRevocationFailedException('Connection failed');
    } on TimeoutException {
      throw const DriveRevocationFailedException('Timed out');
    } finally {
      client.close();
    }
  }

  /// [_revoke], ignoring a failure: for tokens the app is dropping anyway.
  Future<void> _revokeQuietly(String token) async {
    try {
      await _revoke(token);
    } on DriveRevocationFailedException catch (error) {
      debugPrint('Drive manual auth: revocation of an old token failed: '
          '${error.message}');
    }
  }

  /// The stored refresh token; an unreadable store (its Keystore key lost)
  /// counts as none.
  Future<String?> _readStored() async {
    try {
      return await _store.read();
    } on PlatformException catch (error) {
      debugPrint('Drive manual auth: secure storage unreadable: ${error.code}');
      return null;
    }
  }

  /// The UTC expiry of an access token; Google says one hour, assumed when
  /// the answer has none.
  DateTime _expiryOf(DateTime? expiresAt) =>
      expiresAt?.toUtc() ?? utcNow(_clock).add(const Duration(hours: 1));

  /// The exception for a failed `flutter_appauth` call during [step]: no
  /// connection is [DriveRequestException] (`offline`), anything else a
  /// [DriveAuthException] carrying only the error codes.
  static Exception _failureOf(
    FlutterAppAuthPlatformException error,
    String step,
  ) {
    final details = error.platformErrorDetails;
    if (_isNetworkError(details)) {
      debugPrint('Drive manual auth: $step failed, no connection');
      return DriveRequestException('$step: no connection', offline: true);
    }
    final code = details.error ?? '${details.type}/${details.code}';
    debugPrint('Drive manual auth: $step failed ($code)');
    return DriveAuthException('$step failed: $code');
  }

  /// Whether [details] is AppAuth-Android's general network error
  /// (`AuthorizationException.GeneralErrors.NETWORK_ERROR`: type 0, code
  /// 3), raised when Google cannot be reached.
  static bool _isNetworkError(FlutterAppAuthPlatformErrorDetails details) =>
      details.type == '0' && details.code == '3';
}
