import 'package:drift/drift.dart';

import 'app_database.dart';

/// Whether a vehicle row can be written to, as the repositories need to know
/// before every write on the vehicle or on what belongs to it.
enum VehicleState {
  /// Live and not archived: the normal, writable state.
  active,

  /// Live but archived (schema v8): visible, read-only until reactivated.
  archived,

  /// Soft-deleted (in the Trash), or no row with that id.
  absent,
}

/// The one query behind every "is this vehicle writable" check, shared by
/// the DAOs of the entries, the readings and the attachments.
///
/// The foreign key alone cannot tell: a soft-deleted or archived vehicle
/// still has a row.
extension VehicleStateQuery on DatabaseAccessor<AppDatabase> {
  /// The [VehicleState] of the vehicle with [vehicleId].
  Future<VehicleState> vehicleStateOf(String vehicleId) async {
    final vehicles = attachedDatabase.vehicles;
    final row = await (attachedDatabase.selectOnly(vehicles)
          ..addColumns([vehicles.archivedAt])
          ..where(
            vehicles.id.equals(vehicleId) & vehicles.deleted.equals(false),
          )
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return VehicleState.absent;
    return row.read(vehicles.archivedAt) == null
        ? VehicleState.active
        : VehicleState.archived;
  }
}
