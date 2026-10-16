import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/app.dart';

import 'support/fake_repositories.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('VehicleHistoryApp builds without throwing', (tester) async {
    // Pump the root application widget on fake data. If building the widget
    // tree threw an exception, `pumpWidget` would surface it and fail the
    // test.
    await pumpApp(tester, FakeStore());

    // Sanity check: the root widget is present in the tree, which confirms the
    // build completed and mounted successfully.
    expect(find.byType(VehicleHistoryApp), findsOneWidget);
  });
}
