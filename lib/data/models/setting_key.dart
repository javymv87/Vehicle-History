/// A key of the `settings` table.
///
/// Stored through its explicit [code], never through `Enum.name` or the
/// index, so renaming a Dart value cannot change what is on disk.
enum SettingKey {
  /// When the last backup package was exported successfully: an instant as
  /// ISO-8601 UTC text, absent until the first export.
  lastExportAt('last_export_at');

  const SettingKey(this.code);

  /// Text stored in `settings.key`.
  final String code;
}
