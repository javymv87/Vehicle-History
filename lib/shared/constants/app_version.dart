/// Version of the app, exactly as `version:` in `pubspec.yaml`
/// (`<name>+<build number>`).
///
/// Written into the manifest of every backup package. Kept by hand because
/// reading it at runtime would need another plugin; a unit test fails when
/// it differs from `pubspec.yaml`, so a version bump cannot forget it.
const String appVersion = '0.11.0+13';
