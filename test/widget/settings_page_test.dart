import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/models/setting_key.dart';

import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

/// The Settings page (U21): current values, and language and theme applied
/// at once.
void main() {
  late BackupFakes fakes;

  setUp(() => fakes = BackupFakes());

  /// Pumps the app on the Settings page, the device in English.
  Future<void> pumpSettings(WidgetTester tester) async {
    await pumpApp(
      tester,
      FakeStore(),
      location: AppRoutes.settings,
      backup: fakes,
    );
  }

  /// Opens the dialog of the tile [setting] and taps [option].
  Future<void> choose(
    WidgetTester tester,
    String setting,
    String option,
  ) async {
    await tester.tap(find.text(setting));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(option),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the menu of the vehicle list opens Settings', (tester) async {
    await pumpApp(tester, FakeStore(), backup: fakes);
    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
  });

  testWidgets('shows the stored values, System when absent', (tester) async {
    fakes.settings.values[SettingKey.theme] = 'dark';
    await pumpSettings(tester);

    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Language'),
        matching: find.text('System'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Theme'),
        matching: find.text('Dark'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'the language dialog names each language in its own language, and '
      'choosing Español switches the app at once', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    for (final name in ['System', 'Italiano', 'Español', 'English']) {
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(name),
        ),
        findsOneWidget,
      );
    }
    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();

    expect(fakes.settings.values[SettingKey.language], 'es');
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Idioma'), findsOneWidget);
    expect(find.text('Español'), findsOneWidget);
  });

  testWidgets('choosing Dark changes the theme mode at once', (tester) async {
    await pumpSettings(tester);
    MaterialApp app() => tester.widget(find.byType(MaterialApp));
    expect(app().themeMode, ThemeMode.system);

    await choose(tester, 'Theme', 'Dark');

    expect(fakes.settings.values[SettingKey.theme], 'dark');
    expect(app().themeMode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.text('Theme'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('Cancel keeps the current value', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(fakes.settings.values, isEmpty);
  });
}
