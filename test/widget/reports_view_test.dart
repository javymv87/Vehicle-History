import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/models/archive_reason.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/refuel.dart';
import 'package:vehicle_history/features/vehicles/controllers/vehicle_tab_controller.dart';

import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

/// The Reports tab (`Docs/03_features.md`, "Informes"): the filter modes,
/// the empty states, no consumption on an electric vehicle, and the same
/// reports on an archived one.
void main() {
  late FakeStore store;
  late String ownerId;

  /// Today on the phone, and [days] before it.
  final now = DateTime.now();
  final today = CalendarDate(now.year, now.month, now.day);
  CalendarDate daysAgo(int days) => today.addDays(-days);

  setUp(() {
    store = FakeStore();
    ownerId = store.addOwner('Mario').id;
  });

  /// A vehicle of [fuelType] whose initial reading is 10 000 km.
  String vehicleOf(FuelType fuelType) => store
      .addVehicle('AB123CD', ownerId: ownerId, km: 10000, fuelType: fuelType)
      .id;

  /// A full-tank petrol refuel [days] ago at [km] with [volume] litres.
  void refuel(String vehicleId, int days, double km, double volume) =>
      store.addEntry(
        vehicleId,
        date: daysAgo(days),
        type: LogEntryType.refuel,
        km: km,
        costCents: (volume * 180).round(),
        refuel: RefuelDetails(fuel: RefuelFuel.petrol, volume: volume),
      );

  /// Opens the Reports tab of [vehicleId].
  Future<void> openReports(WidgetTester tester, String vehicleId) => pumpApp(
        tester,
        store,
        location: AppRoutes.vehicle(vehicleId, tab: VehicleTab.reports),
      );

  /// Finds [text] inside the report card with [key].
  Finder inCard(String key, String text) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.text(text),
      );

  /// Scrolls the reports list until [finder] is built and visible.
  Future<void> scrollTo(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('reports-list')),
          matching: find.byType(Scrollable),
        ),
      );

  /// The text of the coverage line.
  String coverage(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('report-coverage')),
          matching: find.byType(Text),
        ),
      )
      .data!;

  testWidgets('dates: all, then 90 days', (tester) async {
    final vehicleId = vehicleOf(FuelType.petrol);
    // Segments: 200 → 150 days ago (old), 150 → 20, 20 → 10.
    refuel(vehicleId, 200, 10000, 40);
    refuel(vehicleId, 150, 10600, 36);
    refuel(vehicleId, 20, 11100, 30);
    refuel(vehicleId, 10, 11600, 30);
    store.addReading(vehicleId, date: daysAgo(10), km: 11600);
    await openReports(tester, vehicleId);

    // No add button on the read-only tab.
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(inCard('report-consumption', 'Valid segments'), findsOneWidget);
    expect(inCard('report-consumption', '3'), findsOneWidget);
    expect(
      coverage(tester),
      'Average over 1,600\u00A0km (190 days) of the 1,600\u00A0km (190 days) in the '
      'range.',
    );

    await tester.tap(find.text('90 days'));
    await tester.pumpAndSettle();
    // Only 20 → 10 lies wholly inside; 150 → 20 crosses the border.
    expect(inCard('report-consumption', '1'), findsOneWidget);
    expect(
      coverage(tester),
      'Average over 500\u00A0km (10 days) of the 500\u00A0km (10 days) in the range.',
    );
  });

  testWidgets('odometer: prefilled with the readings, then narrowed',
      (tester) async {
    final vehicleId = vehicleOf(FuelType.petrol);
    refuel(vehicleId, 30, 10000, 40);
    refuel(vehicleId, 20, 10600, 36);
    refuel(vehicleId, 10, 11100, 30);
    store.addReading(vehicleId, date: daysAgo(10), km: 11100);
    await openReports(tester, vehicleId);

    await tester.tap(find.text('Odometer'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '10000'), findsOneWidget);
    expect(find.widgetWithText(TextField, '11100'), findsOneWidget);
    expect(inCard('report-consumption', '2'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('report-km-from')),
      '10600',
    );
    await tester.pumpAndSettle();
    expect(inCard('report-consumption', '1'), findsOneWidget);
    expect(
      coverage(tester),
      'Average over 500\u00A0km (10 days) of the 500\u00A0km (10 days) in the range.',
    );
  });

  testWidgets('empty states with no refuel and the initial reading only',
      (tester) async {
    final vehicleId = vehicleOf(FuelType.diesel);
    await openReports(tester, vehicleId);

    expect(
      inCard('report-consumption', 'No consumption segment in this range.'),
      findsOneWidget,
    );
    expect(
      inCard('report-fuel-spend', 'No refuel in this range.'),
      findsOneWidget,
    );
    // One reading: no division by zero, the rates are not computed.
    await scrollTo(tester, find.byKey(const ValueKey('report-distance')));
    expect(inCard('report-distance', 'Per day'), findsOneWidget);
    expect(inCard('report-distance', '—'), findsNWidgets(2));
  });

  testWidgets('an electric vehicle has no consumption report', (tester) async {
    final vehicleId = vehicleOf(FuelType.electric);
    store.addEntry(
      vehicleId,
      date: daysAgo(5),
      type: LogEntryType.refuel,
      km: 10100,
      costCents: 1200,
    );
    await openReports(tester, vehicleId);

    expect(find.byKey(const ValueKey('report-consumption')), findsNothing);
    expect(inCard('report-fuel-spend', '€12.00'), findsOneWidget);
    expect(inCard('report-fuel-spend', 'Average price'), findsNothing);
  });

  testWidgets('an archived vehicle shows its reports, read-only',
      (tester) async {
    final vehicleId = vehicleOf(FuelType.petrol);
    refuel(vehicleId, 30, 10000, 40);
    refuel(vehicleId, 20, 10600, 36);
    store.vehicles[vehicleId] = store.vehicles[vehicleId]!.copyWith(
      archivedAt: daysAgo(1),
      archiveReason: ArchiveReason.sold,
    );
    await openReports(tester, vehicleId);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(inCard('report-consumption', 'Valid segments'), findsOneWidget);
    // A segment opens its closing refuel, with nothing to edit.
    await scrollTo(tester, find.text('Valid'));
    await tester.ensureVisible(find.text('Valid'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valid'));
    await tester.pumpAndSettle();
    expect(find.text('Refuelling'), findsWidgets);
    expect(find.byTooltip('Edit'), findsNothing);
  });
}
