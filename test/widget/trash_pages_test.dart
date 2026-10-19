import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/features/trash/pages/trash_page.dart';

import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

void main() {
  late FakeStore store;

  setUp(() => store = FakeStore());

  /// Adds a Fiat Punto of Mario with two entries and a second reading, and
  /// moves it to the Trash.
  Vehicle trashedPunto({String plate = 'AB123CD'}) {
    final owner = store.liveOwners.isEmpty
        ? store.addOwner('Mario', lastName: 'Rossi')
        : store.liveOwners.first;
    final vehicle = store.addVehicle(
      plate,
      ownerId: owner.id,
      make: 'Fiat',
      model: 'Punto',
    );
    final day = CalendarDate(store.now.year, store.now.month, store.now.day);
    store.addEntry(vehicle.id, date: day);
    store.addEntry(vehicle.id, date: day);
    store.addReading(vehicle.id, date: day, km: 1500);
    store.deletedVehicles.add(vehicle.id);
    store.vehicleDeletedAt[vehicle.id] = DateTime.now().toUtc();
    return vehicle;
  }

  testWidgets('empty Trash shows the empty state and no Empty action',
      (tester) async {
    await pumpApp(tester, store, location: AppRoutes.trash);

    expect(find.byType(TrashPage), findsOneWidget);
    expect(find.text('The Trash is empty'), findsOneWidget);
    expect(find.byTooltip('Empty Trash'), findsNothing);
  });

  testWidgets('the vehicle list menu opens the Trash, with its count',
      (tester) async {
    trashedPunto();
    await pumpApp(tester, store);

    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trash (1)'));
    await tester.pumpAndSettle();

    expect(find.byType(TrashPage), findsOneWidget);
    expect(find.text('Fiat Punto'), findsOneWidget);
    expect(find.text('AB123CD'), findsOneWidget);
    expect(find.text('Mario Rossi'), findsOneWidget);
    expect(find.textContaining('Deleted on '), findsOneWidget);
    expect(find.text('Will be removed in 30 days'), findsOneWidget);
    expect(find.text('2 entries · 2 odometer readings'), findsOneWidget);
  });

  testWidgets('Restore brings the vehicle back with its entries',
      (tester) async {
    final vehicle = trashedPunto();
    await pumpApp(tester, store, location: AppRoutes.trash);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('Vehicle restored'), findsOneWidget);
    expect(find.text('The Trash is empty'), findsOneWidget);
    expect(store.liveVehicles.single.id, vehicle.id);
    expect(store.liveEntriesOf(vehicle.id), hasLength(2));
  });

  testWidgets('a refused Restore shows the plate message', (tester) async {
    final vehicle = trashedPunto();
    store.addVehicle('AB123CD', ownerId: vehicle.ownerId);
    await pumpApp(tester, store, location: AppRoutes.trash);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('Another vehicle already has this plate'), findsOneWidget);
    expect(store.trashedVehicles.single.vehicle.id, vehicle.id);
  });

  testWidgets('Delete permanently asks first, then removes everything',
      (tester) async {
    final vehicle = trashedPunto();
    await pumpApp(tester, store, location: AppRoutes.trash);

    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    expect(
      find.text('Delete Fiat Punto (AB123CD) permanently?'),
      findsOneWidget,
    );
    expect(
      find.text(
        'The vehicle, its 2 entries and its 2 odometer readings will be '
        'deleted forever. This cannot be undone.',
      ),
      findsOneWidget,
    );

    // Cancel is the safe default: nothing happens.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.trashedVehicles, hasLength(1));

    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete permanently'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vehicle deleted permanently'), findsOneWidget);
    expect(find.text('The Trash is empty'), findsOneWidget);
    expect(store.vehicles.containsKey(vehicle.id), isFalse);
    final orphans =
        store.entries.values.where((e) => e.vehicleId == vehicle.id);
    expect(orphans, isEmpty);
  });

  testWidgets('Empty Trash confirms with the number of vehicles',
      (tester) async {
    trashedPunto();
    trashedPunto(plate: 'CD456EF');
    await pumpApp(tester, store, location: AppRoutes.trash);

    await tester.tap(find.byTooltip('Empty Trash'));
    await tester.pumpAndSettle();
    expect(find.text('Empty the Trash?'), findsOneWidget);
    expect(
      find.textContaining('The 2 vehicles in the Trash will be deleted'),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Empty Trash'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trash emptied'), findsOneWidget);
    expect(find.text('The Trash is empty'), findsOneWidget);
    expect(store.vehicles, isEmpty);
  });

  testWidgets('deleting an owner with a vehicle in the Trash is refused',
      (tester) async {
    final vehicle = trashedPunto();
    await pumpApp(
      tester,
      store,
      location: AppRoutes.owner(vehicle.ownerId),
    );

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This owner has vehicles in the Trash: restore them or empty the '
        'Trash.',
      ),
      findsOneWidget,
    );
    expect(store.liveOwners, hasLength(1));
  });
}
