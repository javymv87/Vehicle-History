/// Paths of every screen, in one place.
///
/// Identifiers always travel in the path, so any screen can be opened
/// directly by a deep link (for example from a reminder notification).
abstract final class AppRoutes {
  /// Vehicle list, the home screen.
  static const String vehicles = '/vehicles';

  /// Form that creates a vehicle.
  static const String newVehicle = '/vehicles/new';

  /// Owner list.
  static const String owners = '/owners';

  /// Form that creates an owner.
  ///
  /// When it is pushed, it pops with the id of the created owner, so the
  /// vehicle form can select it.
  static const String newOwner = '/owners/new';

  /// Detail of the vehicle with [id].
  static String vehicle(String id) => '$vehicles/${Uri.encodeComponent(id)}';

  /// Form that edits the vehicle with [id].
  static String editVehicle(String id) => '${vehicle(id)}/edit';

  /// Form that creates a history entry for the vehicle with [vehicleId].
  static String newEntry(String vehicleId) =>
      '${vehicle(vehicleId)}/entries/new';

  /// Detail of the history entry [entryId] of the vehicle with [vehicleId].
  ///
  /// Both ids travel in the path, so a future reminder notification can open
  /// the entry that produced it directly.
  static String entry(String vehicleId, String entryId) =>
      '${vehicle(vehicleId)}/entries/${Uri.encodeComponent(entryId)}';

  /// Form that edits the history entry [entryId] of the vehicle with
  /// [vehicleId].
  static String editEntry(String vehicleId, String entryId) =>
      '${entry(vehicleId, entryId)}/edit';

  /// Detail of the owner with [id].
  static String owner(String id) => '$owners/${Uri.encodeComponent(id)}';

  /// Form that edits the owner with [id].
  static String editOwner(String id) => '${owner(id)}/edit';
}
