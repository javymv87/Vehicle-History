import 'package:drift/drift.dart';

import 'converters.dart';
import 'technical_columns.dart';
import 'vehicles_table.dart';

/// The `mileage_readings` table: the odometer history of every vehicle, one
/// row per explicit "update km" by the user.
///
/// Independent of `log_entries` by design (`Docs/04_maintenance_logic.md`):
/// the km typed on an entry never lands here by itself. Every vehicle has at
/// least one live reading, its initial one (the oldest), and
/// `vehicles.current_odometer_km` always equals the km of its last live
/// reading. Added in schema v4.
@DataClassName('MileageReadingRow')
@TableIndex(
  name: 'mileage_readings_vehicle_date',
  columns: {#vehicleId, #readingDate},
)
class MileageReadings extends Table with TechnicalColumns {
  /// Vehicle the reading belongs to. A vehicle with readings cannot be
  /// removed from disk; soft-deleting it simply hides them.
  TextColumn get vehicleId =>
      text().references(Vehicles, #id, onDelete: KeyAction.restrict)();

  /// Day of the reading as `yyyy-MM-dd` text, never a timestamp.
  TextColumn get readingDate => text().map(const CalendarDateConverter())();

  /// Total odometer value, in kilometres. Never negative. `REAL` since
  /// schema v9: a value typed in another unit (100 mi = 160.9344 km) is
  /// stored exactly, so it reads back as what was typed.
  RealColumn get km => real()();

  // Written as SQL rather than with `Column.check`, whose self-referencing
  // getter trips the `recursive_getters` lint.
  @override
  List<String> get customConstraints => ["CHECK (km >= 0)"];
}
