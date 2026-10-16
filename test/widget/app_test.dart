import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

void main() {
  // The home screen is the vehicle list. Its title and the navigation labels
  // must follow the device language.
  const cases = <String, (String, String)>{
    'it': ('Veicoli', 'Proprietari'),
    'es': ('Vehículos', 'Propietarios'),
    'en': ('Vehicles', 'Owners'),
  };

  for (final MapEntry(key: languageCode, value: (vehicles, owners))
      in cases.entries) {
    testWidgets('shows the localised home for "$languageCode"', (
      tester,
    ) async {
      await pumpApp(tester, FakeStore(), locale: Locale(languageCode));

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(vehicles),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(owners),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('a device language that is not supported falls back to English',
      (tester) async {
    await pumpApp(tester, FakeStore(), locale: const Locale('de'));
    expect(find.text('Vehicles'), findsWidgets);
  });
}
