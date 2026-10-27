/// The Web OAuth client id of the Google Cloud project "Vehicle History",
/// which `google_sign_in` on Android needs as `serverClientId`.
///
/// Public by design (it identifies the app, it grants nothing): committed
/// here. The Android OAuth client of the same project (package name + SHA-1
/// of the fixed signing key) is what lets the phone ask for tokens; it is
/// not referenced in code. The Web client's secret is never used by the app
/// and never goes into the repository.
const String driveServerClientId =
    '724262826629-k244j3frv04i866jm0uc3f5taoh7rmm0.apps.googleusercontent.com';

/// The Android OAuth client id of the same project (package name + SHA-1 of
/// the fixed signing key), used by mode 2 (`flutter_appauth`). A public
/// client: there is no secret, and none is ever used or stored.
const String driveAndroidClientId =
    '724262826629-83b26p1jk89l4bgjtpb0dqk41h77ebfd.apps.googleusercontent.com';

/// Where the browser sends mode 2 back to the app: the reversed
/// [driveAndroidClientId] as scheme (Google's convention). Its scheme is
/// `appAuthRedirectScheme` in `android/app/build.gradle.kts`.
const String driveRedirectUrl =
    'com.googleusercontent.apps.724262826629-83b26p1jk89l4bgjtpb0dqk41h77ebfd'
    ':/oauth2redirect';

/// Google's OpenID Connect discovery document, from which `flutter_appauth`
/// reads the authorisation and token endpoints.
const String googleDiscoveryUrl =
    'https://accounts.google.com/.well-known/openid-configuration';

/// Google's token revocation endpoint, called when mode 2 is unlinked.
const String googleRevokeUrl = 'https://oauth2.googleapis.com/revoke';

/// The only Drive scope the app asks for: files the app created itself.
/// Non-sensitive, so the consent screen needs no Google verification.
const String driveScope = 'https://www.googleapis.com/auth/drive.file';

/// Name of the visible Drive folder the app creates for its packages. The
/// packages are found by their properties, not by this name, so renaming or
/// moving the folder changes nothing.
const String driveFolderName = 'Vehicle History';

/// How many packages Drive keeps: after each upload the older ones are
/// deleted, silently. A mistake uploaded once still leaves two earlier
/// copies, which can be downloaded by hand from the Drive folder.
const int driveKeptCopies = 3;
