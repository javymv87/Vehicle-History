import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';

import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

/// Every screen must fit a 360 dp wide phone with very large system text,
/// in light and dark mode. A layout overflow fails the test.
void main() {
  late FakeStore store;
  late String ownerId;
  late String vehicleId;
  late String entryId;

  setUp(() {
    store = FakeStore();
    ownerId = store
        .addOwner('Maria Antonietta', lastName: 'Fernández de la Fuente')
        .id;
    vehicleId = store
        .addVehicle(
          'AB123CD',
          ownerId: ownerId,
          km: 1234567,
          fuelType: FuelType.pluginHybrid,
          nickname: 'The family car for long trips',
          kind: VehicleKind.moped,
          make: 'Mercedes-Benz',
          makeSlug: 'mercedes-benz',
          model: 'Classe A 180 d Automatic Premium',
        )
        .id;
    entryId = store
        .addEntry(
          vehicleId,
          date: const CalendarDate(2026, 10, 19),
          type: LogEntryType.legalDue,
          km: 1234567,
          costCents: 99999999,
          description: 'Bollo auto pagato in tabaccheria con carta di credito, '
              'ricevuta conservata nel cassetto del cruscotto',
        )
        .id;
    store.addEntry(
      vehicleId,
      date: const CalendarDate(2026, 9, 1),
      type: LogEntryType.genericCheck,
    );
  });

  final locations = <String, String Function()>{
    'vehicle list': () => AppRoutes.vehicles,
    'vehicle detail': () => AppRoutes.vehicle(vehicleId),
    'vehicle form': () => AppRoutes.newVehicle,
    'vehicle edit': () => AppRoutes.editVehicle(vehicleId),
    'entry form': () => AppRoutes.newEntry(vehicleId),
    'entry detail': () => AppRoutes.entry(vehicleId, entryId),
    'entry edit': () => AppRoutes.editEntry(vehicleId, entryId),
    'owner list': () => AppRoutes.owners,
    'owner detail': () => AppRoutes.owner(ownerId),
    'owner form': () => AppRoutes.newOwner,
  };

  for (final brightness in Brightness.values) {
    for (final MapEntry(key: name, value: location) in locations.entries) {
      testWidgets('$name fits 360 dp with 2x text (${brightness.name})',
          (tester) async {
        tester.view
          ..physicalSize = const Size(360, 720)
          ..devicePixelRatio = 1;
        tester.platformDispatcher
          ..textScaleFactorTestValue = 2
          ..platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);

        await pumpApp(
          tester,
          store,
          location: location(),
          locale: const Locale('it'),
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('make picker fits 360 dp with 2x text (${brightness.name})',
        (tester) async {
      tester.view
        ..physicalSize = const Size(360, 720)
        ..devicePixelRatio = 1;
      tester.platformDispatcher
        ..textScaleFactorTestValue = 2
        ..platformBrightnessTestValue = brightness;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      await pumpApp(
        tester,
        store,
        location: AppRoutes.newVehicle,
        locale: const Locale('it'),
      );
      await tester.tap(find.byKey(const ValueKey('make-field')));
      await tester.pumpAndSettle();

      expect(find.text('Più diffuse'), findsOneWidget);
      expect(find.text('Altra marca…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'filters, active chips and details tab fit 360 dp with 2x text '
        '(${brightness.name})', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 720)
        ..devicePixelRatio = 1;
      tester.platformDispatcher
        ..textScaleFactorTestValue = 2
        ..platformBrightnessTestValue = brightness;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      await pumpApp(
        tester,
        store,
        location: AppRoutes.vehicle(vehicleId),
        locale: const Locale('it'),
      );
      await tester.tap(find.byTooltip('Filtra'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final type in ['Manutenzione', 'Scadenza legale', 'Controllo']) {
        final chip = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(type),
        );
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pump();
      }
      await tester.enterText(find.byType(TextField), 'tabaccheria');
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();
      expect(find.text('Rimuovi filtri'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Scheda'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
