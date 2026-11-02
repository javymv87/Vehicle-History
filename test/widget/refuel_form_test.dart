import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/refuel.dart';

import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

/// The refuel form and detail (`Docs/03_features.md`, refuel form): the
/// fields per fuel type, the amount / volume / price triangle, and what a
/// refuel means for the consumption.
void main() {
  late FakeStore store;
  late String ownerId;

  setUp(() {
    store = FakeStore();
    ownerId = store.addOwner('Mario').id;
  });

  /// A vehicle of [fuelType] at 12 345 km.
  String vehicleOf(FuelType fuelType) => store
      .addVehicle('AB123CD', ownerId: ownerId, km: 12345, fuelType: fuelType)
      .id;

  /// Scrolls [finder] into view and taps it.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Types [text] into the field with [key], as the user would.
  Future<void> type(WidgetTester tester, String key, String text) async {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.pump();
  }

  /// The text the field with [key] shows.
  String textOf(WidgetTester tester, String key) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(EditableText),
        ),
      )
      .controller
      .text;

  /// Opens a new entry form for [vehicleId] on the refuel type, at the
  /// vehicle's current km (no odometer offer after saving).
  Future<void> openRefuelForm(WidgetTester tester, String vehicleId) async {
    await pumpApp(tester, store, location: AppRoutes.newEntry(vehicleId));
    await tester.tap(find.text('Refuelling'));
    await tester.pumpAndSettle();
    await type(tester, 'entry-km-field', '12345');
  }

  /// Taps Save in the app bar.
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('petrol: amount and price give the volume, then it follows',
      (tester) async {
    final vehicleId = vehicleOf(FuelType.petrol);
    await openRefuelForm(tester, vehicleId);

    expect(find.byKey(const ValueKey('entry-fuel-choice')), findsNothing);
    expect(find.text('Amount'), findsOneWidget);
    await type(tester, 'entry-cost-field', '60');
    await type(tester, 'entry-price-field', '1.875');
    expect(textOf(tester, 'entry-volume-field'), '32');
    // Volume and price are now the last two typed: the amount follows.
    await type(tester, 'entry-volume-field', '40');
    expect(textOf(tester, 'entry-cost-field'), '75.00');

    await save(tester);
    final entry = store.entries.values.single;
    expect(entry.type, LogEntryType.refuel);
    expect(entry.costCents, 7500);
    expect(
      entry.refuel,
      const RefuelDetails(fuel: RefuelFuel.petrol, volume: 40),
    );
    expect(
      find.text(
        'Refuel saved. You will see the consumption from the next full tank.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the switches are saved: partial, after a missed refuel',
      (tester) async {
    final vehicleId = vehicleOf(FuelType.diesel);
    await openRefuelForm(tester, vehicleId);
    await type(tester, 'entry-volume-field', '20.5');
    await tapVisible(
      tester,
      find.byKey(const ValueKey('entry-full-tank-switch')),
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('entry-missed-checkbox')),
    );
    await save(tester);
    expect(
      store.entries.values.single.refuel,
      const RefuelDetails(
        fuel: RefuelFuel.diesel,
        volume: 20.5,
        fullTank: false,
        missedPrevious: true,
      ),
    );
  });

  testWidgets('bi-fuel: the fuel choice, CNG in kg', (tester) async {
    final vehicleId = vehicleOf(FuelType.petrolCng);
    await openRefuelForm(tester, vehicleId);

    expect(find.byKey(const ValueKey('entry-fuel-choice')), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
    await tapVisible(tester, find.text('CNG'));
    expect(find.text('Quantity'), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
    await type(tester, 'entry-volume-field', '12.4');
    await save(tester);
    expect(
      store.entries.values.single.refuel,
      const RefuelDetails(fuel: RefuelFuel.cng, volume: 12.4),
    );
  });

  testWidgets('an unusual price asks before saving, never blocks',
      (tester) async {
    final vehicleId = vehicleOf(FuelType.petrol);
    await openRefuelForm(tester, vehicleId);
    await type(tester, 'entry-cost-field', '100');
    await type(tester, 'entry-volume-field', '10');
    await save(tester);
    expect(find.text('Save this refuel?'), findsOneWidget);
    expect(store.entries, isEmpty);
    await tester.tap(find.text('Save anyway'));
    await tester.pumpAndSettle();
    expect(store.entries.values.single.costCents, 10000);
  });

  testWidgets('electric: a refuel is just an expense', (tester) async {
    final vehicleId = vehicleOf(FuelType.electric);
    await openRefuelForm(tester, vehicleId);

    expect(find.byKey(const ValueKey('entry-volume-field')), findsNothing);
    expect(find.byKey(const ValueKey('entry-full-tank-switch')), findsNothing);
    expect(find.text('Cost'), findsOneWidget);
    await type(tester, 'entry-cost-field', '12');
    await save(tester);
    final entry = store.entries.values.single;
    expect((entry.costCents, entry.refuel), (1200, null));
    expect(find.text('Entry saved'), findsOneWidget);
  });

  group('detail', () {
    /// Adds a refuel on day [day] of October 2026 to [vehicleId].
    String refuel(
      String vehicleId,
      int day,
      double km,
      double volume, {
      bool missed = false,
      int? cents,
    }) =>
        store
            .addEntry(
              vehicleId,
              date: CalendarDate(2026, 10, day),
              type: LogEntryType.refuel,
              km: km,
              costCents: cents,
              refuel: RefuelDetails(
                fuel: RefuelFuel.petrol,
                volume: volume,
                missedPrevious: missed,
              ),
            )
            .id;

    testWidgets('the closing refuel shows its segment', (tester) async {
      final vehicleId = vehicleOf(FuelType.petrol);
      refuel(vehicleId, 1, 10000, 40);
      final closing = refuel(vehicleId, 11, 10600, 36, cents: 6300);
      await pumpApp(
        tester,
        store,
        location: AppRoutes.entry(vehicleId, closing),
      );
      expect(find.text('€1.750/L'), findsOneWidget);
      // The consumption is below the fields: scroll to it.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('refuel-consumption')),
        200,
      );
      expect(
        find.text('6 L/100 km · 600 km in 10 days · €10.50/100 km'),
        findsOneWidget,
      );
    });

    testWidgets('a segment after a missed refuel says why it is missing',
        (tester) async {
      final vehicleId = vehicleOf(FuelType.petrol);
      refuel(vehicleId, 1, 10000, 40);
      final closing = refuel(vehicleId, 11, 10600, 36, missed: true);
      await pumpApp(
        tester,
        store,
        location: AppRoutes.entry(vehicleId, closing),
      );
      expect(
        find.text(
          'The consumption cannot be calculated: a refuel of this segment '
          'was not recorded.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a suspicious segment links to its edit form', (tester) async {
      final vehicleId = vehicleOf(FuelType.petrol);
      refuel(vehicleId, 1, 10000, 40);
      refuel(vehicleId, 2, 10500, 30);
      refuel(vehicleId, 3, 11000, 30);
      final odd = refuel(vehicleId, 4, 11500, 60);
      await pumpApp(tester, store, location: AppRoutes.entry(vehicleId, odd));
      expect(
        find.text('Consumption far from the average. Was a refuel missed?'),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('Edit refuel'));
      expect(find.text('I skipped a refuel before this one'), findsOneWidget);
    });

    testWidgets('a partial refuel says it counts in the next full tank',
        (tester) async {
      final vehicleId = vehicleOf(FuelType.petrol);
      refuel(vehicleId, 1, 10000, 40);
      final partial = store
          .addEntry(
            vehicleId,
            date: const CalendarDate(2026, 10, 5),
            type: LogEntryType.refuel,
            km: 10300,
            refuel: const RefuelDetails(
              fuel: RefuelFuel.petrol,
              volume: 15,
              fullTank: false,
            ),
          )
          .id;
      await pumpApp(
        tester,
        store,
        location: AppRoutes.entry(vehicleId, partial),
      );
      expect(
        find.text('It will count in the segment of the next full tank.'),
        findsOneWidget,
      );
    });
  });
}
