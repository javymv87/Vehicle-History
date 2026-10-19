import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/trashed_vehicle.dart';
import '../../../data/models/vehicle.dart';
import '../../../shared/utils/action_result.dart';

/// The vehicles in the Trash, most recently deleted first, updated after
/// every change (U17).
final trashedVehiclesProvider =
    StreamProvider.autoDispose<List<TrashedVehicle>>(
  (ref) => ref.watch(vehicleRepositoryProvider).watchTrashed(),
);

/// How many vehicles are in the Trash, for the menu entry of the vehicle
/// list. 0 while loading or on error, so the menu always opens.
final trashCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(trashedVehiclesProvider).value?.length ?? 0,
);

/// The actions of the Trash page: restore, permanent delete, empty.
///
/// Stateless: the list itself is [trashedVehiclesProvider], which refreshes
/// after every write. Kept alive like the deletion controllers, so an action
/// still running when the page closes finishes normally.
class TrashController extends Notifier<void> {
  @override
  void build() {}

  /// Brings the vehicle with [id] back from the Trash with its entries and
  /// readings (U18).
  ///
  /// Fails with [ActionError.duplicatePlate] if a live vehicle took the
  /// plate, or [ActionError.ownerNotFound] if the owner is no longer live.
  Future<ActionResult<Vehicle>> restore(String id) =>
      runAction(() => ref.read(vehicleRepositoryProvider).restore(id));

  /// Removes the vehicle with [id], its entries and readings for good.
  Future<ActionResult<void>> purge(String id) =>
      runAction(() => ref.read(vehicleRepositoryProvider).purge(id));

  /// Removes every vehicle in the Trash for good. Succeeds with how many
  /// were removed.
  Future<ActionResult<int>> purgeAll() =>
      runAction(() => ref.read(vehicleRepositoryProvider).purgeAllTrashed());
}

/// The app-wide [TrashController].
final trashControllerProvider = NotifierProvider<TrashController, void>(
  TrashController.new,
);
