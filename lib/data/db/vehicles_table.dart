import 'package:drift/drift.dart';

import 'converters.dart';
import 'owners_table.dart';
import 'technical_columns.dart';

/// The `vehicles` table: the central entity of the app.
///
/// The plate is unique only among live rows (a partial index), so the plate
/// of a deleted vehicle can be reused.
@DataClassName('VehicleRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX vehicles_plate_live_unique '
  'ON vehicles (plate) WHERE deleted = 0',
)
@TableIndex(name: 'vehicles_owner_id', columns: {#ownerId})
class Vehicles extends Table with TechnicalColumns {
  /// Licence plate, trimmed and upper-case. Required and never blank.
  TextColumn get plate => text()();

  /// Optional friendly name.
  TextColumn get nickname => text().nullable()();

  /// Owning person. An owner cannot be removed while referenced.
  TextColumn get ownerId =>
      text().references(Owners, #id, onDelete: KeyAction.restrict)();

  /// Last known total odometer reading, in whole kilometres. Never negative.
  IntColumn get currentOdometerKm => integer()();

  /// Fuel type as a stable text code (see [FuelTypeConverter]).
  TextColumn get fuelType => text().map(const FuelTypeConverter())();

  /// Engine oil recommended by the manufacturer.
  TextColumn get recommendedEngineOil => text().nullable()();

  /// Other manufacturer notes.
  TextColumn get manufacturerNotes => text().nullable()();

  /// Photo path relative to the app support directory.
  TextColumn get photoPath => text().nullable()();

  // Written as SQL rather than with `Column.check`, whose self-referencing
  // getter trips the `recursive_getters` lint.
  @override
  List<String> get customConstraints => [
        "CHECK (length(trim(plate)) > 0)",
        "CHECK (current_odometer_km >= 0)",
      ];
}
