import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/log_entry.dart';
import '../../../data/models/log_entry_filter.dart';
import '../../../data/models/log_entry_type.dart';

/// The filters of one vehicle's history (`Docs/03_features.md`, U8).
///
/// Holds the filter currently applied; the history list follows it. Lives
/// as long as the vehicle page shows the history, so the filters reset when
/// the page is closed.
class LogEntryFilterController extends Notifier<LogEntryFilter> {
  /// Creates the controller for the history of the vehicle with
  /// [vehicleId].
  LogEntryFilterController(this.vehicleId);

  /// Id of the vehicle whose history is filtered.
  final String vehicleId;

  @override
  LogEntryFilter build() => LogEntryFilter.none;

  /// Applies [filter] as a whole, as the filter sheet does.
  void apply(LogEntryFilter filter) => state = filter;

  /// Removes the date range.
  void clearDateRange() => state = state.withDateRange(null, null);

  /// Stops filtering by [type].
  void removeType(LogEntryType type) => state = state.withoutType(type);

  /// Removes the text criterion.
  void clearText() => state = state.withText('');

  /// Removes every criterion ("Clear filters").
  void clear() => state = LogEntryFilter.none;
}

/// The [LogEntryFilterController] of a vehicle's history, by vehicle id.
final logEntryFilterProvider = NotifierProvider.autoDispose
    .family<LogEntryFilterController, LogEntryFilter, String>(
  LogEntryFilterController.new,
);

/// The history list of a vehicle, by vehicle id: the entries that pass the
/// current filter, newest first, refreshed after every write and every
/// filter change.
final logEntryHistoryProvider =
    StreamProvider.autoDispose.family<List<LogEntry>, String>((ref, vehicleId) {
  final filter = ref.watch(logEntryFilterProvider(vehicleId));
  return ref
      .watch(logEntryRepositoryProvider)
      .watchByVehicle(vehicleId, filter: filter);
});

/// A history entry by id, refreshed after every write; `null` when no live
/// entry has that id (unknown, deleted, or of a deleted vehicle), so the
/// detail page shows a not-found state instead of failing.
final logEntryDetailProvider =
    StreamProvider.autoDispose.family<LogEntry?, String>(
  (ref, entryId) => ref.watch(logEntryRepositoryProvider).watchById(entryId),
);
