import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/features/vehicles/pages/vehicle_detail_page.dart';
import 'package:vehicle_history/features/vehicles/pages/vehicle_form_page.dart';
import 'package:vehicle_history/features/vehicles/pages/vehicle_list_page.dart';

import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

void main() {
  late FakeStore store;

  setUp(() => store = FakeStore());

  /// Scrolls [finder] into view and taps it.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Picks [label] in the dropdown [field].
  Future<void> pick(WidgetTester tester, Finder field, String label) async {
    await tapVisible(tester, field);
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// Finds [text] inside the open full-screen picker.
  Finder inPicker(String text) =>
      find.descendant(of: find.byType(Dialog), matching: find.text(text));

  /// Opens the picker behind [fieldKey], optionally searches [query], then
  /// taps [option].
  Future<void> choose(
    WidgetTester tester,
    String fieldKey,
    String option, {
    String? query,
  }) async {
    await tapVisible(tester, find.byKey(ValueKey(fieldKey)));
    if (query != null) {
      await tester.enterText(find.widgetWithText(TextField, 'Search'), query);
      await tester.pumpAndSettle();
    }
    await tester.tap(inPicker(option));
    await tester.pumpAndSettle();
  }

  /// Types [text] into the free-text dialog and confirms it.
  Future<void> typeInDialog(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      text,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
  }

  /// Fills the fields the vehicle form needs besides make and model.
  Future<void> fillRest(WidgetTester tester, {required String plate}) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Plate'), plate);
    await pick(tester, find.text('Fuel type'), 'Petrol');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current km'),
      '1000',
    );
  }

  /// Taps Save in the app bar.
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
  }

  /// The text shown by the picker field with [fieldKey], or `null`.
  String? fieldText(WidgetTester tester, String fieldKey) {
    final texts = find.descendant(
      of: find.byKey(ValueKey(fieldKey)),
      matching: find.byType(Text),
    );
    // Everything but the label and the hint is the value.
    const decorations = {'Make', 'Model', 'Choose the make first'};
    final values = [
      for (final element in texts.evaluate())
        if ((element.widget as Text).data case final data?
            when !decorations.contains(data))
          data,
    ];
    return values.isEmpty ? null : values.single;
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

    testWidgets(
        'vehicle row shows make and model, plate, nickname, owner, '
        'km and fuel', (tester) async {
      final owner = store.addOwner('Mario', lastName: 'Rossi');
      store.addVehicle(
        'AB123CD',
        ownerId: owner.id,
        km: 12345,
        fuelType: FuelType.diesel,
        nickname: 'Dad',
        make: 'Fiat',
        model: 'Punto',
      );
      await pumpApp(tester, store);

      expect(find.text('Fiat Punto'), findsOneWidget);
      expect(find.text('AB123CD'), findsOneWidget);
      expect(find.text('Dad'), findsOneWidget);
      expect(find.text('Mario Rossi'), findsOneWidget);
      expect(find.text('12,345 km · Diesel'), findsOneWidget);
    });

    testWidgets('a vehicle without make and model shows its plate first',
        (tester) async {
      final owner = store.addOwner('Mario');
      store.addVehicle('AB123CD', ownerId: owner.id);
      await pumpApp(tester, store);

      final title = tester.widget<ListTile>(find.byType(ListTile)).title;
      expect((title! as Text).data, 'AB123CD');
    });

    testWidgets('vehicle detail shows the read-only km with its note',
        (tester) async {
      final owner = store.addOwner('Mario');
      final vehicle = store.addVehicle('AB123CD', ownerId: owner.id, km: 12345);
      await pumpApp(tester, store, location: AppRoutes.vehicle(vehicle.id));

      expect(find.byType(VehicleDetailPage), findsOneWidget);
      // The header always shows the km; the history tab comes first.
      expect(find.text('12,345 km'), findsOneWidget);
      expect(find.textContaining('from the Mileage tab'), findsNothing);

      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('12,345 km'), findsNWidgets(2));
      expect(find.textContaining('from the Mileage tab'), findsOneWidget);
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

    await save(tester);

    expect(find.text('Choose the make'), findsOneWidget);
    expect(find.text('Enter the model'), findsOneWidget);
    expect(find.text('Enter the plate'), findsOneWidget);
    expect(find.text('Choose an owner'), findsOneWidget);
    expect(find.text('Choose the fuel type'), findsOneWidget);
    expect(find.text('Enter the current km'), findsOneWidget);
    expect(store.liveVehicles, isEmpty);
  });

  testWidgets('make → model → year → version saves names and slugs',
      (tester) async {
    store.addOwner('Mario');
    await pumpApp(tester, store, location: AppRoutes.newVehicle);

    // Before a make is chosen the model cannot be picked.
    expect(find.text('Choose the make first'), findsOneWidget);

    // Accent- and case-insensitive search inside the make picker.
    await choose(tester, 'make-field', 'Fiat', query: 'FI');
    await choose(tester, 'model-field', 'Punto', query: 'pun');
    await tester.enterText(find.widgetWithText(TextFormField, 'Year'), '2012');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Version / trim'),
      '1.2 69 CV Lounge',
    );
    await pick(tester, find.text('Owner'), 'Mario');
    await fillRest(tester, plate: 'ab123cd');
    await save(tester);

    final vehicle = store.liveVehicles.single;
    expect(vehicle.kind, VehicleKind.car);
    expect(vehicle.make, 'Fiat');
    expect(vehicle.makeSlug, 'fiat');
    expect(vehicle.model, 'Punto');
    expect(vehicle.modelSlug, 'punto');
    expect(vehicle.modelYear, 2012);
    expect(vehicle.version, '1.2 69 CV Lounge');
    expect(find.text('Fiat Punto'), findsOneWidget);
  });

  testWidgets('the motorcycle kind offers motorcycle makes and models',
      (tester) async {
    store.addOwner('Mario');
    await pumpApp(tester, store, location: AppRoutes.newVehicle);

    await tapVisible(tester, find.text('Motorcycle'));
    await choose(tester, 'make-field', 'Honda');
    await tapVisible(tester, find.byKey(const ValueKey('model-field')));
    // Car models of the same make are not offered.
    expect(inPicker('Civic'), findsNothing);
    await tester.tap(inPicker('SH125'));
    await tester.pumpAndSettle();
    await pick(tester, find.text('Owner'), 'Mario');
    await fillRest(tester, plate: 'AB12345');
    await save(tester);

    final vehicle = store.liveVehicles.single;
    expect(vehicle.kind, VehicleKind.motorcycle);
    expect(vehicle.makeSlug, 'honda');
    expect(vehicle.modelSlug, 'sh125');
  });

  testWidgets('"Other make…" takes free text and the model is typed too',
      (tester) async {
    store.addOwner('Mario');
    await pumpApp(tester, store, location: AppRoutes.newVehicle);

    await tapVisible(tester, find.byKey(const ValueKey('make-field')));
    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'Zast');
    await tester.pumpAndSettle();
    // Nothing matches, yet "Other make…" is still there.
    expect(
      find.text('No matches. Use the last option to type it.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Other make…'));
    await tester.pumpAndSettle();
    // The search text is offered as the starting value.
    expect(find.widgetWithText(TextField, 'Zast'), findsOneWidget);
    await typeInDialog(tester, 'Zastava');

    expect(fieldText(tester, 'make-field'), 'Zastava');
    await tester.enterText(
      find.byKey(const ValueKey('custom-model-field')),
      'Yugo 45',
    );
    await pick(tester, find.text('Owner'), 'Mario');
    await fillRest(tester, plate: 'AB123CD');
    await save(tester);

    final vehicle = store.liveVehicles.single;
    expect(vehicle.make, 'Zastava');
    expect(vehicle.makeSlug, isNull);
    expect(vehicle.model, 'Yugo 45');
    expect(vehicle.modelSlug, isNull);
  });

  testWidgets('"Other model…" keeps the catalogue make', (tester) async {
    store.addOwner('Mario');
    await pumpApp(tester, store, location: AppRoutes.newVehicle);

    await choose(tester, 'make-field', 'Fiat');
    await choose(tester, 'model-field', 'Other model…');
    await typeInDialog(tester, 'Ritmo');
    await pick(tester, find.text('Owner'), 'Mario');
    await fillRest(tester, plate: 'AB123CD');
    await save(tester);

    final vehicle = store.liveVehicles.single;
    expect(vehicle.makeSlug, 'fiat');
    expect(vehicle.model, 'Ritmo');
    expect(vehicle.modelSlug, isNull);
  });

  testWidgets(
      'changing the make clears the model, changing the kind clears '
      'both', (tester) async {
    store.addOwner('Mario');
    await pumpApp(tester, store, location: AppRoutes.newVehicle);

    await choose(tester, 'make-field', 'Fiat');
    await choose(tester, 'model-field', 'Punto');
    expect(fieldText(tester, 'model-field'), 'Punto');

    await choose(tester, 'make-field', 'Honda');
    expect(fieldText(tester, 'make-field'), 'Honda');
    expect(fieldText(tester, 'model-field'), isNull);

    await choose(tester, 'model-field', 'Civic');
    await tapVisible(tester, find.text('Van'));
    expect(fieldText(tester, 'make-field'), isNull);
    expect(fieldText(tester, 'model-field'), isNull);
  });

  testWidgets('editing a vehicle without make asks for make and model',
      (tester) async {
    final owner = store.addOwner('Mario');
    final vehicle = store.addVehicle('AB123CD', ownerId: owner.id);
    await pumpApp(tester, store, location: AppRoutes.editVehicle(vehicle.id));

    await save(tester);
    expect(find.text('Choose the make'), findsOneWidget);
    expect(find.text('Enter the model'), findsOneWidget);
    expect(store.vehicles[vehicle.id]!.make, isNull);

    await choose(tester, 'make-field', 'Fiat');
    await choose(tester, 'model-field', 'Panda');
    await save(tester);

    final saved = store.vehicles[vehicle.id]!;
    expect(saved.make, 'Fiat');
    expect(saved.model, 'Panda');
    expect(saved.plate, 'AB123CD');
  });

  testWidgets('a model year after next year is refused', (tester) async {
    final owner = store.addOwner('Mario');
    final vehicle = store.addVehicle(
      'AB123CD',
      ownerId: owner.id,
      make: 'Fiat',
      makeSlug: 'fiat',
      model: 'Punto',
      modelSlug: 'punto',
    );
    await pumpApp(tester, store, location: AppRoutes.editVehicle(vehicle.id));

    final nextYear = DateTime.now().year + 1;
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Year'),
      '${nextYear + 1}',
    );
    await save(tester);
    expect(find.text('Enter a year between 1886 and $nextYear'), findsOne);
    expect(store.vehicles[vehicle.id]!.modelYear, isNull);
  });

  testWidgets(
      'creating a vehicle through "New owner" comes back with the owner '
      'selected', (tester) async {
    await pumpApp(tester, store);
    await tester.tap(find.text('Add vehicle'));
    await tester.pumpAndSettle();

    // No owner exists yet: the picker offers "New owner" directly.
    await tapVisible(tester, find.widgetWithText(TextButton, 'New owner'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'Mario',
    );
    await save(tester);

    // Back on the vehicle form with the new owner selected.
    expect(find.byType(VehicleFormPage), findsOneWidget);
    expect(find.text('Mario'), findsOneWidget);

    await choose(tester, 'make-field', 'Fiat');
    await choose(tester, 'model-field', 'Punto');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Plate'),
      'ab123cd',
    );
    await pick(tester, find.text('Fuel type'), 'Diesel');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current km'),
      '12345',
    );
    await save(tester);

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
    final other = store.addVehicle(
      'XY987ZW',
      ownerId: owner.id,
      make: 'Fiat',
      makeSlug: 'fiat',
      model: 'Punto',
      modelSlug: 'punto',
    );
    await pumpApp(tester, store, location: AppRoutes.editVehicle(other.id));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Plate'),
      'ab123cd',
    );
    await save(tester);

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
