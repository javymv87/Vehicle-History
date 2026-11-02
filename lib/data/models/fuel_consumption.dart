// Fuel consumption by the full-tank chain (`Docs/04_maintenance_logic.md`,
// "Repostajes y consumos"). Pure Dart, derived from the refuel entries on
// every read and never stored: the numbers always follow the entries.
//
// A segment runs from one full tank to the next full tank of the same fuel,
// in chronological order. Its distance is the difference of the odometer
// km recorded on the two refuels; its volume is the closing refuel's plus
// every refuel in between. A refuel without a volume never opens or closes
// a segment, and one inside a segment makes it impossible to compute.

import 'fuel_type.dart';
import 'log_entry.dart';
import 'log_entry_type.dart';
import 'refuel.dart';

/// Why a segment cannot be computed. Invalid segments are listed, never
/// averaged, and nothing of them is estimated.
enum SegmentProblem {
  /// A refuel in the segment says the user skipped recording one before it.
  missedRefuel,

  /// A refuel in the segment has no volume.
  missingVolume,

  /// A refuel of the segment has no odometer km.
  missingKm,

  /// The closing km is not above the opening km.
  noDistance,

  /// The volume of the segment is not above 0.
  noVolume,
}

/// How a segment counts in the averages.
enum SegmentState {
  /// Computed and counted.
  valid,

  /// Computed and counted, but far from the chain's average: probably a
  /// refuel was not recorded. Shown in amber, never excluded.
  suspicious,

  /// Not computable ([FuelSegment.problem]): listed, never counted.
  invalid,
}

/// One segment of a full-tank chain: from the full tank [opening] to the
/// next full tank [closing] of the same [fuel].
class FuelSegment {
  /// Creates a segment. Built by [FuelChain.build] only.
  const FuelSegment({
    required this.fuel,
    required this.opening,
    required this.closing,
    required this.partials,
    required this.problem,
    this.suspicious = false,
  });

  /// The fuel of the chain.
  final RefuelFuel fuel;

  /// The full tank the segment starts from. Its volume belongs to the
  /// previous segment.
  final LogEntry opening;

  /// The full tank that closes the segment.
  final LogEntry closing;

  /// The refuels of [fuel] between [opening] and [closing], oldest first.
  final List<LogEntry> partials;

  /// Why the segment cannot be computed; `null` when it can.
  final SegmentProblem? problem;

  /// Whether the segment is far from the chain's average (see
  /// [FuelChain.suspiciousDeviation]); only for computable segments.
  final bool suspicious;

  /// How the segment counts.
  SegmentState get state => problem != null
      ? SegmentState.invalid
      : suspicious
          ? SegmentState.suspicious
          : SegmentState.valid;

  /// Whether the segment counts in the averages (valid or suspicious).
  bool get isComputable => problem == null;

  /// The refuels whose volume and amount the segment counts: the partials
  /// and the closing refuel.
  List<LogEntry> get counted => [...partials, closing];

  /// Odometer distance in km, or `null` when a km is missing.
  double? get km {
    final from = opening.km;
    final to = closing.km;
    return from == null || to == null ? null : to - from;
  }

  /// Litres (kilograms for CNG) of the counted refuels; a missing volume
  /// counts as 0 here, and [problem] says so.
  double get volume => [
        for (final entry in counted) entry.refuel?.volume ?? 0,
      ].fold(0, (sum, v) => sum + v);

  /// Calendar days from [opening] to [closing].
  int get days => opening.date.daysUntil(closing.date);

  /// Sum of the amounts of the counted refuels, in cents; `null` when any
  /// of them has no amount, since a partial sum would understate the cost.
  int? get costCents {
    var sum = 0;
    for (final entry in counted) {
      final cents = entry.costCents;
      if (cents == null) return null;
      sum += cents;
    }
    return sum;
  }

  /// Consumption in L/100 km (kg/100 km for CNG), the stored unit of
  /// consumption; `null` when the segment cannot be computed.
  double? get consumption {
    final km = this.km;
    return isComputable && km != null ? volume / km * 100 : null;
  }

  /// Cost per km in cents; `null` when the segment cannot be computed or
  /// an amount is missing.
  double? get centsPerKm {
    final km = this.km;
    final cents = costCents;
    return isComputable && km != null && cents != null ? cents / km : null;
  }

