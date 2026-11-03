import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/reminder.dart';
import 'package:vehicle_history/data/models/reminder_kind.dart';
import 'package:vehicle_history/features/vehicles/controllers/vehicle_tab_controller.dart';
import 'package:vehicle_history/shared/utils/calendar_date_conversion.dart';

import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

void main() {
  late FakeStore store;
  late String vehicleId;

  /// Today on the phone: the statuses are computed against the real day.
  final today = calendarDateOf(DateTime.now());

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

  /// An engine-oil reminder done 13 months ago at 10,000 km, every
  /// 15,000 km or 12 months: overdue by date, fine by km.
  Reminder addOil({
    bool overridden = false,
  }) =>
      store.addReminder(
        Reminder(
          id: 'rem-oil',
          vehicleId: vehicleId,
          kind: ReminderKind.engineOil,
          title: 'Engine oil',
          refIntervalKm: 15000,
          refIntervalMonths: 12,
          lastDoneDate: today.addMonths(-13),
          lastDoneKm: 10000,
          overrideActive: overridden,
          appliedIntervalKm: overridden ? 80000 : null,
          overrideReason: overridden ? 'Low mileage' : null,
          overrideAt: overridden ? store.now : null,
          createdAt: store.now,
          updatedAt: store.now,
        ),
      );

  /// A coolant reminder done today, every 48 months: up to date.
  Reminder addCoolant() => store.addReminder(
        Reminder(
          id: 'rem-coolant',
          vehicleId: vehicleId,
          kind: ReminderKind.coolant,
          title: 'Coolant',
          refIntervalMonths: 48,
          lastDoneDate: today,
          createdAt: store.now,
          updatedAt: store.now,
        ),
      );

  /// Taps Save in the app bar.
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
  }

  group('Reminders page of Home', () {
    testWidgets('says where reminders are created when there are none',
        (tester) async {
      await pumpApp(tester, store, location: AppRoutes.reminders);
      expect(
        find.textContaining('Reminders tab of each vehicle'),
        findsOneWidget,
      );
      // No add button: a reminder belongs to a vehicle.
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('groups by status, names the vehicle and badges the overdue',
        (tester) async {
      addOil();
      addCoolant();
      await pumpApp(tester, store, location: AppRoutes.reminders);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Up to date'), findsOneWidget);
      expect(find.text('Engine oil'), findsOneWidget);
      expect(find.text('Coolant'), findsOneWidget);
      expect(find.text('Fiat Punto (AB123CD)'), findsNWidgets(2));
      expect(find.textContaining('Overdue by'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });
  });

  group('Reminders tab of the vehicle', () {
    testWidgets('lists the reminders with the New reminder button',
        (tester) async {
      addOil();
      await pumpApp(
        tester,
        store,
        location: AppRoutes.vehicle(vehicleId, tab: VehicleTab.reminders),
      );
      expect(find.text('Engine oil'), findsOneWidget);
      expect(
        find.widgetWithText(FloatingActionButton, 'New reminder'),
        findsOneWidget,
      );
    });
  });

  group('form', () {
    testWidgets('creates a recurring reminder from the kind picker',
        (tester) async {
      await pumpApp(
        tester,
        store,
        location: AppRoutes.newReminder(vehicleId),
      );
      await tester.tap(find.byKey(const ValueKey('reminder-kind-field')));
      await tester.pumpAndSettle();
      // Grouped, the engine first.
      expect(find.text('Engine'), findsOneWidget);
      await tester.tap(find.text('Engine oil'));
      await tester.pumpAndSettle();
      // The title is prefilled with the kind's name.
      expect(find.widgetWithText(TextFormField, 'Engine oil'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('reminder-interval-km')),
        '15000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('reminder-interval-months')),
        '12',
      );
      await save(tester);

      final saved = store.reminders.values.single;
      expect(saved.kind, ReminderKind.engineOil);
      expect(saved.title, 'Engine oil');
      expect(saved.refIntervalKm, 15000);
      expect(saved.refIntervalMonths, 12);
      expect(saved.lastDoneDate, today);
      // The anchor started from the current reading.
      expect(saved.lastDoneKm, 12345);
    });

    testWidgets('a recurring reminder needs an interval', (tester) async {
      await pumpApp(
        tester,
        store,
        location: AppRoutes.newReminder(vehicleId),
      );
      await tester.tap(find.byKey(const ValueKey('reminder-kind-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Engine oil'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(find.text('Fill in at least one interval'), findsOneWidget);
      expect(store.reminders, isEmpty);
    });
  });

  group('detail', () {
    testWidgets('shows both criteria of an override and the history',
        (tester) async {
      addOil(overridden: true);
      await pumpApp(
        tester,
        store,
        location: AppRoutes.reminder(vehicleId, 'rem-oil'),
      );
      expect(find.text('Applied criterion'), findsOneWidget);
      expect(find.text('Every 80,000 km · time off'), findsOneWidget);
      expect(find.text('Reference criterion'), findsOneWidget);
      expect(find.text('Every 15,000 km · every 12 months'), findsOneWidget);
      expect(
        find.text('The applied criterion is less strict than the reference'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('Reminder history'), 200);
      expect(find.textContaining('· Created'), findsOneWidget);
    });

    testWidgets('marks done with a new entry that closes it', (tester) async {
      addOil();
      await pumpApp(
        tester,
        store,
        location: AppRoutes.reminder(vehicleId, 'rem-oil'),
      );
      await tester.tap(find.byTooltip('Mark done'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('mark-done-km')),
        '13000',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Mark done'));
      await tester.pumpAndSettle();

      final entry = store.entries.values.single;
      expect(entry.type, LogEntryType.maintenance);
      expect(entry.km, 13000);
      expect(entry.description, 'Engine oil');
      final closed = store.reminders['rem-oil']!;
      expect(closed.lastEntryId, entry.id);
      expect(closed.lastDoneKm, 13000);
      expect(closed.lastDoneDate, today);
    });

    testWidgets('an unknown id shows the not-found page', (tester) async {
      await pumpApp(
        tester,
        store,
        location: AppRoutes.reminder(vehicleId, 'nope'),
      );
      expect(
        find.text('This reminder does not exist or was deleted.'),
        findsOneWidget,
      );
    });
  });

  group('entry form', () {
    testWidgets('a maintenance entry can close a reminder', (tester) async {
      addOil();
      await pumpApp(tester, store, location: AppRoutes.newEntry(vehicleId));
      await tester.tap(find.text('Maintenance'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('entry-km-field')),
        '13000',
      );
      final field = find.byKey(
        ValueKey('entry-closes-reminder-${LogEntryType.maintenance}'),
      );
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Engine oil').last);
      await tester.pumpAndSettle();
      await save(tester);

      final entry = store.entries.values.single;
      expect(store.reminders['rem-oil']!.lastEntryId, entry.id);
    });

    testWidgets('a refuel offers no reminder to close', (tester) async {
      addOil();
      await pumpApp(tester, store, location: AppRoutes.newEntry(vehicleId));
      await tester.tap(find.text('Refuelling'));
      await tester.pumpAndSettle();
      expect(find.text('Closes the reminder'), findsNothing);
    });

    testWidgets('the history row marks the entry that closed a reminder',
        (tester) async {
      final oil = addOil();
      final entry = store.addEntry(
        vehicleId,
        date: const CalendarDate(2026, 1, 10),
        km: 11000,
      );
      store.closeReminder(oil.id, entry);
      await pumpApp(tester, store, location: AppRoutes.vehicle(vehicleId));
      expect(find.byIcon(Icons.event_available), findsOneWidget);
    });
  });
}
