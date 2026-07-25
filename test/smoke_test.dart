import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/main.dart';

void main() {
  testWidgets('VehicleHistoryApp builds without throwing', (tester) async {
    // Pump the root application widget. If building the widget tree threw an
    // exception, `pumpWidget` would surface it and fail the test.
    await tester.pumpWidget(const VehicleHistoryApp());

    // Sanity check: the root widget is present in the tree, which confirms the
    // build completed and mounted successfully.
    expect(find.byType(VehicleHistoryApp), findsOneWidget);
  });
}
