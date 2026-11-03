import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/reminder.dart';
import 'package:vehicle_history/data/models/reminder_kind.dart';
import 'package:vehicle_history/data/models/reminder_status.dart';

/// A recurring engine-oil reminder done on 1 March 2026 at 100 000 km,
/// every [km] km and / or [months] months.
Reminder recurring({
  double? km = 15000,
  int? months = 12,
  CalendarDate lastDone = const CalendarDate(2026, 3, 1),
  double? lastDoneKm = 100000,
}) =>
    Reminder(
      id: 'r1',
      vehicleId: 'v1',
      kind: ReminderKind.engineOil,
      title: 'Olio',
      refIntervalKm: km,
      refIntervalMonths: months,
      lastDoneDate: lastDone,
      lastDoneKm: lastDoneKm,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

/// A one-shot road-tax reminder due on [due].
Reminder oneShot(CalendarDate due) => Reminder(
      id: 'r2',
      vehicleId: 'v1',
      kind: ReminderKind.roadTax,
      title: 'Bollo',
      dueDate: due,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

const ReminderLead lead = ReminderLead();

void main() {
  /// Evaluates [reminder] on [today] with the odometer at [km].
  ReminderDue eval(
    Reminder reminder, {
    CalendarDate today = const CalendarDate(2026, 6, 1),
    double km = 105000,
    ReminderLead lead = lead,
  }) =>
      evaluateReminder(reminder, today: today, currentKm: km, lead: lead);

  group('due values', () {
    test('anchor plus each interval', () {
      final due = eval(recurring());
      expect(due.dueDate, const CalendarDate(2027, 3, 1));
      expect(due.dueKm, 115000);
      expect(due.remainingDays, 273);
      expect(due.remainingKm, 10000);
      expect(due.status, ReminderStatus.ok);
    });

    test('a single axis leaves the other null', () {
      final byKm = eval(recurring(months: null));
      expect(byKm.dueDate, isNull);
      expect(byKm.remainingDays, isNull);
      expect(byKm.dueKm, 115000);
      final byTime = eval(recurring(km: null, lastDoneKm: null));
      expect(byTime.dueKm, isNull);
      expect(byTime.remainingKm, isNull);
      expect(byTime.dueDate, const CalendarDate(2027, 3, 1));
    });

    test('months clamp to the end of a shorter month', () {
      final due = eval(
        recurring(lastDone: const CalendarDate(2026, 1, 31), months: 1),
      );
      expect(due.dueDate, const CalendarDate(2026, 2, 28));
    });

    test('a one-shot reminder falls due on its date, never by km', () {
      final due = eval(oneShot(const CalendarDate(2026, 7, 15)));
      expect(due.dueDate, const CalendarDate(2026, 7, 15));
      expect(due.dueKm, isNull);
      expect(due.remainingDays, 44);
      expect(due.status, ReminderStatus.ok);
    });
  });

  group('status: the first of the two to fall due wins', () {
    test('overdue by date alone, km far away', () {
      final due = eval(
        recurring(),
        today: const CalendarDate(2027, 3, 2),
        km: 101000,
      );
      expect(due.status, ReminderStatus.overdue);
      expect(due.remainingDays, -1);
    });

    test('the due day itself is not overdue yet', () {
      final due = eval(
        recurring(),
        today: const CalendarDate(2027, 3, 1),
        km: 101000,
      );
      expect(due.status, ReminderStatus.dueSoon);
      expect(due.remainingDays, 0);
    });

    test('overdue by km alone, date far away, from the due km on', () {
      expect(eval(recurring(), km: 115000).status, ReminderStatus.overdue);
      expect(eval(recurring(), km: 120000).remainingKm, -5000);
    });

    test('due soon within the lead days', () {
      final due = eval(
        recurring(),
        today: const CalendarDate(2027, 1, 30),
        km: 101000,
      );
      expect(due.remainingDays, 30);
      expect(due.status, ReminderStatus.dueSoon);
      expect(
        eval(recurring(), today: const CalendarDate(2027, 1, 29), km: 101000)
            .status,
        ReminderStatus.ok,
      );
    });

    test('due soon within the lead km', () {
      expect(eval(recurring(), km: 114000).status, ReminderStatus.dueSoon);
      expect(eval(recurring(), km: 113999).status, ReminderStatus.ok);
    });

    test('overdue beats due soon on the other axis', () {
      final due = eval(
        recurring(),
        today: const CalendarDate(2027, 3, 5),
        km: 114500,
      );
      expect(due.status, ReminderStatus.overdue);
    });

    test('a completed one-shot is completed whatever its date', () {
      final done = oneShot(const CalendarDate(2026, 1, 1))
          .copyWith(completedAt: DateTime.utc(2026, 1, 2));
      expect(eval(done).status, ReminderStatus.completed);
    });
  });

  group('lead', () {
    test('a per-reminder lead overrides the global one, axis by axis', () {
      final reminder = recurring().copyWith(leadDays: 5, leadKm: 200);
      expect(eval(reminder, km: 114000).status, ReminderStatus.ok);
      expect(eval(reminder, km: 114800).status, ReminderStatus.dueSoon);
      expect(
        eval(reminder, today: const CalendarDate(2027, 2, 20), km: 101000)
            .status,
        ReminderStatus.ok,
      );
      final daysOnly = recurring().copyWith(leadDays: 5);
      // The km lead is still the global 1000.
      expect(eval(daysOnly, km: 114000).status, ReminderStatus.dueSoon);
    });

    test('the global lead decides when the reminder has none', () {
      const wide = ReminderLead(days: 400, km: 1000);
      expect(eval(recurring(), lead: wide).status, ReminderStatus.dueSoon);
    });
  });

  group('snooze', () {
    test('replaces the due value of its axis only', () {
      final snoozed = recurring().copyWith(
        snoozeUntilDate: const CalendarDate(2027, 6, 1),
        snoozeReason: 'In officina a giugno',
      );
      final due = eval(snoozed, today: const CalendarDate(2027, 3, 10));
      expect(due.dueDate, const CalendarDate(2027, 3, 1));
      expect(due.effectiveDate, const CalendarDate(2027, 6, 1));
      expect(due.status, ReminderStatus.ok);
      // The km axis still decides on its own.
      expect(
        eval(snoozed, today: const CalendarDate(2027, 3, 10), km: 116000)
            .status,
        ReminderStatus.overdue,
      );
    });

    test('a km snooze takes precedence over the due km', () {
      final snoozed = recurring().copyWith(snoozeUntilKm: 118000);
      final due = eval(snoozed, km: 116000);
      expect(due.effectiveKm, 118000);
      expect(due.remainingKm, 2000);
      expect(due.status, ReminderStatus.ok);
    });
  });

  group('override', () {
    test('the applied criterion decides; the reference is still computed', () {
      final custom = recurring().copyWith(
        overrideActive: true,
        appliedIntervalKm: 10000,
        appliedIntervalMonths: 12,
      );
      final due = eval(custom, km: 109500);
      expect(due.dueKm, 110000);
      expect(due.referenceDueKm, 115000);
      expect(due.referenceDueDate, const CalendarDate(2027, 3, 1));
      expect(due.status, ReminderStatus.dueSoon);
      expect(due.laxerThanReference, isFalse);
    });

    test('a disabled axis no longer falls due', () {
      final custom = recurring().copyWith(
        overrideActive: true,
        appliedIntervalKm: 80000,
        appliedIntervalMonths: null,
      );
      final due = eval(custom, today: const CalendarDate(2030, 1, 1));
      expect(due.dueDate, isNull);
      expect(due.referenceDueDate, const CalendarDate(2027, 3, 1));
      expect(due.status, ReminderStatus.ok);
      expect(due.laxerThanReference, isTrue);
    });

    test('applied values are ignored while the override is off', () {
      final off = recurring().copyWith(appliedIntervalKm: 1000);
      expect(eval(off).dueKm, 115000);
    });
  });

  group('isLaxerThanReference', () {
    Reminder custom({double? km, int? months}) => recurring().copyWith(
          overrideActive: true,
          appliedIntervalKm: km,
          appliedIntervalMonths: months,
        );

    test('a longer interval on any axis of the reference is laxer', () {
      expect(isLaxerThanReference(custom(km: 20000, months: 12)), isTrue);
      expect(isLaxerThanReference(custom(km: 15000, months: 24)), isTrue);
    });

    test('equal or shorter intervals are not laxer', () {
      expect(isLaxerThanReference(custom(km: 15000, months: 12)), isFalse);
      expect(isLaxerThanReference(custom(km: 10000, months: 6)), isFalse);
    });

    test('disabling an axis of the reference is laxer', () {
      expect(isLaxerThanReference(custom(km: 15000)), isTrue);
      expect(isLaxerThanReference(custom(months: 12)), isTrue);
    });

    test('adding an axis the reference lacks is stricter, not laxer', () {
      final timeOnly = recurring(km: null).copyWith(
        overrideActive: true,
        appliedIntervalKm: 20000,
        appliedIntervalMonths: 12,
      );
      expect(isLaxerThanReference(timeOnly), isFalse);
    });

    test('never without an active override', () {
      expect(isLaxerThanReference(recurring()), isFalse);
    });
  });

  test('compareByUrgency: status, then remaining days, then remaining km', () {
    const overdue = ReminderDue(
      status: ReminderStatus.overdue,
      remainingDays: -3,
    );
    const soonByDays = ReminderDue(
      status: ReminderStatus.dueSoon,
      remainingDays: 5,
    );
    const soonSameDayLessKm = ReminderDue(
      status: ReminderStatus.dueSoon,
      remainingDays: 5,
      remainingKm: 100,
    );
    const soonByKm = ReminderDue(
      status: ReminderStatus.dueSoon,
      remainingKm: 300,
    );
    const ok = ReminderDue(status: ReminderStatus.ok, remainingDays: 1);
    final sorted = [ok, soonByKm, soonByDays, overdue, soonSameDayLessKm]
      ..sort(compareByUrgency);
    expect(sorted, [overdue, soonSameDayLessKm, soonByDays, soonByKm, ok]);
  });

  group('ReminderLead', () {
    test('missing or unreadable values are the defaults', () {
      expect(ReminderLead.fromCodes(), const ReminderLead(days: 30, km: 1000));
      expect(
        ReminderLead.fromCodes(days: '-1', km: 'x'),
        const ReminderLead(),
      );
      expect(
        ReminderLead.fromCodes(days: '15', km: '1609.344'),
        const ReminderLead(days: 15, km: 1609.344),
      );
    });

    test('a whole km is stored without decimals', () {
      expect(ReminderLead.kmCode(1000), '1000');
      expect(ReminderLead.kmCode(1609.344), '1609.344');
    });
  });
}
