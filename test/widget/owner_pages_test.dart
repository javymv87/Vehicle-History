import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/features/owners/pages/owner_detail_page.dart';
import 'package:vehicle_history/features/owners/pages/owner_form_page.dart';
import 'package:vehicle_history/features/owners/pages/owner_list_page.dart';

import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

void main() {
  late FakeStore store;

  setUp(() => store = FakeStore());

  group('smoke', () {
    testWidgets('empty owner list shows the empty state', (tester) async {
      await pumpApp(tester, store, location: AppRoutes.owners);

      expect(find.byType(OwnerListPage), findsOneWidget);
      expect(
        find.text('No owners yet. Every vehicle belongs to an owner.'),
        findsOneWidget,
      );
      // Only the FAB offers "add": the empty state never repeats it.
      expect(find.text('Add owner'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Add owner'),
          matching: find.byType(FloatingActionButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('owner list shows the owners', (tester) async {
      store.addOwner('Mario', lastName: 'Rossi');
      await pumpApp(tester, store, location: AppRoutes.owners);

      expect(find.text('Mario Rossi'), findsOneWidget);
    });

    testWidgets('owner detail shows the owner and their vehicles',
        (tester) async {
      final owner = store.addOwner('Mario', lastName: 'Rossi');
      store.addVehicle('AB123CD', ownerId: owner.id);
      await pumpApp(tester, store, location: AppRoutes.owner(owner.id));

      expect(find.byType(OwnerDetailPage), findsOneWidget);
      expect(find.text('Rossi'), findsOneWidget);
      expect(find.text('AB123CD'), findsOneWidget);
    });

    testWidgets('owner form builds', (tester) async {
      await pumpApp(tester, store, location: AppRoutes.newOwner);

      expect(find.byType(OwnerFormPage), findsOneWidget);
      expect(find.text('New owner'), findsOneWidget);
    });
  });

  testWidgets('first name is required', (tester) async {
    await pumpApp(tester, store, location: AppRoutes.newOwner);

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter the first name'), findsOneWidget);
    expect(store.liveOwners, isEmpty);
  });

  testWidgets('an owner with vehicles cannot be deleted', (tester) async {
    final owner = store.addOwner('Mario');
    store.addVehicle('AB123CD', ownerId: owner.id);
    await pumpApp(tester, store, location: AppRoutes.owner(owner.id));

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Owner not deleted'), findsOneWidget);
    expect(find.textContaining('Nothing was deleted.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(OwnerDetailPage), findsOneWidget);
    expect(store.liveOwners, [owner]);
  });

  testWidgets('delete asks for confirmation, then Undo restores',
      (tester) async {
    final owner = store.addOwner('Mario');
    await pumpApp(tester, store, location: AppRoutes.owners);
    await tester.tap(find.text('Mario'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete owner?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(store.liveOwners, isEmpty);
    expect(find.byType(OwnerListPage), findsOneWidget);
    expect(find.text('Owner deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.liveOwners, [owner]);
    expect(find.text('Mario'), findsOneWidget);
  });
}
