import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/status_colors.dart';
import '../../../data/models/fuel_consumption.dart';
import '../../../data/models/log_entry.dart';
import '../../../data/models/mileage_reading.dart';
import '../../../data/models/refuel.dart';
import '../../../data/models/report_filter.dart';
import '../../../data/models/vehicle.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/utils/money.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../mileage/controllers/mileage_history_controller.dart';
import '../../settings/controllers/settings_controller.dart';
import '../../vehicles/controllers/vehicle_detail_controller.dart';
import '../controllers/fuel_chains_controller.dart';
import '../controllers/report_filter_controller.dart';

/// The Reports tab of a vehicle (`Docs/03_features.md`, "Informes"):
/// read-only, the same on an archived vehicle. A shared filter on top,
/// then the consumption report (not for an electric vehicle), the fuel
/// spend and the distance over time. Everything is derived from the
/// entries and readings on every change; nothing is stored or written.
class ReportsView extends ConsumerWidget {
  /// Creates the reports of the vehicle with [vehicleId].
  const ReportsView({super.key, required this.vehicleId});

  /// Id of the vehicle whose reports are shown.
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(vehicleByIdProvider(vehicleId));
    final readings = ref.watch(mileageReadingsProvider(vehicleId));
    final refuels = ref.watch(vehicleRefuelsProvider(vehicleId));
    final chains = ref.watch(fuelChainsProvider(vehicleId));
    final state = ref.watch(reportFilterProvider(vehicleId));
    // One loading or error state for the four sources.
    final all = switch ((vehicle, readings, refuels, chains)) {
      (
        AsyncData(value: final v?),
        AsyncData(value: final r),
        AsyncData(value: final e),
        AsyncData(value: final c),
      ) =>
        AsyncValue.data((v, r, e, c)),
      (AsyncError(:final error, :final stackTrace), _, _, _) ||
      (_, AsyncError(:final error, :final stackTrace), _, _) ||
      (_, _, AsyncError(:final error, :final stackTrace), _) ||
      (_, _, _, AsyncError(:final error, :final stackTrace)) =>
        AsyncValue<
            (
              Vehicle,
              List<MileageReading>,
              List<LogEntry>,
              List<FuelChain>
            )>.error(error, stackTrace),
      _ => const AsyncValue<
          (
            Vehicle,
            List<MileageReading>,
            List<LogEntry>,
            List<FuelChain>
          )>.loading(),
    };
    return AsyncValueView(
      value: all,
      data: (data) {
        final (vehicle, readings, refuels, chains) = data;
        final kms = [for (final r in readings) r.km];
        final firstKm = kms.isEmpty ? 0.0 : kms.reduce((a, b) => a < b ? a : b);
        final lastKm = kms.isEmpty ? 0.0 : kms.reduce((a, b) => a > b ? a : b);
        final filter = state.filterOn(
          calendarDateOf(DateTime.now()),
          firstKm: firstKm,
          lastKm: lastKm,
        );
        return ListView(
          key: const ValueKey('reports-list'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _FilterBar(
              vehicleId: vehicleId,
              state: state,
              firstKm: firstKm,
              lastKm: lastKm,
            ),
            const SizedBox(height: 16),
            if (chains.isNotEmpty) ...[
              _ConsumptionCard(
                vehicleId: vehicleId,
                chains: chains,
                selected: state.fuel ?? chains.first.fuel,
                filter: filter,
                readings: readings,
              ),
              const SizedBox(height: 16),
            ],
            _FuelSpendCard(
              report: FuelSpendReport.of(refuels, filter),
              perFuel: vehicle.fuelType.refuelFuels.length > 1,
            ),
            const SizedBox(height: 16),
            _DistanceCard(report: DistanceReport.of(readings, filter)),
          ],
        );
      },
    );
  }
}

