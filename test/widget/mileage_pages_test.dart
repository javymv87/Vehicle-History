import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/features/mileage/pages/mileage_reading_form_page.dart';
import 'package:vehicle_history/features/vehicles/controllers/vehicle_tab_controller.dart';

import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

void main() {
  late FakeStore store;
  late String vehicleId;

  setUp(() {
    store = FakeStore();
    final owner = store.addOwner('Mario');
    vehicleId = store
        .addVehicle(
          'AB123CD',
          ownerId: owner.id,
          km: 12345,
          make: 'Fiat',
          model: 'Punto',
        )
        .id;
  });

  /// Opens the vehicle page on the Mileage tab.
  Future<void> openMileage(WidgetTester tester) => pumpApp(
        tester,
        store,
        location: AppRoutes.vehicle(vehicleId, tab: VehicleTab.mileage),
      );

  /// Taps Save in the app bar.
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
  }

  /// Km of the vehicle's live readings, newest first.
  List<double> readingKms() =>
      [for (final r in store.liveReadingsOf(vehicleId)) r.km];

  group('Mileage tab', () {
    testWidgets('opens from ?tab=mileage with the initial reading',
        (tester) async {
      await openMileage(tester);
      expect(find.textContaining('Initial reading'), findsOneWidget);
      // Header and row both show the km; the FAB updates it.
      expect(find.text('12,345 km'), findsOneWidget);
      expect(find.text('AB123CD · 12,345 km'), findsOneWidget);
      expect(
        find.widgetWithText(FloatingActionButton, 'Update odometer'),
        findsOneWidget,
      );
    });

    testWidgets('rows show the difference with the previous reading',
        (tester) async {
      store.addReading(
        vehicleId,
        date: const CalendarDate(2025, 1, 10),
        km: 13595,
      );
      await openMileage(tester);
      expect(find.text('13,595 km'), findsOneWidget);
      expect(find.textContaining('+1,250 km'), findsOneWidget);
      expect(find.textContaining('Initial reading'), findsOneWidget);
    });
  });

  group('Update odometer', () {
    testWidgets('a new reading appears and the header km changes',
        (tester) async {
      await openMileage(tester);
      await tester.tap(find.text('Update odometer'));
      await tester.pumpAndSettle();
      expect(find.byType(MileageReadingFormPage), findsOneWidget);
      expect(find.textContaining('Last: 12,345 km'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('reading-km-field')),
        '13000',
      );
      await save(tester);

      expect(find.byType(MileageReadingFormPage), findsNothing);
      expect(readingKms(), [13000, 12345]);
      expect(find.text('AB123CD · 13,000 km'), findsOneWidget);
      expect(find.textContaining('+655 km'), findsOneWidget);
    });

    testWidgets('a km below the last reading is blocked', (tester) async {
      await pumpApp(
        tester,
        store,
        location: AppRoutes.newMileageReading(vehicleId),
      );
      await tester.enterText(
        find.byKey(const ValueKey('reading-km-field')),
        '12000',
      );
      await save(tester);
      expect(find.textContaining('At least 12,345 km'), findsOneWidget);
      expect(readingKms(), [12345]);
    });

    testWidgets('a big jump asks first; cancel saves nothing', (tester) async {
      await pumpApp(
        tester,
        store,
        location: AppRoutes.newMileageReading(vehicleId),
      );
      await tester.enterText(
        find.byKey(const ValueKey('reading-km-field')),
        '72346',
      );
      await save(tester);
      expect(find.text('Are you sure?'), findsOneWidget);
      expect(
        find.textContaining(
          '60,001 km more than the last reading, above the 50,000 km check',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(MileageReadingFormPage), findsOneWidget);
      expect(readingKms(), [12345]);

      await save(tester);
      await tester.tap(find.text('Save anyway'));
      await tester.pumpAndSettle();
      expect(readingKms(), [72346, 12345]);
    });
  });

  group('row actions', () {
    testWidgets('delete the last reading, then Undo', (tester) async {
      store.addReading(
        vehicleId,
        date: const CalendarDate(2025, 1, 10),
        km: 13000,
      );
      await openMileage(tester);

      await tester.tap(find.text('13,000 km'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete the reading?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(readingKms(), [12345]);
      expect(find.text('AB123CD · 12,345 km'), findsOneWidget);
      expect(find.text('Reading deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(readingKms(), [13000, 12345]);
      expect(find.text('AB123CD · 13,000 km'), findsOneWidget);
    });

    testWidgets('an older reading only explains; the sole one offers Correct',
        (tester) async {
      await openMileage(tester);
      await tester.tap(find.textContaining('Initial reading'));
      await tester.pumpAndSettle();
      expect(find.text('Correct'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      store.addReading(
        vehicleId,
        date: const CalendarDate(2025, 1, 10),
        km: 13000,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Initial reading'));
      await tester.pumpAndSettle();
      expect(find.text('Correct'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.textContaining('Only the last reading'), findsOneWidget);
    });

    testWidgets('Correct changes the sole reading and the header',
        (tester) async {
      await openMileage(tester);
      await tester.tap(find.textContaining('Initial reading'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Correct'));
      await tester.pumpAndSettle();
      expect(find.text('Correct reading'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('reading-km-field')),
        '12000',
      );
      await save(tester);
      expect(readingKms(), [12000]);
      expect(find.text('AB123CD · 12,000 km'), findsOneWidget);
    });
  });

  group('entry form', () {
    /// Creates a maintenance entry with [km] through the form, dated today.
    Future<void> addMaintenance(WidgetTester tester, String km) async {
      await pumpApp(tester, store, location: AppRoutes.vehicle(vehicleId));
      await tester.tap(find.text('New entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintenance'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('entry-km-field')), km);
      await save(tester);
    }

    testWidgets('a higher km offers to update the odometer (E3)',
        (tester) async {
      await addMaintenance(tester, '13000');
      expect(store.entries, hasLength(1));
      expect(
        find.text('Entry saved. Update the odometer to 13,000 km?'),
        findsOneWidget,
      );
      // The entry alone never moves the odometer.
      expect(readingKms(), [12345]);

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(readingKms(), [13000, 12345]);
      expect(find.text('AB123CD · 13,000 km'), findsOneWidget);
      // The page switched to the Mileage tab, where the reading shows.
      expect(find.textContaining('+655 km'), findsOneWidget);
    });

    testWidgets('ignoring the offer changes nothing', (tester) async {
      await addMaintenance(tester, '13000');
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(find.textContaining('Update the odometer'), findsNothing);
      expect(readingKms(), [12345]);
      expect(find.text('AB123CD · 12,345 km'), findsOneWidget);
    });

    testWidgets('a km not above the odometer makes no offer', (tester) async {
      await addMaintenance(tester, '12345');
      expect(find.text('Entry saved'), findsOneWidget);
      expect(find.textContaining('Update the odometer'), findsNothing);
    });

    testWidgets('more km than a later reading asks first (E2)', (tester) async {
      store
        ..addReading(
          vehicleId,
          date: const CalendarDate(2025, 6, 1),
          km: 20000,
        )
        ..addReading(
          vehicleId,
          date: const CalendarDate(2025, 9, 1),
          km: 30000,
        );
      final entry = store.addEntry(
        vehicleId,
        date: const CalendarDate(2025, 5, 1),
        km: 15000,
      );
      await pumpApp(
        tester,
        store,
        location: AppRoutes.editEntry(vehicleId, entry.id),
      );
      // Below the current odometer (30,000), but above the 1 June reading.
      await tester.enterText(
        find.byKey(const ValueKey('entry-km-field')),
        '25000',
      );
      await save(tester);
      expect(find.text('Check the reading'), findsOneWidget);
      expect(
        find.textContaining('reading of Jun 1, 2025 (20,000 km)'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save anyway'));
      await tester.pumpAndSettle();
      expect(store.entries[entry.id]!.km, 25000);
    });

    testWidgets('a km that fits the readings saves without asking (E2)',
        (tester) async {
      store.addReading(
        vehicleId,
        date: const CalendarDate(2025, 6, 1),
        km: 20000,
      );
      final entry = store.addEntry(
        vehicleId,
        date: const CalendarDate(2025, 5, 1),
        km: 15000,
      );
      await pumpApp(
        tester,
        store,
        location: AppRoutes.editEntry(vehicleId, entry.id),
      );
      await tester.enterText(
        find.byKey(const ValueKey('entry-km-field')),
        '19000',
      );
      await save(tester);
      expect(find.text('Check the reading'), findsNothing);
      expect(store.entries[entry.id]!.km, 19000);
    });

    testWidgets('maintenance in the future is refused, a deadline is not (E1)',
        (tester) async {
      final future = CalendarDate.localDayOf(
        DateTime.now().add(const Duration(days: 30)),
      );
      final entry = store.addEntry(
        vehicleId,
        date: future,
        type: LogEntryType.legalDue,
        km: null,
      );
      await pumpApp(
        tester,
        store,
        location: AppRoutes.editEntry(vehicleId, entry.id),
      );
      await tester.tap(find.text('Maintenance'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('entry-km-field')),
        '12345',
      );
      await save(tester);
      expect(
        find.text('This type of entry cannot be dated in the future'),
        findsOneWidget,
      );
      expect(store.entries[entry.id]!.type, LogEntryType.legalDue);

      await tester.tap(find.text('Legal deadline'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(find.textContaining('cannot be dated'), findsNothing);
      expect(store.entries[entry.id]!.date, future);
    });
  });
}
