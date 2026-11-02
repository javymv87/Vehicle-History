// The filter shared by the three reports of a vehicle
// (`Docs/03_features.md`, "Informes"), and the figures each report draws
// from the entries and readings it selects. Pure Dart, recomputed on every
// read; nothing here is stored.

import 'dart:math' as math;

import 'calendar_date.dart';
import 'fuel_consumption.dart';
import 'log_entry.dart';
import 'log_entry_type.dart';
import 'mileage_reading.dart';
import 'refuel.dart';

/// What part of a vehicle's life the reports look at: a range of days or a
/// range of odometer km. Screen state, never stored.
sealed class ReportFilter {
  const ReportFilter();

  /// Whether a refuel or another entry falls inside the filter.
  bool includesEntry(LogEntry entry);

  /// Whether an odometer reading falls inside the filter.
  bool includesReading(MileageReading reading);

  /// Whether [segment] belongs to the filter: its opening **and** its
  /// closing refuel fall inside. A segment across a border is left out, not
  /// split: splitting it would be a guess.
  bool includesSegment(FuelSegment segment) =>
      includesEntry(segment.opening) && includesEntry(segment.closing);
}

/// The days [from]–[to], both inclusive; a missing end is open, so both
/// missing is "all".
final class DateRangeFilter extends ReportFilter {
  /// Creates the filter; with no ends it takes everything.
  const DateRangeFilter({this.from, this.to});

  /// First day included, or `null` for no lower bound.
  final CalendarDate? from;

  /// Last day included, or `null` for no upper bound.
  final CalendarDate? to;

  /// Whether [date] is inside the range.
  bool includesDate(CalendarDate date) {
    final from = this.from;
    final to = this.to;
    return (from == null || !date.isBefore(from)) &&
        (to == null || !date.isAfter(to));
  }

  @override
  bool includesEntry(LogEntry entry) => includesDate(entry.date);

  @override
  bool includesReading(MileageReading reading) => includesDate(reading.date);

  @override
  bool operator ==(Object other) =>
      other is DateRangeFilter && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// The odometer km [fromKm]–[toKm], both inclusive, in km.
final class KmRangeFilter extends ReportFilter {
  /// Creates the filter.
  const KmRangeFilter({required this.fromKm, required this.toKm});

  /// Lowest km included.
  final double fromKm;

  /// Highest km included.
  final double toKm;

  /// Whether [km] is inside the range.
  bool includesKm(double km) => km >= fromKm && km <= toKm;

  /// An entry belongs by its km; one without km never does.
  @override
  bool includesEntry(LogEntry entry) {
    final km = entry.km;
    return km != null && includesKm(km);
  }

  @override
  bool includesReading(MileageReading reading) => includesKm(reading.km);

  @override
  bool operator ==(Object other) =>
      other is KmRangeFilter && other.fromKm == fromKm && other.toKm == toKm;

  @override
  int get hashCode => Object.hash(fromKm, toKm);
}

/// The consumption report of one chain in a filter: its segments, their
/// figures and how much of the filter they cover.
class ConsumptionReport {
  /// Builds the report of [chain] for [filter]; [readings] are the
  /// vehicle's odometer readings, which bound a km range.
  factory ConsumptionReport.of(
    FuelChain chain,
    ReportFilter filter,
    List<MileageReading> readings,
  ) {
    final segments = [
      for (final segment in chain.segments.reversed)
        if (filter.includesSegment(segment)) segment,
    ];
    final summary = ChainSummary.of(segments);
    // The refuels of this fuel inside the filter, with or without a volume,
    // oldest first: the real extent of the filter for this chain.
    final inside = [
      for (final refuel in chain.refuels)
        if (filter.includesEntry(refuel)) refuel,
    ];
    final double spanKm;
    switch (filter) {
      case DateRangeFilter():
        final kms = [
          for (final refuel in inside)
            if (refuel.km case final km?) km,
        ];
        spanKm = kms.length < 2 ? 0 : math.max(0, kms.last - kms.first);
      case KmRangeFilter(:final fromKm, :final toKm):
        spanKm = _clippedKmRange(fromKm, toKm, readings);
    }
    final spanDays =
        inside.length < 2 ? 0 : inside.first.date.daysUntil(inside.last.date);
    return ConsumptionReport._(
      fuel: chain.fuel,
      segments: segments,
      summary: summary,
      spanKm: spanKm,
      spanDays: spanDays,
      refuelCount: inside.length,
    );
  }

