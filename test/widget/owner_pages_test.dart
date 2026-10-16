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

  group('nationality', () {
    testWidgets('searching "cub" in Spanish picks Cuba and stores its code',
        (tester) async {
      final owner = store.addOwner('Ana');
      await pumpApp(
        tester,
        store,
        location: AppRoutes.editOwner(owner.id),
        locale: const Locale('es'),
      );

      await tester.tap(find.byKey(const ValueKey('nationality-field')));
      await tester.pumpAndSettle();
      expect(find.text('Elige la nacionalidad'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Buscar'), 'cub');
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog);
      expect(
        find.descendant(of: dialog, matching: find.text('Curazao')),
        findsNothing,
      );
      await tester
          .tap(find.descendant(of: dialog, matching: find.text('Cuba')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(store.owners[owner.id]!.nationality, 'CU');
      expect(find.byType(OwnerDetailPage), findsOneWidget);
      expect(find.text('Cuba'), findsOneWidget);
    });

    testWidgets('a known code is shown in the app language', (tester) async {
      final owner = store.addOwner('Ana', nationality: 'ES');
      await pumpApp(
        tester,
        store,
        location: AppRoutes.owner(owner.id),
        locale: const Locale('it'),
      );
      expect(find.text('Spagna'), findsOneWidget);
    });

    testWidgets('free text is shown as typed', (tester) async {
      final owner = store.addOwner('Luis', nationality: 'Cubana');
      await pumpApp(tester, store, location: AppRoutes.owner(owner.id));
      expect(find.text('Cubana'), findsOneWidget);
    });

    testWidgets('"Other…" stores the typed text', (tester) async {
      final owner = store.addOwner('Ana');
      await pumpApp(tester, store, location: AppRoutes.editOwner(owner.id));

      await tester.tap(find.byKey(const ValueKey('nationality-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Kosovar',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      expect(store.owners[owner.id]!.nationality, 'Kosovar');
    });
  });

  testWidgets('About shows the data credits and opens the licences',
      (tester) async {
    await pumpApp(tester, store, location: AppRoutes.owners);

    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Vehicle data by VehiclesDB (CC BY 4.0), built from official public '
        'registers.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Unicode CLDR'), findsOneWidget);
    await tester.tap(find.text('View licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
