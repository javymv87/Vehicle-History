import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/app_routes.dart';
import '../../../data/models/log_entry.dart';
import '../../../data/models/log_entry_filter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../controllers/log_entry_history_controller.dart';
import 'log_entry_filter_sheet.dart';
import 'log_entry_tile.dart';
import 'log_entry_type_icon.dart';

/// Opens the filter sheet for the history of [vehicleId] and applies what
/// the user chooses. Shared by the filter button of the vehicle page.
Future<void> openLogEntryFilters(
  BuildContext context,
  WidgetRef ref,
  String vehicleId,
) async {
  final controller = ref.read(logEntryFilterProvider(vehicleId).notifier);
  final chosen = await showLogEntryFilterSheet(
    context,
    ref.read(logEntryFilterProvider(vehicleId)),
  );
  if (chosen != null) controller.apply(chosen);
}

/// The history tab of a vehicle (`Docs/03_features.md`, U6–U9): the active
/// filters as removable chips, then the entries newest first, grouped by
/// month under a small header.
class LogEntryHistoryView extends ConsumerWidget {
  /// Creates the history of the vehicle with [vehicleId].
  const LogEntryHistoryView({super.key, required this.vehicleId});

  /// Id of the vehicle whose history is shown.
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(logEntryFilterProvider(vehicleId));
    final entries = ref.watch(logEntryHistoryProvider(vehicleId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!filter.isEmpty)
          _ActiveFilters(vehicleId: vehicleId, filter: filter),
        Expanded(
          child: AsyncValueView(
            value: entries,
            data: (entries) {
              if (entries.isNotEmpty) {
                return _HistoryList(vehicleId: vehicleId, entries: entries);
              }
              if (filter.isEmpty) {
                // The FAB is the only "add": the empty state never repeats it.
                return MessageView(
                  icon: Icons.history,
                  message: l10n.historyEmpty,
                );
              }
              return MessageView(
                icon: Icons.filter_alt_off,
                message: l10n.historyNoMatches,
                action: FilledButton.tonal(
                  onPressed: () => ref
                      .read(logEntryFilterProvider(vehicleId).notifier)
                      .clear(),
                  child: Text(l10n.clearFilters),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The chips of the active filters, each removable, and "Clear filters".
class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.vehicleId, required this.filter});

  final String vehicleId;
  final LogEntryFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(logEntryFilterProvider(vehicleId).notifier);
    final from = filter.from;
    final to = filter.to;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (filter.hasDateRange)
            InputChip(
              avatar: const Icon(Icons.date_range),
              label: Text(
                l10n.dateRangeValue(
                  (from ?? to)!.toLocalDateTime(),
                  (to ?? from)!.toLocalDateTime(),
                ),
              ),
              deleteButtonTooltipMessage: l10n.removeFilter,
              onPressed: () => openLogEntryFilters(context, ref, vehicleId),
              onDeleted: controller.clearDateRange,
            ),
          for (final type in filter.types)
            InputChip(
              avatar: Icon(type.icon),
              label: Text(type.label(l10n)),
              deleteButtonTooltipMessage: l10n.removeFilter,
              onPressed: () => openLogEntryFilters(context, ref, vehicleId),
              onDeleted: () => controller.removeType(type),
            ),
          if (filter.hasText)
            InputChip(
              avatar: const Icon(Icons.search),
              label: Text(l10n.filterTextChip(filter.text.trim())),
              deleteButtonTooltipMessage: l10n.removeFilter,
              onPressed: () => openLogEntryFilters(context, ref, vehicleId),
              onDeleted: controller.clearText,
            ),
          TextButton(
            onPressed: controller.clear,
            child: Text(l10n.clearFilters),
          ),
        ],
      ),
    );
  }
}

/// One item of the history list: a month header or an entry.
sealed class _HistoryItem {
  const _HistoryItem();
}

/// Header above the entries of one month.
final class _MonthHeader extends _HistoryItem {
  const _MonthHeader(this.year, this.month);

  final int year;
  final int month;
}

/// One entry row.
final class _EntryItem extends _HistoryItem {
  const _EntryItem(this.entry);

  final LogEntry entry;
}

/// The entries, already ordered newest first, with a header each time the
/// month changes. Lazy, so long histories scroll smoothly.
class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.vehicleId, required this.entries});

  final String vehicleId;
  final List<LogEntry> entries;

  /// Interleaves a [_MonthHeader] before the first entry of every month.
  static List<_HistoryItem> _items(List<LogEntry> entries) {
    final items = <_HistoryItem>[];
    (int, int)? month;
    for (final entry in entries) {
      final current = (entry.date.year, entry.date.month);
      if (current != month) {
        items.add(_MonthHeader(current.$1, current.$2));
        month = current;
      }
      items.add(_EntryItem(entry));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(entries);
    return ListView.builder(
      // Room at the bottom so the FAB never covers the last entry.
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length,
      itemBuilder: (context, index) => switch (items[index]) {
        _MonthHeader(:final year, :final month) =>
          _MonthHeaderTile(year: year, month: month),
        _EntryItem(:final entry) => LogEntryTile(
            entry: entry,
            onTap: () => context.push(AppRoutes.entry(vehicleId, entry.id)),
          ),
      },
    );
  }
}

/// The small "October 2026" header of a month, in the app language.
class _MonthHeaderTile extends StatelessWidget {
  const _MonthHeaderTile({required this.year, required this.month});

  final int year;
  final int month;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = l10n.localeName;
    // Month names are lower-case in Italian and Spanish; a header starts
    // with a capital letter.
    final label = toBeginningOfSentenceCase(
      DateFormat.yMMMM(locale).format(DateTime(year, month)),
      locale,
    );
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
