import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/app.dart';

void main() {
  // Each device language must produce the localised app title in the app bar.
  // "Vehicle History" is the product name and is identical in all three ARB
  // files, so a status label is checked as well to prove the locale switched.
  const cases = <String, String>{
    'it': 'Scaduto',
    'es': 'Vencido',
    'en': 'Overdue',
  };

  for (final MapEntry(key: languageCode, value: overdueLabel)
      in cases.entries) {
    testWidgets('shows the localised title for "$languageCode"', (
      tester,
    ) async {
      tester.platformDispatcher.localesTestValue = [Locale(languageCode)];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(const VehicleHistoryApp());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Vehicle History'),
        ),
        findsOneWidget,
      );
      // The overdue label appears twice: as plain text and inside the chip.
      expect(find.text(overdueLabel), findsNWidgets(2));
    });
  }
}
