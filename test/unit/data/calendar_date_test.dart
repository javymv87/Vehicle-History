import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';

void main() {
  group('CalendarDate', () {
    test('formats and parses ISO yyyy-MM-dd', () {
      const date = CalendarDate(2024, 3, 4);
      expect(date.toIso8601String(), '2024-03-04');
      expect(CalendarDate.parse('2024-03-04'), date);
      expect(CalendarDate.parse(date.toIso8601String()), date);
    });

    test('pads small years', () {
      expect(const CalendarDate(987, 1, 2).toIso8601String(), '0987-01-02');
    });

    test('accepts 29 February in a leap year only', () {
      expect(CalendarDate.parse('2024-02-29'), const CalendarDate(2024, 2, 29));
      expect(() => CalendarDate.parse('2023-02-29'), throwsFormatException);
    });

    test('rejects malformed or impossible input', () {
      for (final bad in [
        '',
        '2024-3-4',
        '2024-03-04T00:00:00',
        '2024/03/04',
        '2024-13-01',
        '2024-00-10',
        '2024-04-31',
        '0000-01-01',
      ]) {
        expect(
          () => CalendarDate.parse(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('compares chronologically', () {
      const a = CalendarDate(2023, 12, 31);
      const b = CalendarDate(2024, 1, 1);
      expect(a.compareTo(b), lessThan(0));
      expect(b.isAfter(a), isTrue);
      expect(a.isBefore(b), isTrue);
      expect(a.compareTo(a), 0);
      expect([b, a]..sort(), [a, b]);
    });

    test('has value equality', () {
      expect(const CalendarDate(2024, 3, 4), const CalendarDate(2024, 3, 4));
      expect(
        const CalendarDate(2024, 3, 4).hashCode,
        const CalendarDate(2024, 3, 4).hashCode,
      );
      expect(
        const CalendarDate(2024, 3, 4).copyWith(day: 5),
        const CalendarDate(2024, 3, 5),
      );
    });

    test('counts and adds calendar days across month and year ends', () {
      const a = CalendarDate(2025, 12, 30);
      expect(a.daysUntil(const CalendarDate(2026, 1, 2)), 3);
      expect(const CalendarDate(2026, 1, 2).daysUntil(a), -3);
      expect(a.daysUntil(a), 0);
      // Across the March daylight saving change: still whole days.
      expect(
        const CalendarDate(2026, 3, 28)
            .daysUntil(const CalendarDate(2026, 3, 30)),
        2,
      );
      expect(a.addDays(3), const CalendarDate(2026, 1, 2));
      expect(
        const CalendarDate(2024, 3, 1).addDays(-1),
        const CalendarDate(2024, 2, 29),
      );
    });
  });
}
