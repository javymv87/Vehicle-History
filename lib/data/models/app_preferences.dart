/// The language the user chose for the interface (setting `language`).
///
/// Stored through its explicit [code], never through `Enum.name` or the
/// index, so renaming a Dart value cannot change what is on disk.
enum AppLanguage {
  /// Follow the device language, with English as the fallback.
  system('system'),

  /// Italian.
  italian('it'),

  /// Spanish.
  spanish('es'),

  /// English.
  english('en');

  const AppLanguage(this.code);

  /// Text stored as the value of the `language` setting.
  final String code;

  /// The language code to show the app in, or `null` for [system].
  String? get languageCode => this == system ? null : code;

  /// The value stored as [code]; an absent or unknown value is [system], so
  /// a row written by a newer app version never breaks the start.
  static AppLanguage fromCode(String? code) => values.firstWhere(
        (language) => language.code == code,
        orElse: () => system,
      );
}

/// The light / dark mode the user chose (setting `theme`).
///
/// Named `AppThemeMode` because `AppTheme` already holds the two themes.
/// Stored through its explicit [code], like [AppLanguage].
enum AppThemeMode {
  /// Follow the operating system.
  system('system'),

  /// Always the light theme.
  light('light'),

  /// Always the dark theme.
  dark('dark');

  const AppThemeMode(this.code);

  /// Text stored as the value of the `theme` setting.
  final String code;

  /// The value stored as [code]; an absent or unknown value is [system].
  static AppThemeMode fromCode(String? code) => values.firstWhere(
        (mode) => mode.code == code,
        orElse: () => system,
      );
}
