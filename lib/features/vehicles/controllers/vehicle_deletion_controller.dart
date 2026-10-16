import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/vehicle.dart';
import '../../../shared/utils/action_result.dart';

/// Deletes vehicles and undoes those deletions.
///
/// The state is the id of the last vehicle deleted, which the "Undo"
/// snackbar can still restore, or `null`. The provider is kept alive (not
/// auto-disposed) because the snackbar outlives the detail page that started
/// the deletion.
class VehicleDeletionController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Soft-deletes the vehicle with [id].
  Future<ActionResult<void>> delete(String id) async {
    final result =
        await runAction(() => ref.read(vehicleRepositoryProvider).delete(id));
    if (result is ActionSuccess) state = id;
    return result;
  }

  /// Restores the vehicle with [id] deleted by [delete].
  ///
  /// Fails with [ActionError.duplicatePlate] if another vehicle took the
  /// plate in the meantime, or [ActionError.ownerNotFound] if the owner was
  /// deleted since.
  Future<ActionResult<Vehicle>> undo(String id) async {
    final result =
        await runAction(() => ref.read(vehicleRepositoryProvider).restore(id));
    if (state == id) state = null;
    return result;
  }
}

/// The app-wide [VehicleDeletionController].
final vehicleDeletionControllerProvider =
    NotifierProvider<VehicleDeletionController, String?>(
  VehicleDeletionController.new,
);
