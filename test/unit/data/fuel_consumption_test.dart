import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_consumption.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/mileage_reading.dart';
import 'package:vehicle_history/data/models/refuel.dart';
import 'package:vehicle_history/data/models/report_filter.dart';

/// Counter giving every refuel a later creation instant than the previous.
var _created = 0;

/// A refuel on day [day] of October 2026 (or [date]) at [km], with
/// [volume] litres and [cents], a full tank unless [full] is false.
LogEntry refuel(
  String id, {
  int day = 1,
  CalendarDate? date,
  double? km,
  double? volume,
  int? cents,
  bool full = true,
  bool missed = false,
  RefuelFuel fuel = RefuelFuel.petrol,
}) {
  final created = DateTime.utc(2026, 1, 1).add(Duration(minutes: _created++));
  return LogEntry(
    id: id,
    vehicleId: 'v1',
    date: date ?? CalendarDate(2026, 10, day),
    km: km,
    type: LogEntryType.refuel,
    costCents: cents,
    refuel: RefuelDetails(
      fuel: fuel,
      volume: volume,
      fullTank: full,
      missedPrevious: missed,
    ),
    createdAt: created,
    updatedAt: created,
  );
}

/// The petrol chain of [entries].
FuelChain chainOf(List<LogEntry> entries) =>
    FuelChain.build(entries, RefuelFuel.petrol);

