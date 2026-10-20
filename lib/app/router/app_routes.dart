import '../../features/vehicles/controllers/vehicle_tab_controller.dart';

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

  /// Detail of the vehicle with [id], opened on [tab] (the history when
  /// omitted, which adds no query parameter).
  static String vehicle(String id, {VehicleTab? tab}) {
    final path = '$vehicles/${Uri.encodeComponent(id)}';
    return tab == null || tab == VehicleTab.history
        ? path
        : '$path?tab=${tab.queryValue}';
  }

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

  /// Form that adds an odometer reading to the vehicle with [vehicleId].
  static String newMileageReading(String vehicleId) =>
      '${vehicle(vehicleId)}/mileage/new';

  /// Form that corrects the reading [readingId] of the vehicle with
  /// [vehicleId], allowed only while it is the vehicle's sole reading.
  static String editMileageReading(String vehicleId, String readingId) =>
      '${vehicle(vehicleId)}/mileage/${Uri.encodeComponent(readingId)}/edit';

  /// The Trash: the deleted vehicles, restorable for 30 days.
  static const String trash = '/trash';

  /// The Backup page: export and import the backup package.
  static const String backup = '/backup';

  /// Detail of the owner with [id].
  static String owner(String id) => '$owners/${Uri.encodeComponent(id)}';

  /// Form that edits the owner with [id].
  static String editOwner(String id) => '${owner(id)}/edit';
}