/// The shared filter: dates (presets or two days) or an odometer range.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.vehicleId,
    required this.state,
    required this.firstKm,
    required this.lastKm,
  });

  final String vehicleId;
  final ReportFilterState state;
  final double firstKm;
  final double lastKm;

  /// Opens the date picker on [initial] and returns the chosen day.
  Future<DateTime?> _pickDate(BuildContext context, DateTime? initial) =>
      showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(reportFilterProvider(vehicleId).notifier);
    final from = state.customFrom;
    final to = state.customTo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ReportFilterMode>(
          key: const ValueKey('report-filter-mode'),
          segments: [
            ButtonSegment(
              value: ReportFilterMode.dates,
              icon: const Icon(Icons.date_range),
              label: Text(l10n.reportFilterDates),
            ),
            ButtonSegment(
              value: ReportFilterMode.odometer,
              icon: const Icon(Icons.speed),
              label: Text(l10n.reportFilterOdometer),
            ),
          ],
          selected: {state.mode},
          onSelectionChanged: (selection) =>
              controller.setMode(selection.single),
        ),
        const SizedBox(height: 12),
        if (state.mode == ReportFilterMode.dates) ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (preset, label) in [
                (ReportDatePreset.all, l10n.reportPresetAll),
                (ReportDatePreset.months12, l10n.reportPreset12Months),
                (ReportDatePreset.days90, l10n.reportPreset90Days),
                (ReportDatePreset.custom, l10n.reportPresetCustom),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: state.preset == preset,
                  onSelected: (_) => controller.setPreset(preset),
                ),
            ],
          ),
          if (state.preset == ReportDatePreset.custom) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      from == null
                          ? l10n.reportFrom
                          : l10n.dateValue(from.toLocalDateTime()),
                    ),
                    onPressed: () async {
                      final picked =
                          await _pickDate(context, from?.toLocalDateTime());
                      if (picked != null) {
                        controller.setCustomDates(calendarDateOf(picked), to);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      to == null
                          ? l10n.reportTo
                          : l10n.dateValue(to.toLocalDateTime()),
                    ),
                    onPressed: () async {
                      final picked =
                          await _pickDate(context, to?.toLocalDateTime());
                      if (picked != null) {
                        controller.setCustomDates(from, calendarDateOf(picked));
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ] else
          _KmRangeFields(
            vehicleId: vehicleId,
            fromKm: state.fromKm ?? firstKm,
            toKm: state.toKm ?? lastKm,
          ),
      ],
    );
  }
}

/// The two ends of the odometer range, typed in the distance unit and
/// prefilled with the vehicle's first and last reading.
class _KmRangeFields extends ConsumerStatefulWidget {
  const _KmRangeFields({
    required this.vehicleId,
    required this.fromKm,
    required this.toKm,
  });

  final String vehicleId;
  final double fromKm;
  final double toKm;

  @override
  ConsumerState<_KmRangeFields> createState() => _KmRangeFieldsState();
}

class _KmRangeFieldsState extends ConsumerState<_KmRangeFields> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    final distance = readUnitFormatter(context, ref).distance;
    _from.text = distance.inputText(widget.fromKm);
    _to.text = distance.inputText(widget.toKm);
    _filled = true;
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  /// Applies the two fields; a blank or malformed end follows the readings.
  void _apply() {
    final distance = readUnitFormatter(context, ref).distance;
    double? parse(TextEditingController field, double shown) =>
        field.text.trim().isEmpty
            ? null
            : distance.parse(field.text, sameAs: shown);
    ref.read(reportFilterProvider(widget.vehicleId).notifier).setKmRange(
          parse(_from, widget.fromKm),
          parse(_to, widget.toKm),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final symbol = unitFormatterOf(context, ref).distance.symbol;
    InputDecoration decoration(String label) => InputDecoration(
          labelText: label,
          suffixText: symbol,
          border: const OutlineInputBorder(),
        );
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('report-km-from'),
            controller: _from,
            decoration: decoration(l10n.reportFrom),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => _apply(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            key: const ValueKey('report-km-to'),
            controller: _to,
            decoration: decoration(l10n.reportTo),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => _apply(),
          ),
        ),
      ],
    );
  }
}