  /// A copy marked as [suspicious].
  FuelSegment _withSuspicious(bool suspicious) => FuelSegment(
        fuel: fuel,
        opening: opening,
        closing: closing,
        partials: partials,
        problem: problem,
        suspicious: suspicious,
      );
}

/// What one refuel is in its chain, for the entry detail and the message
/// after saving (`Docs/03_features.md`, refuel detail).
sealed class RefuelRole {
  const RefuelRole();
}

/// The refuel closes [segment].
final class ClosesSegment extends RefuelRole {
  /// Creates the role for the closing refuel of [segment].
  const ClosesSegment(this.segment);

  /// The segment it closes.
  final FuelSegment segment;
}

/// The refuel is the first full tank of its chain: the consumption shows
/// from the next full tank on.
final class FirstFullTank extends RefuelRole {
  /// Creates the role.
  const FirstFullTank();
}

/// A partial refuel inside [segment], counted in it.
final class PartOfSegment extends RefuelRole {
  /// Creates the role for a partial refuel of [segment].
  const PartOfSegment(this.segment);

  /// The segment it is counted in.
  final FuelSegment segment;
}

/// A partial refuel after the last full tank: it will count in the segment
/// of the next full tank.
final class CountsInNextSegment extends RefuelRole {
  /// Creates the role.
  const CountsInNextSegment();
}

/// A partial refuel before the first full tank: no segment counts it.
final class BeforeFirstFullTank extends RefuelRole {
  /// Creates the role.
  const BeforeFirstFullTank();
}

/// A refuel with no volume: never part of the chain's figures; inside a
/// segment it makes that segment impossible to compute.
final class WithoutVolume extends RefuelRole {
  /// Creates the role.
  const WithoutVolume();
}

/// The figures of a set of segments: the averages count the computable
/// ones only, as totals divided by totals.
class ChainSummary {
  /// Sums the computable segments among [segments].
  factory ChainSummary.of(Iterable<FuelSegment> segments) {
    var count = 0;
    var km = 0.0;
    var volume = 0.0;
    var days = 0;
    var costKm = 0.0;
    var costCents = 0;
    for (final segment in segments) {
      final segmentKm = segment.km;
      if (!segment.isComputable || segmentKm == null) continue;
      count++;
      km += segmentKm;
      volume += segment.volume;
      days += segment.days;
      final cents = segment.costCents;
      if (cents != null) {
        costKm += segmentKm;
        costCents += cents;
      }
    }
    return ChainSummary._(
      segmentCount: count,
      km: km,
      volume: volume,
      days: days,
      costCents: costCents,
      costKm: costKm,
    );
  }

  const ChainSummary._({
    required this.segmentCount,
    required this.km,
    required this.volume,
    required this.days,
    required this.costCents,
    required this.costKm,
  });

  /// Number of computable segments.
  final int segmentCount;

  /// Distance of the computable segments, in km.
  final double km;

  /// Volume (or mass) of the computable segments.
  final double volume;

  /// Days of the computable segments.
  final int days;

  /// Amounts of the computable segments with every amount recorded, in
  /// cents.
  final int costCents;

  /// Distance of the segments counted in [costCents], in km.
  final double costKm;

  /// Average consumption in L/100 km (kg/100 km for CNG): total volume
  /// over total distance, not the mean of the segments; `null` without a
  /// computable segment.
  double? get consumption => km > 0 ? volume / km * 100 : null;

  /// Average cost per km in cents, over the segments with every amount
  /// recorded; `null` when there is none.
  double? get centsPerKm => costKm > 0 ? costCents / costKm : null;
}

/// The full-tank chain of one fuel of a vehicle.
class FuelChain {
  const FuelChain._(this.fuel, this.refuels, this.segments);

  /// Builds the chain of [fuel] from [entries], which may hold any entry
  /// of the vehicle: only its live refuels of [fuel] are used.
  factory FuelChain.build(Iterable<LogEntry> entries, RefuelFuel fuel) {
    final refuels = [
      for (final entry in entries)
        if (entry.type == LogEntryType.refuel && entry.refuel?.fuel == fuel)
          entry,
    ]..sort(compareChronologically);
    final segments = <FuelSegment>[];
    int? openingIndex;
    for (var i = 0; i < refuels.length; i++) {
      if (!_isChainNode(refuels[i])) continue;
      if (openingIndex != null) {
        final partials = refuels.sublist(openingIndex + 1, i);
        segments.add(
          FuelSegment(
            fuel: fuel,
            opening: refuels[openingIndex],
            closing: refuels[i],
            partials: partials,
            problem: _problemOf(refuels[openingIndex], partials, refuels[i]),
          ),
        );
      }
      openingIndex = i;
    }
    return FuelChain._(fuel, refuels, _markSuspicious(segments));
  }

