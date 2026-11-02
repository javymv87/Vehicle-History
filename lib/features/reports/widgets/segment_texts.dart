import '../../../data/models/fuel_consumption.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/utils/unit_formatter.dart';

/// One line with the figures of a computable [segment]: consumption,
/// distance and days, and the cost per distance when every amount is
/// known, e.g. `6.2 L/100 km · 540 km in 12 days · €8.90/100 km`.
String segmentSummaryText(
  FuelSegment segment,
  AppLocalizations l10n,
  UnitFormatter units,
) {
  final consumption =
      units.fuelConsumption(segment.fuel).format(segment.consumption ?? 0);
  final distanceAndDays = l10n.segmentDistanceDays(
    units.distance.format(segment.km ?? 0),
    segment.days,
  );
  final cost = segment.centsPerKm;
  return cost == null
      ? l10n.segmentSummary(consumption, distanceAndDays)
      : l10n.segmentSummaryWithCost(
          consumption,
          distanceAndDays,
          units.formatCostPerDistance(cost),
        );
}

/// The state line of [segment]: its figures when valid, the reason when it
/// cannot be computed; a suspicious one adds the amber sentence on a line
/// of its own ([segmentSuspicious] is shown apart where colour exists).
String segmentStateText(
  FuelSegment segment,
  AppLocalizations l10n,
  UnitFormatter units,
) {
  final problem = segment.problem;
  if (problem != null) return l10n.segmentInvalid(problem.label(l10n));
  return segmentSummaryText(segment, l10n, units);
}

/// What a refuel means for the consumption, as one or two lines
/// (`Docs/03_features.md`, refuel detail): the segment it closes, or why
/// there is none yet. `null` for a refuel without volume when [quiet], so
/// the message after saving stays the plain one.
String? refuelRoleText(
  RefuelRole role,
  AppLocalizations l10n,
  UnitFormatter units, {
  bool quiet = false,
}) =>
    switch (role) {
      ClosesSegment(:final segment) => segment.suspicious
          ? '${segmentStateText(segment, l10n, units)}\n'
              '${l10n.segmentSuspicious}'
          : segmentStateText(segment, l10n, units),
      FirstFullTank() => l10n.refuelFirstFullTank,
      PartOfSegment(:final segment) =>
        l10n.refuelPartOfSegment(segment.closing.date.toLocalDateTime()),
      CountsInNextSegment() => l10n.refuelCountsInNext,
      BeforeFirstFullTank() => l10n.refuelBeforeFirstFullTank,
      WithoutVolume() => quiet ? null : l10n.refuelWithoutVolume,
    };
