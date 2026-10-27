import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/owner.dart';
import '../../../data/models/vehicle.dart';
import '../../owners/controllers/owner_list_controller.dart';

/// A vehicle together with its owner, as shown in the lists and the detail.
class VehicleWithOwner {
  /// Pairs [vehicle] with its [owner].
  const VehicleWithOwner({required this.vehicle, required this.owner});

  /// The vehicle.
  final Vehicle vehicle;

  /// The vehicle's owner. `null` only for a moment while the two streams
  /// catch up with each other, never in steady state.
  final Owner? owner;
}

/// Every active vehicle (live and not archived), ordered by plate, updated
/// after every change.
final activeVehiclesProvider = StreamProvider.autoDispose<List<Vehicle>>(
  (ref) => ref.watch(vehicleRepositoryProvider).watchActive(),
);

/// Every archived vehicle that is not in the Trash, most recently archived
/// first, updated after every change.
final archivedVehiclesProvider = StreamProvider.autoDispose<List<Vehicle>>(
  (ref) => ref.watch(vehicleRepositoryProvider).watchArchived(),
);

/// Pairs each of [vehicles] with its owner.
Future<List<VehicleWithOwner>> _withOwners(
  Ref ref,
  List<Vehicle> vehicles,
) async {
  final owners = await ref.watch(ownerListProvider.future);
  final ownersById = {for (final owner in owners) owner.id: owner};
  return [
    for (final vehicle in vehicles)
      VehicleWithOwner(vehicle: vehicle, owner: ownersById[vehicle.ownerId]),
  ];
}

/// State of the vehicle list (the home screen): every active vehicle with
/// its owner, ordered by plate.
final vehicleListProvider =
    FutureProvider.autoDispose<List<VehicleWithOwner>>((ref) async {
  final vehicles = await ref.watch(activeVehiclesProvider.future);
  return _withOwners(ref, vehicles);
});

/// State of the archived vehicles list: every archived vehicle with its
/// owner, most recently archived first.
final archivedVehicleListProvider =
    FutureProvider.autoDispose<List<VehicleWithOwner>>((ref) async {
  final vehicles = await ref.watch(archivedVehiclesProvider.future);
  return _withOwners(ref, vehicles);
});
