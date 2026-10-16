import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'vehicle_list_controller.dart';

/// State of the vehicle detail page for the vehicle id taken from the path.
///
/// `null` when no live vehicle has that id (unknown or deleted), so the page
/// shows a not-found state instead of failing. Rebuilt after every change to
/// the vehicles or the owners.
final vehicleDetailProvider =
    FutureProvider.autoDispose.family<VehicleWithOwner?, String>(
  (ref, id) async {
    final items = await ref.watch(vehicleListProvider.future);
    return items.where((item) => item.vehicle.id == id).firstOrNull;
  },
);
