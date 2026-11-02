import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/fuel_consumption.dart';
import '../../../data/models/log_entry.dart';
import '../../../data/models/log_entry_filter.dart';
import '../../../data/models/log_entry_type.dart';
import '../../vehicles/controllers/vehicle_detail_controller.dart';

/// The live refuels of the vehicle with the id, newest first, refreshed
/// after every write.
final vehicleRefuelsProvider =
    StreamProvider.autoDispose.family<List<LogEntry>, String>(
  (ref, vehicleId) => ref.watch(logEntryRepositoryProvider).watchByVehicle(
        vehicleId,
        filter: const LogEntryFilter(types: {LogEntryType.refuel}),
      ),
);

/// The full-tank chains of the vehicle with the id
/// (`Docs/04_maintenance_logic.md`): one per fuel its fuel type allows,
/// none for an electric or missing vehicle. Derived again after every
/// write, never stored.
final fuelChainsProvider =
    FutureProvider.autoDispose.family<List<FuelChain>, String>(
  (ref, vehicleId) async {
    final vehicle = await ref.watch(vehicleByIdProvider(vehicleId).future);
    final refuels = await ref.watch(vehicleRefuelsProvider(vehicleId).future);
    if (vehicle == null) return const [];
    return FuelChain.allOf(refuels, vehicle.fuelType);
  },
);

/// What the refuel [entryId] is in its chain, among [chains]; `null` when
/// it is in none (an electric vehicle's refuel, another type).
RefuelRole? refuelRoleIn(List<FuelChain> chains, String entryId) {
  for (final chain in chains) {
    if (chain.roleOf(entryId) case final role?) return role;
  }
  return null;
}
