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

/// Links a Google account for the Drive copy and hands out short-lived
/// access tokens for it (mode 1 of `Docs/05_sync_and_storage.md`: the
/// phone's own accounts, through the system picker).
///
/// No token is ever stored by the app: each one is asked for when needed
/// and only kept in memory by the caller for the request it serves.
abstract interface class DriveAuthService {
  /// Shows the account picker and the consent screen for the Drive scope,
  /// and returns the chosen account.
  ///
  /// Throws [DriveAuthException] (with `cancelled` when the user backed
  /// out).
  Future<DriveAccount> link();

  /// An access token for [account] with the Drive scope, without any UI.
  ///
  /// Throws [DriveAuthorizationRequiredException] when the account no
  /// longer authorises the app.
  Future<String> accessToken(DriveAccount account);

  /// Drops [token] from the platform cache, after Drive refused it, so the
  /// next [accessToken] returns a fresh one.
  Future<void> invalidate(String token);

  /// Forgets the link on this phone (sign out). The authorisation itself
  /// can be revoked from the Google account's settings.
  Future<void> unlink();
}

/// [DriveAuthService] on `google_sign_in` 7: Credential Manager for the
/// account, the Identity `AuthorizationClient` for the Drive scope.
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

  @override
  Future<void> unlink() async {
    await _ensureInitialized();
    await GoogleSignIn.instance.signOut();
  }
}
