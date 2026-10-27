import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/vehicle.dart';
import '../../owners/controllers/owner_list_controller.dart';
import 'vehicle_list_controller.dart';

/// The live vehicle with the given id, active or archived, updated after
/// every change; `null` when it is unknown or in the Trash.
final vehicleByIdProvider = StreamProvider.autoDispose.family<Vehicle?, String>(
  (ref, id) => ref.watch(vehicleRepositoryProvider).watchById(id),
);

/// State of the vehicle detail page for the vehicle id taken from the path.
///
/// `null` when no live vehicle has that id (unknown or deleted), so the page
/// shows a not-found state instead of failing. An archived vehicle is found:
/// its page opens read-only. Rebuilt after every change to the vehicle or
/// the owners.
final vehicleDetailProvider =
    FutureProvider.autoDispose.family<VehicleWithOwner?, String>(
  (ref, id) async {
    final vehicle = await ref.watch(vehicleByIdProvider(id).future);
    if (vehicle == null) return null;
    final owners = await ref.watch(ownerListProvider.future);
    return VehicleWithOwner(
      vehicle: vehicle,
      owner: owners.where((o) => o.id == vehicle.ownerId).firstOrNull,
    );
  },
);
