import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/models/setting_key.dart';
import 'package:vehicle_history/data/models/units.dart';

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

  group('units', () {
    /// The preset the segmented button shows as selected.
    Set<UnitPreset> selectedPreset(WidgetTester tester) => tester
        .widget<SegmentedButton<UnitPreset>>(
          find.byKey(const ValueKey('unit-preset')),
        )
        .selected;

    /// The subtitle of the tile [title].
    String subtitleOf(WidgetTester tester, String title) {
      final tile =
          tester.widget<ListTile>(find.widgetWithText(ListTile, title));
      return (tile.subtitle! as Text).data!;
    }

    /// Scrolls the section into view.
    Future<void> reveal(WidgetTester tester) async {
      await tester.scrollUntilVisible(find.text('Fuel consumption'), 200);
      await tester.pumpAndSettle();
    }

    testWidgets('International is selected by default, every unit SI',
        (tester) async {
      await pumpSettings(tester);
      await reveal(tester);

      expect(selectedPreset(tester), {UnitPreset.international});
      expect(subtitleOf(tester, 'Distance'), 'Kilometres (km)');
      expect(subtitleOf(tester, 'Volume'), 'Litres (L)');
      expect(subtitleOf(tester, 'Temperature'), 'Celsius (°C)');
      expect(subtitleOf(tester, 'Pressure'), 'Bar (bar)');
      expect(
        subtitleOf(tester, 'Fuel consumption'),
        'Litres per 100 km (L/100 km)',
      );
      expect(find.byKey(const ValueKey('unit-consumption-hint')), findsNothing);
    });

    testWidgets('changing one unit makes the preset Custom, and back again',
        (tester) async {
      await pumpSettings(tester);
      await reveal(tester);

      await choose(tester, 'Distance', 'Miles (mi)');
      expect(fakes.settings.values, {SettingKey.unitDistance: 'mi'});
      expect(selectedPreset(tester), {UnitPreset.custom});
      expect(subtitleOf(tester, 'Distance'), 'Miles (mi)');
      expect(subtitleOf(tester, 'Volume'), 'Litres (L)');

      await choose(tester, 'Distance', 'Kilometres (km)');
      expect(selectedPreset(tester), {UnitPreset.international});
    });

    testWidgets('a preset writes all five units at once', (tester) async {
      await pumpSettings(tester);
      await reveal(tester);

      await tester.tap(find.text('Imperial'));
      await tester.pumpAndSettle();
      expect(fakes.settings.values, {
        SettingKey.unitDistance: 'mi',
        SettingKey.unitVolume: 'gal_us',
        SettingKey.unitTemperature: 'f',
        SettingKey.unitPressure: 'psi',
        SettingKey.unitConsumption: 'mpg_us',
      });
      expect(selectedPreset(tester), {UnitPreset.imperial});
      expect(subtitleOf(tester, 'Volume'), 'US gallons (gal)');
      expect(
        subtitleOf(tester, 'Fuel consumption'),
        'Miles per US gallon (mpg)',
      );

      await tester.tap(find.text('International'));
      await tester.pumpAndSettle();
      expect(fakes.settings.values[SettingKey.unitDistance], 'km');
      expect(fakes.settings.values[SettingKey.unitConsumption], 'l_100km');
      expect(selectedPreset(tester), {UnitPreset.international});
    });

    /// Whether the Custom segment is enabled.
    bool customEnabled(WidgetTester tester) => tester
        .widget<SegmentedButton<UnitPreset>>(
          find.byKey(const ValueKey('unit-preset')),
        )
        .segments
        .singleWhere((s) => s.value == UnitPreset.custom)
        .enabled;

    testWidgets(
        'Custom shows as selected only while active, and tapping it '
        'changes nothing', (tester) async {
      fakes.settings.values[SettingKey.unitDistance] = 'mi';
      await pumpSettings(tester);
      await reveal(tester);
      expect(selectedPreset(tester), {UnitPreset.custom});
      expect(customEnabled(tester), isTrue);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      expect(fakes.settings.values, {SettingKey.unitDistance: 'mi'});
      expect(selectedPreset(tester), {UnitPreset.custom});

      await tester.tap(find.text('International'));
      await tester.pumpAndSettle();
      expect(selectedPreset(tester), {UnitPreset.international});
      expect(customEnabled(tester), isFalse);
    });

    testWidgets('a volume that disagrees with the consumption unit only hints',
        (tester) async {
      await pumpSettings(tester);
      await reveal(tester);

      await choose(tester, 'Volume', 'US gallons (gal)');
      expect(fakes.settings.values, {SettingKey.unitVolume: 'gal_us'});
      expect(
        subtitleOf(tester, 'Fuel consumption'),
        'Litres per 100 km (L/100 km)',
      );
      expect(
        find.byKey(const ValueKey('unit-consumption-hint')),
        findsOneWidget,
      );

      await choose(tester, 'Fuel consumption', 'Miles per US gallon (mpg)');
      expect(find.byKey(const ValueKey('unit-consumption-hint')), findsNothing);
    });
  });
}
