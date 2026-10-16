import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/owner.dart';
import '../../../data/models/vehicle.dart';
import 'owner_list_controller.dart';

/// What the owner detail page shows: the owner and their live vehicles.
class OwnerDetail {
  /// Creates the detail of [owner] with their [vehicles].
  const OwnerDetail({required this.owner, required this.vehicles});

  /// The owner.
  final Owner owner;

  /// The owner's live vehicles, ordered by plate.
  final List<Vehicle> vehicles;
}

/// Live vehicles of the owner with the given id, ordered by plate.
final ownerVehiclesProvider =
    StreamProvider.autoDispose.family<List<Vehicle>, String>(
  (ref, ownerId) => ref.watch(vehicleRepositoryProvider).watchByOwner(ownerId),
);

/// State of the owner detail page for the owner id taken from the path.
///
/// `null` when no live owner has that id (unknown or deleted), so the page
/// shows a not-found state instead of failing. Rebuilt after every change to
/// the owners or to the owner's vehicles.
final ownerDetailProvider =
    FutureProvider.autoDispose.family<OwnerDetail?, String>((ref, id) async {
  final owners = await ref.watch(ownerListProvider.future);
  final owner = owners.where((o) => o.id == id).firstOrNull;
  if (owner == null) return null;
  final vehicles = await ref.watch(ownerVehiclesProvider(id).future);
  return OwnerDetail(owner: owner, vehicles: vehicles);
});