/// A report card: a title, then its content.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// One figure of a report: its label and its value, which wraps under
/// large text instead of overflowing.
class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

/// A short text inside a card: an empty state or an explanation.
class _CardText extends StatelessWidget {
  const _CardText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
}

/// Report 1: the consumption of one chain, its coverage and its segments.
class _ConsumptionCard extends ConsumerWidget {
  const _ConsumptionCard({
    required this.vehicleId,
    required this.chains,
    required this.selected,
    required this.filter,
    required this.readings,
  });

  final String vehicleId;
  final List<FuelChain> chains;
  final RefuelFuel selected;
  final ReportFilter filter;
  final List<MileageReading> readings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = unitFormatterOf(context, ref);
    final chain = chains.firstWhere(
      (c) => c.fuel == selected,
      orElse: () => chains.first,
    );
    final report = ConsumptionReport.of(chain, filter, readings);
    final summary = report.summary;
    final fuel = chain.fuel;
    final none = l10n.valueNone;
    return _ReportCard(
      key: const ValueKey('report-consumption'),
      title: l10n.reportConsumptionTitle,
      children: [
        if (chains.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final c in chains)
                  ChoiceChip(
                    label: Text(c.fuel.label(l10n)),
                    selected: c.fuel == fuel,
                    onSelected: (_) => ref
                        .read(reportFilterProvider(vehicleId).notifier)
                        .setFuel(c.fuel),
                  ),
              ],
            ),
          ),
        if (report.refuelCount > 0) ...[
          _Figure(
            l10n.reportAverageConsumption,
            switch (summary.consumption) {
              final value? => units.fuelConsumption(fuel).format(value),
              null => none,
            },
          ),
          _Figure(
            l10n.reportAverageCost,
            switch (summary.centsPerKm) {
              final value? => units.formatCostPerDistance(value),
              null => none,
            },
          ),
          _Figure(
            l10n.reportTotalVolume,
            units.fuelQuantity(fuel).format(summary.volume),
          ),
          _Figure(
            l10n.reportTotalSpent,
            formatEuroCents(summary.costCents, l10n.localeName),
          ),
          _Figure(l10n.reportValidSegments, '${summary.segmentCount}'),
          const SizedBox(height: 4),
          _CardText(
            l10n.reportCoverage(
              units.distance.format(summary.km),
              l10n.dayCount(summary.days),
              units.distance.format(report.spanKm),
              l10n.dayCount(report.spanDays),
            ),
            key: const ValueKey('report-coverage'),
          ),
        ],
        if (report.segments.isEmpty)
          _CardText(l10n.reportConsumptionEmpty)
        else ...[
          const Divider(),
          for (final segment in report.segments)
            _SegmentTile(vehicleId: vehicleId, segment: segment),
        ],
      ],
    );
  }
}

/// One segment of the consumption report: its dates, figures and state;
/// tapping it opens the closing refuel.
class _SegmentTile extends ConsumerWidget {
  const _SegmentTile({required this.vehicleId, required this.segment});

  final String vehicleId;
  final FuelSegment segment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = unitFormatterOf(context, ref);
    final theme = Theme.of(context);
    final status = theme.extension<StatusColors>()!;
    final (icon, color, label) = switch (segment.state) {
      SegmentState.valid => (
          Icons.check_circle_outline,
          status.ok,
          l10n.segmentStateValid,
        ),
      SegmentState.suspicious => (
          Icons.warning_amber,
          status.dueSoon,
          l10n.segmentStateSuspicious,
        ),
      SegmentState.invalid => (
          Icons.block,
          theme.colorScheme.onSurfaceVariant,
          l10n.segmentStateInvalid,
        ),
    };
    final distance = units.distance.format(segment.km ?? 0);
    final quantity = units.fuelQuantity(segment.fuel).format(segment.volume);
    final cents = segment.costCents;
    final figures = cents == null
        ? l10n.segmentFigures(distance, quantity)
        : l10n.segmentFiguresWithCost(
            distance,
            quantity,
            formatEuroCents(cents, l10n.localeName),
          );
    final state = segment.isComputable
        ? units.fuelConsumption(segment.fuel).format(segment.consumption!)
        : l10n.segmentInvalid(segment.problem!.label(l10n));
    return ListTile(
      leading: Icon(icon, color: color, semanticLabel: label),
      title: Text(
        l10n.segmentDates(
          segment.opening.date.toLocalDateTime(),
          segment.closing.date.toLocalDateTime(),
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state, style: theme.textTheme.bodyLarge),
          if (segment.isComputable) Text(figures),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
      onTap: () => context.push(
        AppRoutes.entry(vehicleId, segment.closing.id),
      ),
    );
  }
}