  const ConsumptionReport._({
    required this.fuel,
    required this.segments,
    required this.summary,
    required this.spanKm,
    required this.spanDays,
    required this.refuelCount,
  });

  /// The fuel of the chain.
  final RefuelFuel fuel;

  /// The segments that belong to the filter, newest first, whatever their
  /// state.
  final List<FuelSegment> segments;

  /// The figures of the computable [segments]: "X km (N days)" of the
  /// coverage line are its `km` and `days`.
  final ChainSummary summary;

  /// "Y km" of the coverage line: in a date range, from the first to the
  /// last refuel of this fuel inside it; in a km range, the range itself
  /// clipped to the vehicle's first and last reading.
  final double spanKm;

  /// "M days" of the coverage line: from the first to the last refuel of
  /// this fuel inside the filter.
  final int spanDays;

  /// Refuels of this fuel inside the filter.
  final int refuelCount;

  /// The km of [spanKm] no computable segment covers: what could not be
  /// calculated. Never negative.
  double get uncoveredKm => math.max(0, spanKm - summary.km);

  /// The days of [spanDays] no computable segment covers. Never negative.
  int get uncoveredDays => math.max(0, spanDays - summary.days);

  /// [fromKm]–[toKm] clipped to the km of the first and last of
  /// [readings]; 0 without readings or when nothing is left.
  static double _clippedKmRange(
    double fromKm,
    double toKm,
    List<MileageReading> readings,
  ) {
    if (readings.isEmpty) return 0;
    final kms = [for (final r in readings) r.km];
    final low = math.max(fromKm, kms.reduce(math.min));
    final high = math.min(toKm, kms.reduce(math.max));
    return math.max(0, high - low);
  }
}

/// The amounts spent in one calendar month.
class MonthlySpend {
  /// Creates the month's figures.
  const MonthlySpend({
    required this.year,
    required this.month,
    required this.cents,
    required this.refuelCount,
  });

  /// Year of the month.
  final int year;

  /// Month of the year, 1 to 12.
  final int month;

  /// Amounts of the month's refuels, in cents.
  final int cents;

  /// Refuels of the month, with or without an amount.
  final int refuelCount;
}

/// The fuel spend report of a vehicle in a filter: every refuel, in a
/// chain or not.
class FuelSpendReport {
  /// Builds the report from the vehicle's [entries] for [filter].
  factory FuelSpendReport.of(Iterable<LogEntry> entries, ReportFilter filter) {
    final refuels = [
      for (final entry in entries)
        if (entry.type == LogEntryType.refuel && filter.includesEntry(entry))
          entry,
    ];
    var total = 0;
    final pricedCents = <RefuelFuel, int>{};
    final pricedVolume = <RefuelFuel, double>{};
    final months = <(int, int), (int, int)>{};
    for (final refuel in refuels) {
      final cents = refuel.costCents;
      final key = (refuel.date.year, refuel.date.month);
      final (monthCents, monthCount) = months[key] ?? (0, 0);
      months[key] = (monthCents + (cents ?? 0), monthCount + 1);
      if (cents == null) continue;
      total += cents;
      final details = refuel.refuel;
      final volume = details?.volume;
      if (details != null && volume != null && volume > 0) {
        pricedCents[details.fuel] = (pricedCents[details.fuel] ?? 0) + cents;
        pricedVolume[details.fuel] = (pricedVolume[details.fuel] ?? 0) + volume;
      }
    }
    final sortedMonths = months.keys.toList()
      ..sort((a, b) => a.$1 != b.$1 ? b.$1 - a.$1 : b.$2 - a.$2);
    return FuelSpendReport._(
      refuelCount: refuels.length,
      totalCents: total,
      centsPerUnit: {
        for (final MapEntry(key: fuel, value: cents) in pricedCents.entries)
          fuel: cents / pricedVolume[fuel]!,
      },
      months: [
        for (final key in sortedMonths)
          MonthlySpend(
            year: key.$1,
            month: key.$2,
            cents: months[key]!.$1,
            refuelCount: months[key]!.$2,
          ),
      ],
    );
  }