  /// The fuel of the chain.
  final RefuelFuel fuel;

  /// Every refuel of [fuel], oldest first.
  final List<LogEntry> refuels;

  /// The segments, oldest first.
  final List<FuelSegment> segments;

  /// Relative distance from the chain's average above which a segment is
  /// suspicious (40 %).
  static const double suspiciousDeviation = 0.4;

  /// Computable segments a chain needs before any is called suspicious.
  static const int minSegmentsForSuspicion = 3;

  /// Orders refuels by day, then creation instant, then id.
  static int compareChronologically(LogEntry a, LogEntry b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    final byCreation = a.createdAt.compareTo(b.createdAt);
    return byCreation != 0 ? byCreation : a.id.compareTo(b.id);
  }

  /// Whether [refuel] opens or closes segments: a full tank with a volume.
  static bool _isChainNode(LogEntry refuel) {
    final details = refuel.refuel;
    return details != null && details.fullTank && details.volume != null;
  }

  /// Why the segment from [opening] through [partials] to [closing] cannot
  /// be computed, or `null`.
  static SegmentProblem? _problemOf(
    LogEntry opening,
    List<LogEntry> partials,
    LogEntry closing,
  ) {
    final counted = [...partials, closing];
    if (counted.any((e) => e.refuel?.missedPrevious ?? false)) {
      return SegmentProblem.missedRefuel;
    }
    if (counted.any((e) => e.refuel?.volume == null)) {
      return SegmentProblem.missingVolume;
    }
    if ([opening, ...counted].any((e) => e.km == null)) {
      return SegmentProblem.missingKm;
    }
    if (closing.km! - opening.km! <= 0) return SegmentProblem.noDistance;
    final volume = counted.fold<double>(0, (sum, e) => sum + e.refuel!.volume!);
    return volume <= 0 ? SegmentProblem.noVolume : null;
  }

  /// [segments] with the suspicious ones marked: with at least
  /// [minSegmentsForSuspicion] computable segments, those whose consumption
  /// differs from the chain's average by more than [suspiciousDeviation].
  static List<FuelSegment> _markSuspicious(List<FuelSegment> segments) {
    final summary = ChainSummary.of(segments);
    final average = summary.consumption;
    if (summary.segmentCount < minSegmentsForSuspicion || average == null) {
      return segments;
    }
    return [
      for (final segment in segments)
        switch (segment.consumption) {
          final consumption? => segment._withSuspicious(
              (consumption - average).abs() / average > suspiciousDeviation,
            ),
          null => segment,
        },
    ];
  }

  /// The figures of the whole chain, whatever the filter.
  ChainSummary get summary => ChainSummary.of(segments);

  /// What the refuel with [entryId] is in this chain, or `null` when it is
  /// not one of [refuels].
  RefuelRole? roleOf(String entryId) {
    final index = refuels.indexWhere((e) => e.id == entryId);
    if (index < 0) return null;
    final entry = refuels[index];
    if (entry.refuel?.volume == null) return const WithoutVolume();
    for (final segment in segments) {
      if (segment.closing.id == entryId) return ClosesSegment(segment);
      if (segment.partials.any((e) => e.id == entryId)) {
        return PartOfSegment(segment);
      }
    }
    final firstNode = refuels.indexWhere(_isChainNode);
    if (_isChainNode(entry) && index == firstNode) return const FirstFullTank();
    return firstNode < 0 || index < firstNode
        ? const BeforeFirstFullTank()
        : const CountsInNextSegment();
  }

  /// The chains of a vehicle of [fuelType] from its [entries]: one per fuel
  /// it allows, the primary first; none for an electric vehicle.
  static List<FuelChain> allOf(
    Iterable<LogEntry> entries,
    FuelType fuelType,
  ) =>
      [
        for (final fuel in fuelType.refuelFuels) FuelChain.build(entries, fuel),
      ];
}
