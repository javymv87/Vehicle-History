import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'drive_config.dart';
import 'drive_models.dart';

/// Linking failed or the account no longer authorises the app.
class DriveAuthException implements Exception {
  /// Creates the exception; [cancelled] when the user closed the dialog.
  const DriveAuthException(this.message, {this.cancelled = false});

  /// What went wrong, for the log. Never contains a token.
  final String message;

  /// The user closed the account picker or the consent screen.
  final bool cancelled;

  @override
  String toString() => 'DriveAuthException($message, cancelled: $cancelled)';
}

/// The Drive authorisation was withdrawn or never given for the linked
/// account: it must be linked again (an explicit user action).
class DriveAuthorizationRequiredException extends DriveAuthException {
  /// Creates the exception.
  const DriveAuthorizationRequiredException()
      : super('Drive access needs the user to link the account again');
}

/// Unlinking removed the link on this phone, but Google could not be told
/// to revoke the authorisation (typically no connection): the user can
/// remove it from the Google account's security settings.
class DriveRevocationFailedException implements Exception {
  /// Creates the exception.
  const DriveRevocationFailedException(this.message);

  /// What went wrong, for the log. Never contains a token.
  final String message;

  @override
  String toString() => 'DriveRevocationFailedException($message)';
}

/// Hands out short-lived access tokens with the Drive scope for a linked
/// account: all the Drive client needs.
abstract interface class DriveTokenProvider {
  /// An access token for [account] with the Drive scope, without any UI.
  ///
  /// Throws [DriveAuthorizationRequiredException] when the account no
  /// longer authorises the app.
  Future<String> accessToken(DriveAccount account);

  /// Drops [token] from the cache, after Drive refused it, so the next
  /// [accessToken] returns a fresh one.
  Future<void> invalidate(String token);
}

/// Links a Google account for the Drive copy in one of the modes of
/// `Docs/05_sync_and_storage.md` and hands out its access tokens.
///
/// Access tokens are only ever kept in memory. Mode 1 stores no token at
/// all; mode 2 stores its refresh token in the secure storage only.
abstract interface class DriveAuthService implements DriveTokenProvider {
  /// Shows the account choice and the consent screen for the Drive scope,
  /// and returns the chosen account.
  ///
  /// Throws [DriveAuthException] (with `cancelled` when the user backed
  /// out).
  Future<DriveAccount> link();

  /// Forgets the link on this phone. Throws
  /// [DriveRevocationFailedException] when the link is gone but Google
  /// could not be told.
  Future<void> unlink();
}

/// The [DriveTokenProvider] of the Drive client: hands each account's
/// token requests to the service of the mode it was linked with.
class DriveAuthRouter implements DriveTokenProvider {
  /// Creates the router over the services of each mode.
  DriveAuthRouter(this._services);

  /// The service of each mode.
  final Map<DriveAuthMode, DriveAuthService> _services;

  /// The service that handed out the last token. Only one account is
  /// linked at a time, so every token in flight comes from it.
  DriveAuthService? _issuer;

  /// The service of [mode].
  DriveAuthService _serviceOf(DriveAuthMode mode) =>
      _services[mode] ??
      (throw DriveAuthException('No service for mode ${mode.code}'));

  @override
  Future<String> accessToken(DriveAccount account) {
    final service = _serviceOf(account.mode);
    _issuer = service;
    return service.accessToken(account);
  }

  @override
  Future<void> invalidate(String token) async {
    await _issuer?.invalidate(token);
  }
}

/// Mode 1's [DriveAuthService] on `google_sign_in` 7: Credential Manager
/// for the account, the Identity `AuthorizationClient` for the Drive scope.
class GoogleDriveAuthService implements DriveAuthService {
  /// Creates the service. Stateless apart from the one-time initialisation.
  GoogleDriveAuthService();

  /// Completes once `GoogleSignIn.initialize` has run.
  Future<void>? _initialized;

  /// Initialises the plugin once, with the Web client id the Android
  /// implementation requires.
  Future<void> _ensureInitialized() => _initialized ??=
      GoogleSignIn.instance.initialize(serverClientId: driveServerClientId);

  @override
  Future<DriveAccount> link() async {
    await _ensureInitialized();
    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const [driveScope],
      );
      // Asks for consent only if the scope is not granted yet.
      await account.authorizationClient.authorizeScopes(const [driveScope]);
      return DriveAccount(account.email);
    } on GoogleSignInException catch (error) {
      throw DriveAuthException(
        'Linking failed: ${error.code.name}',
        cancelled: error.code == GoogleSignInExceptionCode.canceled,
      );
    }
  }

  @override
  Future<String> accessToken(DriveAccount account) async {
    await _ensureInitialized();
    // Straight to the platform interface: the app package only offers an
    // authorization client for an account signed in during this process,
    // which would mean an account sheet at every start. Asking by email
    // shows no UI (promptIfUnauthorized: false).
    final ClientAuthorizationTokenData? tokens;
    try {
      tokens = await GoogleSignInPlatform.instance
          .clientAuthorizationTokensForScopes(
        ClientAuthorizationTokensForScopesParameters(
          request: AuthorizationRequestDetails(
            scopes: const [driveScope],
            userId: null,
            email: account.email,
            promptIfUnauthorized: false,
          ),
        ),
      );
    } on GoogleSignInException catch (error) {
      throw DriveAuthException('Token request failed: ${error.code.name}');
    }
    if (tokens == null) throw const DriveAuthorizationRequiredException();
    return tokens.accessToken;
  }

  @override
  Future<void> invalidate(String token) async {
    await _ensureInitialized();
    await GoogleSignIn.instance.authorizationClient
        .clearAuthorizationToken(accessToken: token);
  }

  /// Signs out on this phone. The authorisation itself stays in the Google
  /// account, which is a phone account the user manages in Android.
  @override
  Future<void> unlink() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.signOut();
  }
}
