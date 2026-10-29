import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/mileage_reading.dart';
import 'package:vehicle_history/data/models/odometer_checks.dart';

void main() {
  const today = CalendarDate(2026, 10, 19);
  const lastReading = CalendarDate(2026, 10, 1);

  group('shouldOfferOdometerUpdate (E3)', () {
    bool offer({
      double? km = 90000,
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

  group('laterReadingBelowEntryKm (E2)', () {
    MileageReading reading(String id, CalendarDate date, double km) =>
        MileageReading(
          id: id,
          vehicleId: 'v',
          date: date,
          km: km,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );

    // 1 Oct 100 000, 10 Oct 111 000, 15 Oct 115 000; newest first, as the
    // repository returns them.
    final series = [
      reading('r3', const CalendarDate(2026, 10, 15), 115000),
      reading('r2', const CalendarDate(2026, 10, 10), 111000),
      reading('r1', const CalendarDate(2026, 10, 1), 100000),
    ];

    String? warn(double? km, CalendarDate date) => laterReadingBelowEntryKm(
          entryKm: km,
          entryDate: date,
          readings: series,
        )?.id;

    test('catches an intermediate reading, not only the last one', () {
      // Below the current odometer, yet above the 10 Oct reading.
      expect(warn(112000, const CalendarDate(2026, 10, 5)), 'r2');
    });

    test('warns against the last reading for an earlier day', () {
      expect(warn(116000, const CalendarDate(2026, 10, 12)), 'r3');
    });

    test('not when the km fits between the readings around the date', () {
      expect(warn(105000, const CalendarDate(2026, 10, 5)), isNull);
      expect(warn(111000, const CalendarDate(2026, 10, 5)), isNull);
    });

    test('not on or after the last reading day, whatever the km', () {
      expect(warn(200000, const CalendarDate(2026, 10, 15)), isNull);
      expect(warn(200000, today), isNull);
    });

    test('a reading on the same day as the entry does not count', () {
      // The 10 Oct reading (111 000) is ignored; 15 Oct is the next one.
      expect(warn(112000, const CalendarDate(2026, 10, 10)), isNull);
      expect(warn(116000, const CalendarDate(2026, 10, 10)), 'r3');
    });

    test('not without km or without readings', () {
      expect(warn(null, const CalendarDate(2026, 9, 1)), isNull);
      expect(
        laterReadingBelowEntryKm(
          entryKm: 1,
          entryDate: const CalendarDate(2026, 9, 1),
          readings: const [],
        ),
        isNull,
      );
    });
  });

  test('isBigOdometerJump starts strictly above 50 000 km', () {
    expect(isBigOdometerJump(km: 150000, lastKm: 100000), isFalse);
    expect(isBigOdometerJump(km: 150001, lastKm: 100000), isTrue);
  });
}