/// Report 2: the amounts of every refuel in the range.
class _FuelSpendCard extends ConsumerWidget {
  const _FuelSpendCard({required this.report, required this.perFuel});

  final FuelSpendReport report;

  /// Whether the average price is shown per fuel (bi-fuel vehicles).
  final bool perFuel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = unitFormatterOf(context, ref);
    final locale = l10n.localeName;
    return _ReportCard(
      key: const ValueKey('report-fuel-spend'),
      title: l10n.reportFuelSpendTitle,
      children: report.refuelCount == 0
          ? [_CardText(l10n.reportFuelSpendEmpty)]
          : [
              _Figure(
                l10n.reportTotalSpent,
                formatEuroCents(report.totalCents, locale),
              ),
              _Figure(l10n.reportRefuelCount, '${report.refuelCount}'),
              for (final MapEntry(key: fuel, value: cents)
                  in report.centsPerUnit.entries)
                _Figure(
                  perFuel
                      ? l10n.reportAveragePriceOf(fuel.label(l10n))
                      : l10n.reportAveragePrice,
                  units.formatUnitPrice(fuel, cents / 100),
                ),
              const Divider(),
              _CardText(l10n.reportSpendByMonth),
              for (final month in report.months)
                _Figure(
                  DateFormat.yMMMM(locale)
                      .format(DateTime(month.year, month.month)),
                  l10n.reportMonthSpend(
                    formatEuroCents(month.cents, locale),
                    month.refuelCount,
                  ),
                ),
            ],
    );
  }
}

/// Report 3: the distance over time, from the odometer readings.
class _DistanceCard extends ConsumerWidget {
  const _DistanceCard({required this.report});

  final DistanceReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = unitFormatterOf(context, ref);
    final none = l10n.valueNone;
    return _ReportCard(
      key: const ValueKey('report-distance'),
      title: l10n.reportDistanceTitle,
      children: report.steps.isEmpty
          ? [_CardText(l10n.reportDistanceEmpty)]
          : [
              _Figure(l10n.reportDistance, units.distance.format(report.km)),
              _Figure(l10n.reportDays, l10n.dayCount(report.days)),
              _Figure(
                l10n.reportPerDay,
                switch (report.kmPerDay) {
                  final value? => units.distance.format(value),
                  null => none,
                },
              ),
              _Figure(
                l10n.reportPerMonth,
                switch (report.kmPerMonth) {
                  final value? => units.distance.format(value),
                  null => none,
                },
              ),
              const Divider(),
              for (final step in report.steps)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.speed),
                  title: Text(units.distance.format(step.km)),
                  subtitle: Text(
                    switch ((step.kmSincePrevious, step.daysSincePrevious)) {
                      (final km?, final days?) => l10n.readingRowSubtitle(
                          step.date.toLocalDateTime(),
                          l10n.segmentDistanceDays(
                            l10n.readingDifference(units.distance.format(km)),
                            days,
                          ),
                        ),
                      _ => l10n.readingRowSubtitle(
                          step.date.toLocalDateTime(),
                          l10n.reportFirstReading,
                        ),
                    },
                  ),
                ),
            ],
    );
  }
}
