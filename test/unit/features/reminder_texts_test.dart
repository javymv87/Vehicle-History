import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/reminder.dart';
import 'package:vehicle_history/data/models/reminder_kind.dart';
import 'package:vehicle_history/data/models/reminder_status.dart';
import 'package:vehicle_history/data/models/units.dart';
import 'package:vehicle_history/features/reminders/widgets/reminder_texts.dart';
import 'package:vehicle_history/l10n/app_localizations.dart';
import 'package:vehicle_history/shared/utils/unit_formatter.dart';

/// The shared reminder texts (`Docs/08_recordatorios.md`, formatting
/// rules): years for multiples of 12 months, "no limit" for a disabled
/// axis, what is left or past in days or whole months, and the order of
/// the axes in a row. Every day is a calendar day: no time of day is ever
/// involved.
void main() {
  final es = lookupAppLocalizations(const Locale('es'));
  final units = UnitFormatter(
    preferences: UnitPreferences.international,
    l10n: es,
  );
  final miles = UnitFormatter(preferences: UnitPreferences.imperial, l10n: es);
  const today = CalendarDate(2026, 11, 3);

  // Dates are formatted through intl, as in the app.
  setUpAll(() => initializeDateFormatting('es'));

  /// A reminder with the given own warnings.
  Reminder reminder({int? leadDays, double? leadKm}) => Reminder(
        id: 'r',
        vehicleId: 'v',
        kind: ReminderKind.engineOil,
        title: 'Aceite',
        refIntervalKm: 15000,
        refIntervalMonths: 12,
        lastDoneDate: today,
        lastDoneKm: 100000,
        leadDays: leadDays,
        leadKm: leadKm,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

  /// A computed state due on [date] (seen from [today]) and / or with
  /// [remainingKm] left.
  ReminderDue due({
    CalendarDate? date,
    double? remainingKm,
    ReminderStatus status = ReminderStatus.ok,
  }) =>
      ReminderDue(
        status: status,
        effectiveDate: date,
        remainingDays: date == null ? null : today.daysUntil(date),
        effectiveKm: remainingKm == null ? null : 200000 + remainingKm,
        remainingKm: remainingKm,
      );

  group('periods and criteria', () {
    test('a multiple of 12 months reads in years', () {
      expect(periodText(12, es), '1 año');
      expect(periodText(24, es), '2 años');
      expect(periodText(60, es), '5 años');
      expect(periodText(18, es), '18 meses');
      expect(periodText(1, es), '1 mes');
    });

    test('one or both intervals, the distance first', () {
      String text({double? km, int? months}) =>
          criterionText(km: km, months: months, l10n: es, units: units);
      expect(text(km: 15000, months: 12), 'Cada 15.000 km o 1 año');
      expect(text(km: 15000, months: 18), 'Cada 15.000 km o 18 meses');
      expect(text(km: 15000), 'Cada 15.000 km');
      expect(text(months: 24), 'Cada 2 años');
    });

    test('a disabled axis reads as no limit, in the unit in use', () {
      expect(
        criterionText(
          km: 100000,
          months: null,
          disabledMonths: true,
          l10n: es,
          units: units,
        ),
        'Cada 100.000 km · sin límite de tiempo',
      );
      expect(
        criterionText(
          km: null,
          months: 24,
          disabledKm: true,
          l10n: es,
          units: miles,
        ),
        'Cada 2 años · sin límite de mi',
      );
    });

    test('after a label the line starts in lower case', () {
      expect(
        criterionText(
          km: 15000,
          months: 60,
          sentence: false,
          l10n: es,
          units: units,
        ),
        'cada 15.000 km o 5 años',
      );
    });
  });

  group('whole months', () {
    test('counts calendar months, rounded down', () {
      expect(
        wholeMonthsBetween(
          const CalendarDate(2026, 1, 3),
          const CalendarDate(2026, 3, 2),
        ),
        1,
      );
      expect(
        wholeMonthsBetween(
          const CalendarDate(2026, 1, 3),
          const CalendarDate(2026, 3, 3),
        ),
        2,
      );
      // 31 Jan + 3 months is clamped to 30 Apr.
      expect(
        wholeMonthsBetween(
          const CalendarDate(2026, 1, 31),
          const CalendarDate(2026, 4, 30),
        ),
        3,
      );
    });
  });

  group('what is left, in the detail', () {
    test('days below 60, whole months from 60', () {
      expect(
        remainingDateText(due(date: today.addDays(12)), es),
        'faltan 12 días',
      );
      expect(
        remainingDateText(due(date: today.addDays(1)), es),
        'falta 1 día',
      );
      expect(
        remainingDateText(due(date: today.addDays(59)), es),
        'faltan 59 días',
      );
      expect(
        remainingDateText(due(date: today.addDays(60)), es),
        'falta 1 mes',
      );
      expect(
        remainingDateText(due(date: today.addMonths(4)), es),
        'faltan 4 meses',
      );
    });

    test('past the date: ago, with the same rule; today', () {
      expect(
        remainingDateText(due(date: today.addDays(-3)), es),
        'hace 3 días',
      );
      expect(
        remainingDateText(due(date: today.addMonths(-7)), es),
        'hace 7 meses',
      );
      expect(remainingDateText(due(date: today), es), 'vence hoy');
      expect(remainingDateText(due(remainingKm: 10), es), isNull);
    });

    test('distance left, past, or reached exactly', () {
      expect(
        remainingDistanceText(due(remainingKm: 850), es, units),
        'faltan 850 km',
      );
      expect(
        remainingDistanceText(due(remainingKm: -1200), es, units),
        'hace 1.200 km',
      );
      expect(
        remainingDistanceText(due(remainingKm: 0), es, units),
        'vence hoy',
      );
      expect(remainingDistanceText(due(date: today), es, units), isNull);
    });
  });

  group('order of the axes in a row', () {
    const lead = ReminderLead();

    test('the axis in the worse state comes first', () {
      expect(
        dueAxesInOrder(
          reminder(),
          due(date: today.addDays(200), remainingKm: -50),
          lead,
        ),
        [DueAxis.distance, DueAxis.date],
      );
      expect(
        dueAxesInOrder(
          reminder(),
          due(date: today.addDays(-1), remainingKm: 5000),
          lead,
        ),
        [DueAxis.date, DueAxis.distance],
      );
    });

    test('in the same state, the nearer one in its own warning', () {
      // 12,000 km is 12 warnings of 1,000 km; 400 days are 13.3 of 30.
      expect(
        dueAxesInOrder(
          reminder(),
          due(date: today.addDays(400), remainingKm: 12000),
          lead,
        ),
        [DueAxis.distance, DueAxis.date],
      );
      // The reminder's own warning counts: 12,000 km is 2.4 of 5,000.
      expect(
        dueAxesInOrder(
          reminder(leadDays: 365, leadKm: 5000),
          due(date: today.addDays(400), remainingKm: 12000),
          lead,
        ),
        [DueAxis.date, DueAxis.distance],
      );
    });

    test('the date first on a tie', () {
      expect(
        dueAxesInOrder(
          reminder(),
          due(date: today.addDays(30), remainingKm: 1000),
          lead,
        ),
        [DueAxis.date, DueAxis.distance],
      );
    });
  });

  group('the due part of a row', () {
    const lead = ReminderLead();

    String row(ReminderDue state, [Reminder? of]) =>
        rowDueText(of ?? reminder(), state, lead, es, units);

    test('an axis after a future one drops its "en"', () {
      expect(
        row(due(date: today.addMonths(13), remainingKm: 12000)),
        'en 12.000 km · 13 meses',
      );
      expect(
        row(due(date: today.addDays(12), remainingKm: 30000)),
        'en 12 días · 30.000 km',
      );
    });

    test('past axes say ago; a future one after them keeps "en"', () {
      expect(
        row(due(date: today.addDays(-3), remainingKm: 2000)),
        'hace 3 días · en 2.000 km',
      );
      expect(row(due(remainingKm: 850)), 'en 850 km');
      expect(row(due(date: today)), 'vence hoy');
    });

    test('a completed one-shot reads its day', () {
      final done = reminder().copyWith(
        completedAt: DateTime.utc(2026, 10, 20, 12),
      );
      expect(row(due(status: ReminderStatus.completed), done), '20 oct 2026');
    });
  });
}
