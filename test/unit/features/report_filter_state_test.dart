import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/report_filter.dart';
import 'package:vehicle_history/features/reports/controllers/report_filter_controller.dart';

void main() {
  const today = CalendarDate(2026, 11, 2);

  ReportFilter filterOf(ReportFilterState state, [CalendarDate day = today]) =>
      state.filterOn(day, firstKm: 1000, lastKm: 9000);

  test('the default is every date', () {
    expect(filterOf(const ReportFilterState()), const DateRangeFilter());
  });

  test('12 months and 90 days end today, both ends included', () {
    expect(
      filterOf(const ReportFilterState(preset: ReportDatePreset.months12)),
      const DateRangeFilter(from: CalendarDate(2025, 11, 3), to: today),
    );
    expect(
      filterOf(const ReportFilterState(preset: ReportDatePreset.days90)),
      const DateRangeFilter(from: CalendarDate(2026, 8, 5), to: today),
    );
    // A year before 29 February is 28 February.
    expect(
      filterOf(
        const ReportFilterState(preset: ReportDatePreset.months12),
        const CalendarDate(2028, 2, 29),
      ),
      const DateRangeFilter(
        from: CalendarDate(2027, 3, 1),
        to: CalendarDate(2028, 2, 29),
      ),
    );
  });

  test('custom dates, open ends allowed', () {
    expect(
      filterOf(
        const ReportFilterState(
          preset: ReportDatePreset.custom,
          customFrom: CalendarDate(2026, 1, 1),
        ),
      ),
      const DateRangeFilter(from: CalendarDate(2026, 1, 1)),
    );
  });

  test('the odometer range defaults to the first and last reading', () {
    expect(
      filterOf(const ReportFilterState(mode: ReportFilterMode.odometer)),
      const KmRangeFilter(fromKm: 1000, toKm: 9000),
    );
    expect(
      filterOf(
        const ReportFilterState(mode: ReportFilterMode.odometer, toKm: 5000),
      ),
      const KmRangeFilter(fromKm: 1000, toKm: 5000),
    );
  });
}