  const FuelSpendReport._({
    required this.refuelCount,
    required this.totalCents,
    required this.centsPerUnit,
    required this.months,
  });

  /// Refuels inside the filter.
  final int refuelCount;

  /// Sum of their amounts, in cents (refuels without one add nothing).
  final int totalCents;

  /// Average price per litre (per kg for CNG) of each fuel, in cents:
  /// amounts over volumes of the refuels that have both. Two fuels are
  /// never averaged together.
  final Map<RefuelFuel, double> centsPerUnit;

  /// Spend per calendar month, newest first.
  final List<MonthlySpend> months;
}

/// One row of the km-over-time report: a day with odometer readings.
class DistanceStep {
  /// Creates the row.
  const DistanceStep({
    required this.date,
    required this.km,
    this.kmSincePrevious,
    this.daysSincePrevious,
  });

  /// The day.
  final CalendarDate date;

  /// The day's last reading, in km.
  final double km;

  /// Km since the previous day with a reading; `null` for the first.
  final double? kmSincePrevious;

  /// Days since the previous day with a reading (never 0); `null` for the
  /// first.
  final int? daysSincePrevious;
}

/// The km-over-time report of a vehicle in a filter, from its odometer
/// readings only.
class DistanceReport {
  /// Builds the report from the vehicle's [readings] for [filter]. Several
  /// readings of one day count as one, the day's last.
  factory DistanceReport.of(
    Iterable<MileageReading> readings,
    ReportFilter filter,
  ) {
    final inside = [
      for (final reading in readings)
        if (filter.includesReading(reading)) reading,
    ]..sort(
        (a, b) => a.date != b.date
            ? a.date.compareTo(b.date)
            : a.createdAt.compareTo(b.createdAt),
      );
    // The last reading of each day, in day order.
    final byDay = <CalendarDate, MileageReading>{
      for (final reading in inside) reading.date: reading,
    };
    final days = byDay.values.toList();
    final steps = <DistanceStep>[
      for (var i = 0; i < days.length; i++)
        DistanceStep(
          date: days[i].date,
          km: days[i].km,
          kmSincePrevious: i == 0 ? null : days[i].km - days[i - 1].km,
          daysSincePrevious:
              i == 0 ? null : days[i - 1].date.daysUntil(days[i].date),
        ),
    ];
    return DistanceReport._(
      steps: steps.reversed.toList(),
      km: days.length < 2 ? 0 : days.last.km - days.first.km,
      days: days.length < 2 ? 0 : days.first.date.daysUntil(days.last.date),
    );
  }

  const DistanceReport._({
    required this.steps,
    required this.km,
    required this.days,
  });

  /// One row per day with readings, newest first.
  final List<DistanceStep> steps;

  /// Km from the first to the last day.
  final double km;

  /// Days from the first to the last day.
  final int days;

  /// Average days of a month (365.25 / 12), for [kmPerMonth].
  static const double daysPerMonth = 365.25 / 12;

  /// Km per day; `null` within a single day, never a division by zero.
  double? get kmPerDay => days > 0 ? km / days : null;

  /// Km per average month; `null` like [kmPerDay].
  double? get kmPerMonth => switch (kmPerDay) {
        final perDay? => perDay * daysPerMonth,
        null => null,
      };
}
