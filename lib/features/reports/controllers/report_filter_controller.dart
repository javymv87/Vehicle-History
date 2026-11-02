import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/calendar_date.dart';
import '../../../data/models/refuel.dart';
import '../../../data/models/report_filter.dart';

/// The two kinds of range the reports filter by (`Docs/03_features.md`,
/// "Informes").
enum ReportFilterMode {
  /// A range of days, from a preset or two chosen dates.
  dates,

  /// A range of odometer km.
  odometer,
}

/// The ready-made date ranges.
enum ReportDatePreset {
  /// The whole life of the vehicle, the default.
  all,

  /// The last 12 months, today included.
  months12,

  /// The last 90 days, today included.
  days90,

  /// Two dates chosen by the user.
  custom,
}

/// What the Reports tab of one vehicle shows: the filter in either mode,
/// and the fuel chain the consumption report shows on a bi-fuel vehicle.
/// Screen state, never stored.
class ReportFilterState {
  /// Creates the state; the default is every date and the primary fuel.
  const ReportFilterState({
    this.mode = ReportFilterMode.dates,
    this.preset = ReportDatePreset.all,
    this.customFrom,
    this.customTo,
    this.fromKm,
    this.toKm,
    this.fuel,
  });

  /// Which of the two kinds of range is active.
  final ReportFilterMode mode;

  /// The date range, in [ReportFilterMode.dates].
  final ReportDatePreset preset;

  /// First day of a [ReportDatePreset.custom] range; `null` = open.
  final CalendarDate? customFrom;

  /// Last day of a [ReportDatePreset.custom] range; `null` = open.
  final CalendarDate? customTo;

  /// Lowest km of the odometer range, in km; `null` = the first reading.
  final double? fromKm;

  /// Highest km of the odometer range, in km; `null` = the last reading.
  final double? toKm;

  /// The chain shown by the consumption report; `null` = the primary fuel.
  final RefuelFuel? fuel;

  /// The [ReportFilter] this state selects on [today]; an open end of the
  /// odometer range is the km of the first or last of the vehicle's
  /// readings, [firstKm] and [lastKm].
  ReportFilter filterOn(
    CalendarDate today, {
    required double firstKm,
    required double lastKm,
  }) =>
      switch (mode) {
        ReportFilterMode.odometer =>
          KmRangeFilter(fromKm: fromKm ?? firstKm, toKm: toKm ?? lastKm),
        ReportFilterMode.dates => switch (preset) {
            ReportDatePreset.all => const DateRangeFilter(),
            ReportDatePreset.months12 => DateRangeFilter(
                from: _yearBefore(today).addDays(1),
                to: today,
              ),
            ReportDatePreset.days90 =>
              DateRangeFilter(from: today.addDays(-89), to: today),
            ReportDatePreset.custom =>
              DateRangeFilter(from: customFrom, to: customTo),
          },
      };

  /// The same day a year before [day] (28 February for a 29 February).
  static CalendarDate _yearBefore(CalendarDate day) {
    final shifted = DateTime.utc(day.year - 1, day.month, day.day);
    return shifted.month == day.month
        ? CalendarDate(shifted.year, shifted.month, shifted.day)
        : CalendarDate(day.year - 1, day.month, 28);
  }

  /// Returns a copy with the given values replaced; a custom date or an
  /// odometer end is cleared by its `clear…` flag.
  ReportFilterState copyWith({
    ReportFilterMode? mode,
    ReportDatePreset? preset,
    CalendarDate? customFrom,
    CalendarDate? customTo,
    double? fromKm,
    double? toKm,
    bool clearFromKm = false,
    bool clearToKm = false,
    RefuelFuel? fuel,
  }) =>
      ReportFilterState(
        mode: mode ?? this.mode,
        preset: preset ?? this.preset,
        customFrom: customFrom ?? this.customFrom,
        customTo: customTo ?? this.customTo,
        fromKm: clearFromKm ? null : fromKm ?? this.fromKm,
        toKm: clearToKm ? null : toKm ?? this.toKm,
        fuel: fuel ?? this.fuel,
      );
}

/// The filter of the Reports tab of one vehicle, kept while its page is
/// open (the page listens to it) and reset when the page closes.
class ReportFilterController extends Notifier<ReportFilterState> {
  /// Creates the controller of the vehicle [vehicleId].
  ReportFilterController(this.vehicleId);

  /// Vehicle whose reports are filtered.
  final String vehicleId;

  @override
  ReportFilterState build() => const ReportFilterState();

  /// Switches between dates and odometer, keeping each mode's values.
  void setMode(ReportFilterMode mode) => state = state.copyWith(mode: mode);

  /// Chooses a date preset; [ReportDatePreset.custom] keeps the two dates.
  void setPreset(ReportDatePreset preset) =>
      state = state.copyWith(preset: preset);

  /// Sets the dates of the custom range, swapped if typed backwards.
  void setCustomDates(CalendarDate? from, CalendarDate? to) {
    final swap = from != null && to != null && from.isAfter(to);
    state = ReportFilterState(
      mode: state.mode,
      preset: ReportDatePreset.custom,
      customFrom: swap ? to : from,
      customTo: swap ? from : to,
      fromKm: state.fromKm,
      toKm: state.toKm,
      fuel: state.fuel,
    );
  }

  /// Sets the odometer range in km; `null` ends follow the readings.
  void setKmRange(double? fromKm, double? toKm) => state = state.copyWith(
        fromKm: fromKm,
        toKm: toKm,
        clearFromKm: fromKm == null,
        clearToKm: toKm == null,
      );

  /// Chooses the chain the consumption report shows.
  void setFuel(RefuelFuel fuel) => state = state.copyWith(fuel: fuel);
}

/// The [ReportFilterController] of a vehicle, by id.
final reportFilterProvider = NotifierProvider.autoDispose
    .family<ReportFilterController, ReportFilterState, String>(
  ReportFilterController.new,
);
