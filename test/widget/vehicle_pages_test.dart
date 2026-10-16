import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/features/vehicles/pages/vehicle_detail_page.dart';
import 'package:vehicle_history/features/vehicles/pages/vehicle_form_page.dart';
import 'package:vehicle_history/features/vehicles/pages/vehicle_list_page.dart';

import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

void main() {
  late FakeStore store;

  setUp(() => store = FakeStore());

  /// Picks [label] in the dropdown currently showing [current].
  Future<void> pick(WidgetTester tester, Finder field, String label) async {
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  group('smoke', () {
    testWidgets('empty vehicle list shows the empty state', (tester) async {
      await pumpApp(tester, store);

      expect(find.byType(VehicleListPage), findsOneWidget);
      expect(
        find.text('No vehicles yet. Add the first one to start its history.'),
        findsOneWidget,
      );
      // Only the FAB offers "add": the empty state never repeats it.
      expect(find.text('Add vehicle'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Add vehicle'),
          matching: find.byType(FloatingActionButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('vehicle row shows plate, nickname, owner, km and fuel',
        (tester) async {
      final owner = store.addOwner('Mario', lastName: 'Rossi');
      store.addVehicle(
        'AB123CD',
        ownerId: owner.id,
        km: 12345,
        fuelType: FuelType.diesel,
        nickname: 'Punto',
      );
      await pumpApp(tester, store);

      expect(find.text('AB123CD'), findsOneWidget);
      expect(find.text('Punto'), findsOneWidget);
      expect(find.text('Mario Rossi'), findsOneWidget);
      expect(find.text('12,345 km · Diesel'), findsOneWidget);
    });

    testWidgets('vehicle detail shows the read-only km with its note',
        (tester) async {
      final owner = store.addOwner('Mario');
      final vehicle = store.addVehicle('AB123CD', ownerId: owner.id, km: 12345);
      await pumpApp(tester, store, location: AppRoutes.vehicle(vehicle.id));

      expect(find.byType(VehicleDetailPage), findsOneWidget);
      expect(find.text('12,345 km'), findsOneWidget);
      expect(find.textContaining('odometer section'), findsOneWidget);
    });

    testWidgets('edit form has no km field', (tester) async {
      final owner = store.addOwner('Mario');
      final vehicle = store.addVehicle('AB123CD', ownerId: owner.id);
      await pumpApp(
        tester,
        store,
        location: AppRoutes.editVehicle(vehicle.id),
      );

      expect(find.byType(VehicleFormPage), findsOneWidget);
      expect(find.text('Edit vehicle'), findsOneWidget);
      expect(find.text('Current km'), findsNothing);
    });
  });

  testWidgets('required fields are validated inline', (tester) async {
    store.addOwner('Mario');
    await pumpApp(tester, store, location: AppRoutes.newVehicle);

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter the plate'), findsOneWidget);
    expect(find.text('Choose an owner'), findsOneWidget);
    expect(find.text('Choose the fuel type'), findsOneWidget);
    expect(find.text('Enter the current km'), findsOneWidget);
    expect(store.liveVehicles, isEmpty);
  });

  testWidgets(
      'creating a vehicle through "New owner" comes back with the owner '
      'selected', (tester) async {
    await pumpApp(tester, store);
    await tester.tap(find.text('Add vehicle'));
    await tester.pumpAndSettle();

    // No owner exists yet: the picker offers "New owner" directly.
    await tester.tap(find.widgetWithText(TextButton, 'New owner'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'Mario',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    // Back on the vehicle form with the new owner selected.
    expect(find.byType(VehicleFormPage), findsOneWidget);
    expect(find.text('Mario'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Plate'),
      'ab123cd',
    );
    await pick(tester, find.text('Fuel type'), 'Diesel');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current km'),
      '12345',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    final vehicle = store.liveVehicles.single;
    expect(vehicle.plate, 'AB123CD');
    expect(vehicle.ownerId, store.liveOwners.single.id);
    expect(vehicle.fuelType, FuelType.diesel);
    expect(vehicle.currentOdometerKm, 12345);
    expect(find.byType(VehicleListPage), findsOneWidget);
    expect(find.text('Vehicle saved'), findsOneWidget);
  });

  testWidgets('a duplicate plate is shown on the plate field', (tester) async {
    final owner = store.addOwner('Mario');
    store.addVehicle('AB123CD', ownerId: owner.id);
    final other = store.addVehicle('XY987ZW', ownerId: owner.id);
    await pumpApp(tester, store, location: AppRoutes.editVehicle(other.id));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Plate'),
      'ab123cd',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(VehicleFormPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Plate'),
        matching: find.text('Another vehicle already has this plate'),
      ),
      findsOneWidget,
    );
    expect(store.vehicles[other.id]!.plate, 'XY987ZW');

    // Editing the plate clears the error.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Plate'),
      'ab123cx',
    );
    await tester.pump();
    expect(find.text('Another vehicle already has this plate'), findsNothing);
  });

  testWidgets('delete asks for confirmation, then Undo restores',
      (tester) async {
    final owner = store.addOwner('Mario');
    final vehicle = store.addVehicle('AB123CD', ownerId: owner.id);
    await pumpApp(tester, store);
    await tester.tap(find.text('AB123CD'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete vehicle?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(store.liveVehicles, isEmpty);
    expect(find.text('Vehicle deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.liveVehicles, [vehicle]);
    expect(find.text('AB123CD'), findsOneWidget);
  });
}
