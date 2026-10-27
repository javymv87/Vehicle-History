import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:vehicle_history/data/models/archive_reason.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/features/vehicles/pages/archived_vehicle_list_page.dart';
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

  /// Opens the overflow menu of the vehicle page and taps "Move to Trash".
  Future<void> moveToTrash(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();
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

  testWidgets(
      'delete confirms with what goes with the vehicle, then Undo restores',
      (tester) async {
    final owner = store.addOwner('Mario');
    final vehicle = store.addVehicle(
      'AB123CD',
      ownerId: owner.id,
      make: 'Fiat',
      model: 'Punto',
    );
    final day = CalendarDate(store.now.year, store.now.month, store.now.day);
    store.addEntry(vehicle.id, date: day);
    store.addEntry(vehicle.id, date: day);
    store.addReading(vehicle.id, date: day, km: 1500);
    await pumpApp(tester, store);
    await tester.tap(find.text('Fiat Punto'));
    await tester.pumpAndSettle();

    await moveToTrash(tester);
    // U16: name and plate in the title, live counts in the body.
    expect(find.text('Delete Fiat Punto (AB123CD)?'), findsOneWidget);
    expect(
      find.text(
        'The vehicle, its 2 entries and its 2 odometer readings will be '
        'deleted. You can recover it from the Trash for 30 days.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(store.liveVehicles, isEmpty);
    expect(store.trashedVehicles.single.vehicle.id, vehicle.id);
    expect(find.text('Vehicle deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.liveVehicles, [vehicle.copyWith(currentOdometerKm: 1500)]);
    expect(store.trashedVehicles, isEmpty);
    expect(store.liveEntriesOf(vehicle.id), hasLength(2));
    expect(store.liveReadingsOf(vehicle.id), hasLength(2));
    expect(find.text('Fiat Punto'), findsOneWidget);
  });

  testWidgets('the delete dialog uses the singular for one of each',
      (tester) async {
    final owner = store.addOwner('Mario');
    final vehicle = store.addVehicle('AB123CD', ownerId: owner.id);
    store.addEntry(
      vehicle.id,
      date: CalendarDate(store.now.year, store.now.month, store.now.day),
    );
    await pumpApp(tester, store);
    await tester.tap(find.text('AB123CD'));
    await tester.pumpAndSettle();

    await moveToTrash(tester);
    // No make and model: the plate alone names the vehicle.
    expect(find.text('Delete AB123CD?'), findsOneWidget);
    expect(
      find.textContaining('its entry and its odometer reading'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.liveVehicles, [vehicle]);
  });

  group('archive', () {
    /// Fiat Punto AB123CD of Mario, with a second reading of 1500 km.
    Vehicle addPunto() {
      final owner = store.addOwner('Mario');
      final vehicle = store.addVehicle(
        'AB123CD',
        ownerId: owner.id,
        make: 'Fiat',
        model: 'Punto',
      );
      store.addReading(
        vehicle.id,
        date: CalendarDate(store.now.year, store.now.month, store.now.day),
        km: 1500,
      );
      return store.vehicles[vehicle.id]!;
    }

    /// The phone's today, which the dialog defaults to, as the reading
    /// stores it.
    final today = DateTime.now();
    final todayDay = CalendarDate(today.year, today.month, today.day);

    /// Today as the dialog and the banner show it. Called after the app is
    /// pumped: the locale data is loaded with the localisations.
    String todayText() => DateFormat.yMMMd('en').format(today);

    /// Archives [vehicle] in the store as sold today, with 1500 final km.
    Vehicle archiveInStore(Vehicle vehicle) {
      final archived = vehicle.copyWith(
        archivedAt:
            CalendarDate(store.now.year, store.now.month, store.now.day),
        archiveReason: ArchiveReason.sold,
        archivedKm: 1500,
        archiveNote: 'To Luca',
      );
      store.vehicles[vehicle.id] = archived;
      return archived;
    }

    testWidgets('the list shows the "Archived" row only when there is one',
        (tester) async {
      final punto = addPunto();
      await pumpApp(tester, store);
      expect(find.text('Fiat Punto'), findsOneWidget);
      expect(find.textContaining('Archived ('), findsNothing);

      // Archived meanwhile (the store notifies on the next write).
      archiveInStore(punto);
      await FakeVehicleRepository(store).reactivate(punto.id);
      await FakeVehicleRepository(store).archive(
        punto.id,
        reason: ArchiveReason.sold,
        date: CalendarDate(store.now.year, store.now.month, store.now.day),
      );
      await tester.pumpAndSettle();
      // Out of the main list, into the row at the bottom.
      expect(find.text('Fiat Punto'), findsNothing);
      expect(find.text('Archived (1)'), findsOneWidget);

      await tester.tap(find.text('Archived (1)'));
      await tester.pumpAndSettle();
      expect(find.byType(ArchivedVehicleListPage), findsOneWidget);
      expect(find.text('Fiat Punto'), findsOneWidget);
      expect(find.text('Sold · Mar 2024'), findsOneWidget);
      // No add button on the archived list.
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('the archived detail shows the banner and no add or edit',
        (tester) async {
      final punto = archiveInStore(addPunto());
      await pumpApp(tester, store, location: AppRoutes.vehicle(punto.id));

      expect(find.byType(VehicleDetailPage), findsOneWidget);
      expect(
        find.text('Archived on Mar 4, 2024 · Sold · 1,500 km'),
        findsOneWidget,
      );
      expect(find.text('To Luca'), findsOneWidget);
      expect(find.text('Reactivate'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
      expect(find.byTooltip('Delete'), findsNothing);
      // The menu keeps only "Move to Trash" beside "Reactivate".
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Move to Trash'), findsOneWidget);
      expect(find.text('Archive'), findsNothing);
      await tester.tap(find.text('Move to Trash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // No FAB on any tab, and tapping a reading opens no actions.
      for (final tab in ['Mileage', 'Documents', 'Details']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(find.byType(FloatingActionButton), findsNothing);
      }
      await tester.tap(find.text('Mileage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1,500 km').first);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('Reactivate brings the vehicle back, editable', (tester) async {
      final punto = archiveInStore(addPunto());
      await pumpApp(tester, store, location: AppRoutes.vehicle(punto.id));

      await tester.tap(find.text('Reactivate'));
      await tester.pumpAndSettle();

      expect(find.text('Vehicle reactivated'), findsOneWidget);
      expect(find.textContaining('Archived on'), findsNothing);
      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      final active = store.vehicles[punto.id]!;
      expect(active.isArchived, isFalse);
      expect(active.archivedKm, isNull);
      // The readings are left alone.
      expect(store.liveReadingsOf(punto.id), hasLength(2));
    });

    testWidgets(
        'the archive dialog prefills the last km and records it as a reading',
        (tester) async {
      final punto = addPunto();
      await pumpApp(tester, store, location: AppRoutes.vehicle(punto.id));

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(find.text('Archive vehicle'), findsOneWidget);
      // Reason "None" by default, today, the last reading as the final km.
      expect(find.text('None'), findsOneWidget);
      expect(find.text(todayText()), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '1500',
      );
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sold').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Note'),
        'To Luca',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await tester.pumpAndSettle();

      expect(find.text('Vehicle archived'), findsOneWidget);
      expect(
        find.text('Archived on ${todayText()} · Sold · 1,500 km'),
        findsOneWidget,
      );
      final archived = store.vehicles[punto.id]!;
      expect(archived.archiveReason, ArchiveReason.sold);
      expect(archived.archiveNote, 'To Luca');
      expect(archived.archivedKm, 1500);
      // A third reading, equal to the last, dated today.
      final readings = store.liveReadingsOf(punto.id);
      expect(readings, hasLength(3));
      expect(readings.first.km, 1500);
      expect(readings.first.date, todayDay);
    });

    testWidgets('a final km below the last reading blocks the dialog',
        (tester) async {
      final punto = addPunto();
      await pumpApp(tester, store, location: AppRoutes.vehicle(punto.id));
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Final km'),
        '900',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await tester.pumpAndSettle();

      // The reading form's own message; the dialog stays open.
      expect(
        find.text('At least 1,500 km: the odometer never goes backwards'),
        findsOneWidget,
      );
      expect(find.text('Archive vehicle'), findsOneWidget);
      expect(store.vehicles[punto.id]!.isArchived, isFalse);
      expect(store.liveReadingsOf(punto.id), hasLength(2));

      // Empty: no reading, archived all the same.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Final km'),
        '',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await tester.pumpAndSettle();
      expect(store.vehicles[punto.id]!.isArchived, isTrue);
      expect(store.vehicles[punto.id]!.archivedKm, isNull);
      expect(store.liveReadingsOf(punto.id), hasLength(2));
      expect(find.text('Archived on ${todayText()} · None'), findsOneWidget);
    });

    testWidgets('the owner page lists archived vehicles in a collapsed section',
        (tester) async {
      final punto = archiveInStore(addPunto());
      store.addVehicle(
        'XY987ZW',
        ownerId: punto.ownerId,
        make: 'Fiat',
        model: '500',
      );
      await pumpApp(tester, store, location: AppRoutes.owner(punto.ownerId));

      expect(find.text('Fiat 500'), findsOneWidget);
      expect(find.text('Fiat Punto'), findsNothing);
      await tester.tap(find.text('Archived (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Fiat Punto'), findsOneWidget);
      expect(find.textContaining('Sold · Mar 2024'), findsOneWidget);
    });
  });
}
