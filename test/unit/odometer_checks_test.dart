import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/odometer_checks.dart';

void main() {
  const today = CalendarDate(2026, 10, 19);
  const lastReading = CalendarDate(2026, 10, 1);

  group('shouldOfferOdometerUpdate (E3)', () {
    bool offer({
      int? km = 90000,
      CalendarDate date = const CalendarDate(2026, 10, 10),
      CalendarDate? last = lastReading,
    }) =>
        shouldOfferOdometerUpdate(
          entryKm: km,
          entryDate: date,
          currentOdometerKm: 85000,
          lastReadingDate: last,
          today: today,
        );

    test('offers when km is higher, dated between last reading and today', () {
      expect(offer(), isTrue);
      expect(offer(date: today), isTrue);
      expect(offer(date: lastReading), isTrue);
    });

    test('not when the km is not higher than the odometer', () {
      expect(offer(km: 85000), isFalse);
      expect(offer(km: 84000), isFalse);
      expect(offer(km: null), isFalse);
    });

    test('not when the entry is dated in the future', () {
      expect(offer(date: const CalendarDate(2026, 10, 20)), isFalse);
    });

    test('not when the entry is dated before the last reading', () {
      expect(offer(date: const CalendarDate(2026, 9, 30)), isFalse);
    });
  });

  group('isPastEntryAboveOdometer (E2)', () {
    bool warn({
      int? km = 90000,
      CalendarDate date = const CalendarDate(2026, 9, 1),
    }) =>
        isPastEntryAboveOdometer(
          entryKm: km,
          entryDate: date,
          currentOdometerKm: 85000,
          lastReadingDate: lastReading,
        );

    test('warns for an earlier day with more km than the odometer', () {
      expect(warn(), isTrue);
    });

    test('not on or after the last reading day', () {
      expect(warn(date: lastReading), isFalse);
      expect(warn(date: today), isFalse);
    });

    test('not when the km is not above the odometer, or missing', () {
      expect(warn(km: 85000), isFalse);
      expect(warn(km: null), isFalse);
    });
  });

  test('isBigOdometerJump starts strictly above 50 000 km', () {
    expect(isBigOdometerJump(km: 150000, lastKm: 100000), isFalse);
    expect(isBigOdometerJump(km: 150001, lastKm: 100000), isTrue);
  });
}
