import 'package:drift/drift.dart';

import 'converters.dart';
import 'technical_columns.dart';
import 'vehicles_table.dart';

/// The `log_entries` table: the history of every vehicle, one row per event.
///
/// One table for every entry type (CLAUDE.md §5): type-specific fields will
/// come as optional columns or linked tables, never as a table per type.
/// Added in schema v3.
@DataClassName('LogEntryRow')
@TableIndex(name: 'log_entries_vehicle_date', columns: {#vehicleId, #entryDate})
@TableIndex(name: 'log_entries_vehicle_type', columns: {#vehicleId, #type})
class LogEntries extends Table with TechnicalColumns {
  /// Vehicle the entry belongs to. A vehicle with entries cannot be removed
  /// from disk; soft-deleting it simply hides them.
  TextColumn get vehicleId =>
      text().references(Vehicles, #id, onDelete: KeyAction.restrict)();

  /// Day of the event as `yyyy-MM-dd` text, never a timestamp.
  TextColumn get entryDate => text().map(const CalendarDateConverter())();

  /// Odometer reading at the event, in kilometres. Never negative. `REAL`
  /// since schema v9, like `mileage_readings.km`.
  RealColumn get km => real().nullable()();

  /// Entry type as a stable text code (see [LogEntryTypeConverter]).
  TextColumn get type => text().map(const LogEntryTypeConverter())();

  /// Free text describing the event.
  TextColumn get description => text().nullable()();

  /// Total cost in euro cents. Never negative.
  IntColumn get costCents => integer().nullable()();

  // Written as SQL rather than with `Column.check`, whose self-referencing
  // getter trips the `recursive_getters` lint. A NULL value passes a CHECK.
  @override
  List<String> get customConstraints => [
        "CHECK (km >= 0)",
        "CHECK (cost_cents >= 0)",
      ];
}
