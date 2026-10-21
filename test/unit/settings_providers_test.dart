import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/data_providers.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/app_preferences.dart';
import 'package:vehicle_history/data/models/setting_key.dart';
import 'package:vehicle_history/data/repositories/settings_repository.dart';
import 'package:vehicle_history/features/settings/controllers/settings_controller.dart';

import 'data/test_support.dart';

/// The providers behind `MaterialApp.locale` and `themeMode`: read once the
/// database is open, following every write and every database reopened
/// after an import.
void main() {
  late AppDatabase first;
  late AppDatabase second;
  late ProviderContainer container;

  setUp(() async {
    first = openTestDatabase();
    second = openTestDatabase();
    // The database a package import would bring: English, dark.
    await second.settingsDao
        .writeValue(SettingKey.language, 'en', DateTime.utc(2026));
    await second.settingsDao
        .writeValue(SettingKey.theme, 'dark', DateTime.utc(2026));
    final databases = [first, second];
    var opened = 0;
    container = ProviderContainer(
      overrides: [
        // Each build is a new connection, as after an import; the test
        // owns and closes both databases.
        appDatabaseProvider.overrideWith((ref) => databases[opened++]),
      ],
    );
    container
      ..listen(appLocaleProvider, (_, __) {})
      ..listen(appThemeModeProvider, (_, __) {});
  });

  tearDown(() async {
    container.dispose();
    await first.close();
    await second.close();
  });

  /// Lets the stream queries deliver their rows.
  Future<void> settle() async {
    await container.read(databaseReadyProvider.future);
    await pumpEventQueue();
  }

  test('follow the device until the database is open', () async {
    expect(container.read(appLocaleProvider), isNull);
    expect(container.read(appThemeModeProvider), ThemeMode.system);

    await settle();
    // No rows yet: still the device.
    expect(container.read(appLocaleProvider), isNull);
    expect(container.read(appThemeModeProvider), ThemeMode.system);
  });

  test('follow every write at once', () async {
    await settle();
    final controller = container.read(settingsControllerProvider.notifier);

    await controller.setLanguage(AppLanguage.spanish);
    await controller.setThemeMode(AppThemeMode.light);
    await pumpEventQueue();
    expect(container.read(appLocaleProvider), const Locale('es'));
    expect(container.read(appThemeModeProvider), ThemeMode.light);

    await controller.setLanguage(AppLanguage.system);
    await controller.setThemeMode(AppThemeMode.system);
    await pumpEventQueue();
    expect(container.read(appLocaleProvider), isNull);
    expect(container.read(appThemeModeProvider), ThemeMode.system);
  });

  test(
      'after an import they keep the old values while reopening, then '
      'follow the imported settings', () async {
    await settle();
    await container
        .read(settingsControllerProvider.notifier)
        .setLanguage(AppLanguage.italian);
    await pumpEventQueue();
    expect(container.read(appLocaleProvider), const Locale('it'));

    // What BackupController does after an import.
    container.invalidate(appDatabaseProvider);
    expect(container.read(appLocaleProvider), const Locale('it'));

    await settle();
    expect(container.read(appLocaleProvider), const Locale('en'));
    expect(container.read(appThemeModeProvider), ThemeMode.dark);

    // Writes now go to, and are read from, the new connection.
    await container
        .read(settingsControllerProvider.notifier)
        .setThemeMode(AppThemeMode.light);
    await pumpEventQueue();
    expect(container.read(appThemeModeProvider), ThemeMode.light);
    expect(await second.settingsDao.readValue(SettingKey.theme), 'light');
  });

  test('a failed read falls back to system', () async {
    final failing = ProviderContainer(
      overrides: [
        databaseReadyProvider.overrideWith((ref) async {}),
        settingsRepositoryProvider.overrideWithValue(_FailingSettings()),
      ],
    );
    addTearDown(failing.dispose);
    failing
      ..listen(appLocaleProvider, (_, __) {})
      ..listen(appThemeModeProvider, (_, __) {});
    await failing.read(databaseReadyProvider.future);
    await pumpEventQueue();

    expect(failing.read(appLocaleProvider), isNull);
    expect(failing.read(appThemeModeProvider), ThemeMode.system);
  });
}

/// Settings whose reads always fail.
class _FailingSettings implements SettingsRepository {
  @override
  Future<String?> read(SettingKey key) async => throw Exception('disk');

  @override
  Stream<String?> watch(SettingKey key) => Stream.error(Exception('disk'));

  @override
  Future<void> write(SettingKey key, String? value) async {}
}
