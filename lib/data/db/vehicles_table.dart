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

  /// Vehicle kind as a stable text code (see [VehicleKindConverter]).
  ///
  /// Added in schema v2 with a default, so every v1 vehicle became a car.
  TextColumn get kind => text()
      .map(const VehicleKindConverter())
      .withDefault(const Constant('car'))();

  /// Make as shown to the user, e.g. "Fiat". Always the source of truth for
  /// display, also when [makeSlug] is set. Nullable only for v1 rows.
  TextColumn get make => text().nullable()();

  /// VehiclesDB make slug, e.g. `fiat`; `null` for a make typed by hand.
  TextColumn get makeSlug => text().nullable()();

  /// Model as shown to the user, e.g. "Punto". Nullable only for v1 rows.
  TextColumn get model => text().nullable()();

  /// VehiclesDB model slug, e.g. `punto`; `null` for a model typed by hand.
  TextColumn get modelSlug => text().nullable()();

  /// Model year, e.g. 2012.
  ///
  /// The range CHECK is a column constraint, not one of [customConstraints]:
  /// the column was added by `ALTER TABLE ... ADD COLUMN` in v2, which cannot
  /// add a table constraint without recreating the table.
  IntColumn get modelYear => integer()
      .nullable()
      .customConstraint('NULL CHECK (model_year BETWEEN 1886 AND 2100)')();

  /// Version and trim as free text, e.g. "1.2 69 CV Lounge".
  TextColumn get version => text().nullable()();

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

  /// Day the vehicle was archived (schema v8), as `yyyy-MM-dd` text; `null`
  /// while it is active. A calendar day, like the reading it is dated with.
  TextColumn get archivedAt =>
      text().map(const CalendarDateConverter()).nullable()();

  /// Why it was archived, as a stable text code (see
  /// [ArchiveReasonConverter]); `null` while active.
  TextColumn get archiveReason =>
      text().map(const ArchiveReasonConverter()).nullable()();

  /// Free note of the archive; `null` while active or when none was typed.
  TextColumn get archiveNote => text().nullable()();

  /// Final km recorded at archive time, the snapshot of the reading inserted
  /// then; `null` while active or when no km was given.
  ///
  /// The CHECK is a column constraint, as for [modelYear]: the column was
  /// added by `ALTER TABLE ... ADD COLUMN` in v8.
  IntColumn get archivedKm =>
      integer().nullable().customConstraint('NULL CHECK (archived_km >= 0)')();

  // Written as SQL rather than with `Column.check`, whose self-referencing
  // getter trips the `recursive_getters` lint.
  @override
  List<String> get customConstraints => [
        "CHECK (length(trim(plate)) > 0)",
        "CHECK (current_odometer_km >= 0)",
      ];
}
