import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/features/entries/pages/log_entry_detail_page.dart';
import 'package:vehicle_history/features/entries/pages/log_entry_form_page.dart';

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

  /// Scrolls [finder] into view and taps it.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Finds [text] inside the open bottom sheet.
  Finder inSheet(String text) =>
      find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

  /// Taps Save in the app bar.
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
  }

  /// The texts of the history list, top to bottom.
  List<String> listedTexts(WidgetTester tester) => [
        for (final element in find
            .descendant(of: find.byType(ListView), matching: find.byType(Text))
            .evaluate())
          if ((element.widget as Text).data case final data?) data,
      ];

  group('history', () {
    testWidgets('opens first, with a single add button when empty',
        (tester) async {
      await pumpApp(tester, store, location: AppRoutes.vehicle(vehicleId));

      expect(find.text('Fiat Punto'), findsOneWidget);
      expect(find.text('AB123CD · 12,345 km'), findsOneWidget);
      expect(find.textContaining('Nothing recorded yet'), findsOneWidget);
      expect(find.text('New entry'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('New entry'),
          matching: find.byType(FloatingActionButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('groups by month, newest first', (tester) async {
      store
        ..addEntry(
          vehicleId,
          date: const CalendarDate(2026, 9, 3),
          description: 'Tagliando\nseconda riga',
        )
        ..addEntry(
          vehicleId,
          date: const CalendarDate(2026, 10, 19),
          type: LogEntryType.legalDue,
          km: null,
          costCents: 21050,
        )
        ..addEntry(
          vehicleId,
          date: const CalendarDate(2026, 9, 28),
          type: LogEntryType.note,
          km: null,
        );
      await pumpApp(tester, store, location: AppRoutes.vehicle(vehicleId));

      expect(listedTexts(tester), [
        'October 2026',
        'Legal deadline',
        '€210.50',
        'Oct 19, 2026',
        'September 2026',
        'Note',
        'Sep 28, 2026',
        'Maintenance',
        'Sep 3, 2026 · 1,000 km',
        'Tagliando',
      ]);
    });

    testWidgets('month headers follow the app language', (tester) async {
      store.addEntry(vehicleId, date: const CalendarDate(2026, 10, 19));
      await pumpApp(
        tester,
        store,
        location: AppRoutes.vehicle(vehicleId),
        locale: const Locale('es'),
      );
      expect(find.text('Octubre de 2026'), findsOneWidget);
      expect(find.text('Historial'), findsOneWidget);
    });
  });

  group('form', () {
    testWidgets('quick create: type, current km chip, cost, save',
        (tester) async {
      await pumpApp(tester, store, location: AppRoutes.vehicle(vehicleId));
      await tester.tap(find.text('New entry'));
      await tester.pumpAndSettle();
      expect(find.byType(LogEntryFormPage), findsOneWidget);

      await tester.tap(find.text('Repair'));
      await tester.pumpAndSettle();
      // The km is never prefilled: only the chip fills it.
      expect(find.widgetWithText(TextFormField, '12345'), findsNothing);
      await tapVisible(tester, find.text('Use current reading (12,345 km)'));
      expect(find.widgetWithText(TextFormField, '12345'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('entry-cost-field')),
        '12.5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('entry-description-field')),
        'Frizione',
      );
      await save(tester);

      final entry = store.entries.values.single;
      expect(entry.type, LogEntryType.repair);
      expect(entry.km, 12345);
      expect(entry.costCents, 1250);
      expect(entry.description, 'Frizione');
      final now = DateTime.now();
      expect(entry.date, CalendarDate(now.year, now.month, now.day));

      // Back on the history, under the current month.
      expect(find.byType(LogEntryFormPage), findsNothing);
      expect(find.text('Entry saved'), findsOneWidget);
      expect(
        find.text(DateFormat.yMMMM('en').format(now)),
        findsOneWidget,
      );
      expect(find.text('Frizione'), findsOneWidget);
      expect(find.text('€12.50'), findsOneWidget);
    });

    testWidgets('validates type, km per type and cost', (tester) async {
      await pumpApp(tester, store, location: AppRoutes.newEntry(vehicleId));

      await save(tester);
      expect(find.text('Choose the type'), findsOneWidget);

      await tester.tap(find.text('Refuelling'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('entry-cost-field')),
        '12,505',
      );
      await save(tester);
      expect(find.text('Choose the type'), findsNothing);
      expect(
        find.text('Enter the odometer reading for this type of entry'),
        findsOneWidget,
      );
      expect(
        find.text('Enter an amount of 0 or more, with at most 2 decimals'),
        findsOneWidget,
      );
      expect(store.entries, isEmpty);

      // A legal deadline needs no km.
      await tester.tap(find.text('Legal deadline'));
      await tester.pumpAndSettle();
      expect(find.text('Odometer (optional)'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('entry-cost-field')),
        '99,9',
      );
      await save(tester);
      final entry = store.entries.values.single;
      expect(entry.type, LogEntryType.legalDue);
      expect(entry.km, isNull);
      expect(entry.costCents, 9990);
    });

    testWidgets('does not offer the measured check yet', (tester) async {
      await pumpApp(tester, store, location: AppRoutes.newEntry(vehicleId));
      expect(find.text('Measured check'), findsNothing);
      expect(find.byType(ChoiceChip), findsNWidgets(7));
    });

    testWidgets('edit keeps the values and saves the change', (tester) async {
      final entry = store.addEntry(
        vehicleId,
        date: const CalendarDate(2026, 3, 4),
        km: 11000,
        costCents: 4550,
        description: 'Old text',
      );
      await pumpApp(
        tester,
        store,
        location: AppRoutes.entry(vehicleId, entry.id),
        locale: const Locale('it'),
      );
      expect(find.byType(LogEntryDetailPage), findsOneWidget);

      await tester.tap(find.byTooltip('Modifica'));
      await tester.pumpAndSettle();
      // The cost comes back with the Italian separator.
      expect(find.widgetWithText(TextFormField, '45,50'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '11000'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('entry-description-field')),
        'New text',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Salva'));
      await tester.pumpAndSettle();

      expect(store.entries[entry.id]!.description, 'New text');
      expect(store.entries[entry.id]!.costCents, 4550);
      expect(find.byType(LogEntryDetailPage), findsOneWidget);
      expect(find.text('New text'), findsOneWidget);
    });
  });

  group('detail', () {
    testWidgets('delete asks for confirmation, then Undo restores',
        (tester) async {
      final entry = store.addEntry(
        vehicleId,
        date: const CalendarDate(2026, 10, 1),
        description: 'Gomme invernali',
      );
      await pumpApp(tester, store, location: AppRoutes.vehicle(vehicleId));
      await tester.tap(find.text('Gomme invernali'));
      await tester.pumpAndSettle();
      expect(find.byType(LogEntryDetailPage), findsOneWidget);
      expect(
        find.textContaining('does not change the vehicle'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete entry?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(store.deletedEntries, contains(entry.id));
      expect(find.byType(LogEntryDetailPage), findsNothing);
      expect(find.text('Gomme invernali'), findsNothing);
      expect(find.text('Entry deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.deletedEntries, isEmpty);
      expect(find.text('Gomme invernali'), findsOneWidget);
    });

    testWidgets('an entry of another vehicle is not found', (tester) async {
      final other =
          store.addVehicle('ZZ999ZZ', ownerId: store.liveOwners.first.id);
      final entry =
          store.addEntry(other.id, date: const CalendarDate(2026, 1, 1));
      await pumpApp(
        tester,
        store,
        location: AppRoutes.entry(vehicleId, entry.id),
      );
      expect(
        find.text('This entry does not exist or has been deleted.'),
        findsOneWidget,
      );
    });
  });

  group('filters', () {
    setUp(() {
      store
        ..addEntry(
          vehicleId,
          date: const CalendarDate(2026, 1, 10),
          type: LogEntryType.refuel,
          description: 'Gasolina en Málaga',
        )
        ..addEntry(
          vehicleId,
          date: const CalendarDate(2026, 2, 10),
          type: LogEntryType.maintenance,
          description: 'Cambio olio',
        )
        ..addEntry(
          vehicleId,
          date: const CalendarDate(2026, 3, 10),
          type: LogEntryType.note,
          km: null,
          description: 'Multa',
        );
    });

    testWidgets('sheet → chips → remove one → clear filters', (tester) async {
      await pumpApp(tester, store, location: AppRoutes.vehicle(vehicleId));
      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();

      await tapVisible(tester, inSheet('Refuelling'));
      await tapVisible(tester, inSheet('Maintenance'));
      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        'MALAGA',
      );
      await tapVisible(tester, inSheet('Apply'));

      // Types AND text: only the refuelling in Málaga.
      expect(find.text('Gasolina en Málaga'), findsOneWidget);
      expect(find.text('Cambio olio'), findsNothing);
      expect(find.text('Multa'), findsNothing);
      expect(find.byType(InputChip), findsNWidgets(3));
      expect(find.text('“MALAGA”'), findsOneWidget);

      // Removing the text chip widens the result to both types.
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, '“MALAGA”'),
          matching: find.byTooltip('Remove filter'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gasolina en Málaga'), findsOneWidget);
      expect(find.text('Cambio olio'), findsOneWidget);
      expect(find.text('Multa'), findsNothing);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('Multa'), findsOneWidget);
    });

    testWidgets('no match shows the message and a reset', (tester) async {
      await pumpApp(tester, store, location: AppRoutes.vehicle(vehicleId));
      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        'nothing like this',
      );
      await tapVisible(tester, inSheet('Apply'));

      expect(find.text('No entries match these filters'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('Multa'), findsOneWidget);
    });
  });
}