/// A reading of [km] on day [day] of October 2026.
MileageReading reading(String id, int day, double km) {
  final created = DateTime.utc(2026, 1, 1).add(Duration(minutes: _created++));
  return MileageReading(
    id: id,
    vehicleId: 'v1',
    date: CalendarDate(2026, 10, day),
    km: km,
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  group('segments', () {
    test('a simple chain: two full tanks make one segment', () {
      final chain = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40, cents: 7000),
        refuel('b', day: 11, km: 10600, volume: 36, cents: 6300),
      ]);
      final segment = chain.segments.single;
      expect((segment.opening.id, segment.closing.id), ('a', 'b'));
      expect(segment.km, 600);
      // The opening's volume belongs to the previous segment.
      expect(segment.volume, 36);
      expect(segment.consumption, closeTo(6.0, 1e-9));
      expect(segment.days, 10);
      expect(segment.costCents, 6300);
      expect(segment.centsPerKm, closeTo(10.5, 1e-9));
      expect(segment.state, SegmentState.valid);
    });

    test('a partial in the middle adds its volume and amount', () {
      final chain = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40, cents: 7000),
        refuel('p', day: 5, km: 10300, volume: 15, cents: 2600, full: false),
        refuel('b', day: 11, km: 10600, volume: 21, cents: 3700),
      ]);
      final segment = chain.segments.single;
      expect(segment.partials.map((e) => e.id), ['p']);
      expect(segment.volume, 36);
      expect(segment.costCents, 6300);
      expect(segment.consumption, closeTo(6.0, 1e-9));
    });

    test('a missed refuel in the segment makes it invalid', () {
      final closingMissed = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40),
        refuel('b', day: 11, km: 10600, volume: 36, missed: true),
      ]);
      expect(
        closingMissed.segments.single.problem,
        SegmentProblem.missedRefuel,
      );
      final partialMissed = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40),
        refuel('p', day: 5, km: 10300, volume: 15, full: false, missed: true),
        refuel('b', day: 11, km: 10600, volume: 21),
      ]);
      expect(
        partialMissed.segments.single.problem,
        SegmentProblem.missedRefuel,
      );
      expect(partialMissed.segments.single.consumption, isNull);
      // On the opening it belongs to the previous segment, not this one.
      final openingMissed = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40, missed: true),
        refuel('b', day: 11, km: 10600, volume: 36),
      ]);
      expect(openingMissed.segments.single.state, SegmentState.valid);
    });

    test('the first full tank has no segment', () {
      final chain = chainOf([refuel('a', km: 10000, volume: 40)]);
      expect(chain.segments, isEmpty);
      expect(chain.roleOf('a'), isA<FirstFullTank>());
      expect(chain.summary.consumption, isNull);
    });

    test('same-day refuels are ordered by their creation instant', () {
      // Created in this order on one day: a, then b.
      final a = refuel('a', day: 3, km: 10000, volume: 40);
      final b = refuel('b', day: 3, km: 10050, volume: 4);
      final chain = chainOf([b, a]);
      final segment = chain.segments.single;
      expect((segment.opening.id, segment.closing.id), ('a', 'b'));
      expect(segment.days, 0);
      expect(segment.km, 50);
    });

    test('a refuel without volume never opens or closes a segment', () {
      final chain = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40),
        // A full tank with no volume: the switch is ignored for the chain.
        refuel('n', day: 5, km: 10300),
        refuel('b', day: 11, km: 10600, volume: 36),
      ]);
      final segment = chain.segments.single;
      expect((segment.opening.id, segment.closing.id), ('a', 'b'));
      // Inside the segment, it makes it impossible to compute.
      expect(segment.problem, SegmentProblem.missingVolume);
      expect(chain.roleOf('n'), isA<WithoutVolume>());
    });

    test('old refuels without volume never form a segment', () {
      final chain = chainOf([
        refuel('old1', day: 1, km: 9000),
        refuel('old2', day: 2, km: 9500),
        refuel('a', day: 10, km: 10000, volume: 40),
      ]);
      expect(chain.segments, isEmpty);
      expect(chain.roleOf('a'), isA<FirstFullTank>());
    });

    test('a missing km, no distance or no volume make it invalid', () {
      expect(
        chainOf([
          refuel('a', day: 1, volume: 40),
          refuel('b', day: 11, km: 10600, volume: 36),
        ]).segments.single.problem,
        SegmentProblem.missingKm,
      );
      expect(
        chainOf([
          refuel('a', day: 1, km: 10600, volume: 40),
          refuel('b', day: 11, km: 10600, volume: 36),
        ]).segments.single.problem,
        SegmentProblem.noDistance,
      );
      expect(
        chainOf([
          refuel('a', day: 1, km: 10000, volume: 40),
          refuel('b', day: 11, km: 10600, volume: 0),
        ]).segments.single.problem,
        SegmentProblem.noVolume,
      );
    });

    test('an amount missing leaves the cost unknown, not understated', () {
      final segment = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40, cents: 7000),
        refuel('p', day: 5, km: 10300, volume: 15, full: false),
        refuel('b', day: 11, km: 10600, volume: 21, cents: 3700),
      ]).segments.single;
      expect(segment.costCents, isNull);
      expect(segment.centsPerKm, isNull);
      expect(segment.consumption, closeTo(6.0, 1e-9));
    });
  });

  group('averages and suspicious segments', () {
    test('the average is total volume over total km, not a mean', () {
      final chain = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40, cents: 100),
        // 100 km, 10 L: 10 L/100 km.
        refuel('b', day: 2, km: 10100, volume: 10, cents: 1000),
        // 900 km, 45 L: 5 L/100 km.
        refuel('c', day: 12, km: 11000, volume: 45, cents: 4500),
      ]);
      final summary = chain.summary;
      expect(summary.segmentCount, 2);
      expect(summary.km, 1000);
      expect(summary.volume, 55);
      // 55 / 1000 × 100 = 5.5, not (10 + 5) / 2 = 7.5.
      expect(summary.consumption, closeTo(5.5, 1e-9));
      expect(summary.centsPerKm, closeTo(5.5, 1e-9));
      expect(summary.days, 11);
    });

    test('invalid segments are listed but never averaged', () {
      final chain = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40),
        refuel('b', day: 5, km: 10500, volume: 30),
        refuel('c', day: 9, km: 11000, volume: 99, missed: true),
      ]);
      expect(chain.segments, hasLength(2));
      expect(chain.summary.segmentCount, 1);
      expect(chain.summary.consumption, closeTo(6.0, 1e-9));
    });

    test('with 3 computable segments, one 40 % off is suspicious', () {
      final chain = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40),
        refuel('b', day: 2, km: 10500, volume: 30),
        refuel('c', day: 3, km: 11000, volume: 30),
        // 500 km on 60 L: 12 L/100 km against an average of 8.
        refuel('d', day: 4, km: 11500, volume: 60),
      ]);
      expect(
        [for (final s in chain.segments) s.state],
        [SegmentState.valid, SegmentState.valid, SegmentState.suspicious],
      );
      // Still counted.
      expect(chain.summary.segmentCount, 3);
    });

    test('just under 40 % off is not suspicious', () {
      // Average (30 + 30 + 41.9) / 1500 × 100 ≈ 6.79; 8.38 is 23 % off.
      final chain = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40),
        refuel('b', day: 2, km: 10500, volume: 30),
        refuel('c', day: 3, km: 11000, volume: 30),
        refuel('d', day: 4, km: 11500, volume: 41.9),
      ]);
      expect(
        chain.segments.map((s) => s.state),
        everyElement(SegmentState.valid),
      );
    });

    test('with fewer than 3 computable segments nothing is suspicious', () {
      final chain = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40),
        refuel('b', day: 2, km: 10500, volume: 30),
        refuel('c', day: 3, km: 11000, volume: 90),
      ]);
      expect(
        chain.segments.map((s) => s.state),
        everyElement(SegmentState.valid),
      );
    });
  });

  group('fuels', () {
    test('the two chains of a bi-fuel vehicle are independent', () {
      final entries = [
        refuel('p1', day: 1, km: 10000, volume: 40),
        refuel('l1', day: 2, km: 10100, volume: 30, fuel: RefuelFuel.lpg),
        refuel('p2', day: 5, km: 10600, volume: 30),
        refuel('l2', day: 8, km: 10700, volume: 48, fuel: RefuelFuel.lpg),
      ];
      final chains = FuelChain.allOf(entries, FuelType.petrolLpg);
      expect([
        for (final c in chains) c.fuel,
      ], [
        RefuelFuel.petrol,
        RefuelFuel.lpg,
      ]);
      final petrol = chains.first.segments.single;
      expect((petrol.km, petrol.volume), (600, 30));
      final lpg = chains.last.segments.single;
      expect((lpg.km, lpg.volume), (600, 48));
      // A refuel of the other fuel is not a partial of this chain.
      expect(petrol.partials, isEmpty);
    });

    test('an electric vehicle has no chain', () {
      expect(FuelChain.allOf([refuel('a', km: 1)], FuelType.electric), isEmpty);
    });

    test('other entry types never enter a chain', () {
      final service = refuel('s', day: 4, km: 10300, volume: 1).copyWith(
        type: LogEntryType.maintenance,
      );
      final chain = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40),
        service,
        refuel('b', day: 11, km: 10600, volume: 36),
      ]);
      expect(chain.segments.single.partials, isEmpty);
      expect(chain.roleOf('s'), isNull);
    });
  });

  group('roles', () {
    final entries = [
      refuel('before', day: 1, km: 9900, volume: 5, full: false),
      refuel('a', day: 2, km: 10000, volume: 40),
      refuel('p', day: 5, km: 10300, volume: 15, full: false),
      refuel('b', day: 11, km: 10600, volume: 21),
      refuel('after', day: 15, km: 10900, volume: 10, full: false),
    ];
    final chain = chainOf(entries);

    test('each refuel says what it is in the chain', () {
      expect(chain.roleOf('before'), isA<BeforeFirstFullTank>());
      expect(chain.roleOf('a'), isA<FirstFullTank>());
      expect(
        chain.roleOf('p'),
        isA<PartOfSegment>()
            .having((r) => r.segment.closing.id, 'closing', 'b'),
      );
      expect(
        chain.roleOf('b'),
        isA<ClosesSegment>()
            .having((r) => r.segment.opening.id, 'opening', 'a'),
      );
      expect(chain.roleOf('after'), isA<CountsInNextSegment>());
      expect(chain.roleOf('unknown'), isNull);
    });
  });

  group('report filter', () {
    // Segments: a→b (days 1–11, 600 km), b→c (11–21, 500 km),
    // c→d (21–31, 400 km, invalid: missed refuel).
    final entries = [
      refuel('a', day: 1, km: 10000, volume: 40, cents: 7000),
      refuel('b', day: 11, km: 10600, volume: 36, cents: 6300),
      refuel('c', day: 21, km: 11100, volume: 30, cents: 5200),
      refuel('d', day: 31, km: 11500, volume: 25, cents: 4400, missed: true),
    ];
    final chain = chainOf(entries);
    final readings = [
      reading('r1', 1, 9000),
      reading('r2', 31, 11600),
    ];

    test('"all" takes every segment, newest first', () {
      final report = ConsumptionReport.of(
        chain,
        const DateRangeFilter(),
        readings,
      );
      expect(
        [for (final s in report.segments) s.closing.id],
        ['d', 'c', 'b'],
      );
      expect(report.summary.segmentCount, 2);
      // Y: from the first to the last refuel of the fuel.
      expect(report.spanKm, 1500);
      expect(report.spanDays, 30);
      // X: the two valid segments; Y − X is the invalid one.
      expect(report.summary.km, 1100);
      expect(report.summary.days, 20);
      expect(report.uncoveredKm, 400);
      expect(report.uncoveredDays, 10);
    });

    test('a segment across the border of the dates is left out', () {
      // Days 5–25: b→c is inside; a→b opens on day 1 and c→d closes on
      // day 31, both outside.
      final report = ConsumptionReport.of(
        chain,
        const DateRangeFilter(
          from: CalendarDate(2026, 10, 5),
          to: CalendarDate(2026, 10, 25),
        ),
        readings,
      );
      expect([for (final s in report.segments) s.closing.id], ['c']);
      // Y runs from b to c, the refuels inside; X is that one segment.
      expect((report.spanKm, report.summary.km), (500, 500));
      expect(report.uncoveredKm, 0);
    });

    test('Y − X shows what could not be calculated', () {
      // Days 1–21 with b→c made invalid: Y = a→c, X = a→b only.
      final withHole = chainOf([
        refuel('a', day: 1, km: 10000, volume: 40),
        refuel('b', day: 11, km: 10600, volume: 36),
        refuel('p', day: 15, km: 10800, full: false),
        refuel('c', day: 21, km: 11100, volume: 30),
      ]);
      final report = ConsumptionReport.of(
        withHole,
        const DateRangeFilter(
          from: CalendarDate(2026, 10, 1),
          to: CalendarDate(2026, 10, 21),
        ),
        readings,
      );
      expect(report.segments, hasLength(2));
      expect(report.spanKm, 1100);
      expect(report.summary.km, 600);
      expect(report.uncoveredKm, 500);
      expect(report.spanDays, 20);
      expect(report.uncoveredDays, 10);
    });

    test('in km mode, Y is the typed range clipped to the readings', () {
      // 10 000–11 200 km: a→b and b→c are inside, c→d closes at 11 500.
      final report = ConsumptionReport.of(
        chain,
        const KmRangeFilter(fromKm: 10000, toKm: 11200),
        readings,
      );
      expect([for (final s in report.segments) s.closing.id], ['c', 'b']);
      expect(report.spanKm, 1200);
      // M: the dates of the first and last refuel with km in the range.
      expect(report.spanDays, 20);
      expect(report.summary.km, 1100);
      expect(report.uncoveredKm, 100);

      // A range wider than the readings is clipped to them.
      final wide = ConsumptionReport.of(
        chain,
        const KmRangeFilter(fromKm: 0, toKm: 99999),
        readings,
      );
      expect(wide.spanKm, 2600);
    });

    test('a km segment across the border is left out', () {
      final report = ConsumptionReport.of(
        chain,
        const KmRangeFilter(fromKm: 10300, toKm: 11500),
        readings,
      );
      // a→b opens at 10 000, outside.
      expect([for (final s in report.segments) s.closing.id], ['d', 'c']);
    });
  });

  group('fuel spend', () {
    test('totals, price per fuel and months, newest first', () {
      final entries = [
        refuel(
          'p1',
          date: const CalendarDate(2026, 9, 3),
          km: 1,
          volume: 40,
          cents: 7000,
        ),
        refuel(
          'p2',
          date: const CalendarDate(2026, 10, 3),
          km: 2,
          volume: 30,
          cents: 5000,
        ),
        refuel(
          'l1',
          date: const CalendarDate(2026, 10, 9),
          km: 3,
          volume: 50,
          cents: 4000,
          fuel: RefuelFuel.lpg,
        ),
        // No amount: counted, adds nothing.
        refuel('p3', date: const CalendarDate(2026, 10, 20), km: 4, volume: 10),
        // No volume: in the total, not in the price.
        refuel(
          'p4',
          date: const CalendarDate(2026, 10, 25),
          km: 5,
          cents: 1000,
        ),
      ];
      final report = FuelSpendReport.of(entries, const DateRangeFilter());
      expect(report.refuelCount, 5);
      expect(report.totalCents, 17000);
      expect(report.centsPerUnit[RefuelFuel.petrol], closeTo(12000 / 70, 1e-9));
      expect(report.centsPerUnit[RefuelFuel.lpg], 80);
      expect(
        [
          for (final m in report.months)
            (m.year, m.month, m.cents, m.refuelCount),
        ],
        [(2026, 10, 10000, 4), (2026, 9, 7000, 1)],
      );

      final october = FuelSpendReport.of(
        entries,
        const DateRangeFilter(from: CalendarDate(2026, 10, 1)),
      );
      expect(october.refuelCount, 4);
      expect(october.totalCents, 10000);
    });

    test('electric refuels count as spend, with no price per unit', () {
      final charge = LogEntry(
        id: 'e',
        vehicleId: 'v1',
        date: const CalendarDate(2026, 10, 1),
        km: 100,
        type: LogEntryType.refuel,
        costCents: 1200,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final report = FuelSpendReport.of([charge], const DateRangeFilter());
      expect((report.refuelCount, report.totalCents), (1, 1200));
      expect(report.centsPerUnit, isEmpty);
    });
  });

  group('km over time', () {
    test('steps between days, readings of one day grouped', () {
      final report = DistanceReport.of(
        [
          reading('r1', 1, 1000),
          reading('r2', 11, 1500),
          // Two readings on day 11: the later one counts.
          reading('r3', 11, 1600),
          reading('r4', 31, 2200),
        ],
        const DateRangeFilter(),
      );
      expect(
        [
          for (final s in report.steps)
            (s.date.day, s.km, s.kmSincePrevious, s.daysSincePrevious),
        ],
        [
          (31, 2200.0, 600.0, 20),
          (11, 1600.0, 600.0, 10),
          (1, 1000.0, null, null),
        ],
      );
      expect((report.km, report.days), (1200, 30));
      expect(report.kmPerDay, 40);
      expect(report.kmPerMonth, closeTo(40 * 365.25 / 12, 1e-9));
    });

    test('a single day never divides by zero', () {
      final report = DistanceReport.of(
        [reading('r1', 5, 1000), reading('r2', 5, 1100)],
        const DateRangeFilter(),
      );
      expect(report.steps, hasLength(1));
      expect((report.km, report.days), (0, 0));
      expect(report.kmPerDay, isNull);
      expect(report.kmPerMonth, isNull);
    });

    test('the km mode selects readings by their km', () {
      final report = DistanceReport.of(
        [
          reading('r1', 1, 1000),
          reading('r2', 11, 1500),
          reading('r3', 21, 2000),
        ],
        const KmRangeFilter(fromKm: 1200, toKm: 2000),
      );
      expect([for (final s in report.steps) s.km], [2000, 1500]);
      expect((report.km, report.days), (500, 10));
    });
  });
}
