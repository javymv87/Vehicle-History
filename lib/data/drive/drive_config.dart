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
