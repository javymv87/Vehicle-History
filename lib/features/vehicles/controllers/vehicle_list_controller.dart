import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/owner.dart';
import '../../../data/models/vehicle.dart';
import '../../owners/controllers/owner_list_controller.dart';

/// A vehicle together with its owner, as shown in the list and the detail.
class VehicleWithOwner {
  /// Pairs [vehicle] with its [owner].
  const VehicleWithOwner({required this.vehicle, required this.owner});

  /// The vehicle.
  final Vehicle vehicle;

  /// The vehicle's owner. `null` only for a moment while the two streams
  /// catch up with each other, never in steady state.
  final Owner? owner;
}

/// Every live vehicle, ordered by plate, updated after every change.
final allVehiclesProvider = StreamProvider.autoDispose<List<Vehicle>>(
  (ref) => ref.watch(vehicleRepositoryProvider).watchAll(),
);

/// State of the vehicle list (the home screen): every live vehicle with its
/// owner, ordered by plate.
final vehicleListProvider =
    FutureProvider.autoDispose<List<VehicleWithOwner>>((ref) async {
  final vehicles = await ref.watch(allVehiclesProvider.future);
  final owners = await ref.watch(ownerListProvider.future);
  final ownersById = {for (final owner in owners) owner.id: owner};
  return [
    for (final vehicle in vehicles)
      VehicleWithOwner(vehicle: vehicle, owner: ownersById[vehicle.ownerId]),
  ];
});
