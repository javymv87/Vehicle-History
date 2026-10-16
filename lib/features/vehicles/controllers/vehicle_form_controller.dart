import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/fuel_type.dart';
import '../../../data/models/vehicle.dart';
import '../../../shared/utils/action_result.dart';

/// The values typed into the vehicle form, before they are saved.
///
/// Text is passed as typed: the repository trims it, upper-cases the plate
/// and stores blank optional fields as `null`.
class VehicleDraft {
  /// Creates a draft from the form fields.
  const VehicleDraft({
    required this.plate,
    this.nickname,
    required this.ownerId,
    required this.fuelType,
    this.currentOdometerKm,
    this.recommendedEngineOil,
    this.manufacturerNotes,
  });

  /// Licence plate. Required.
  final String plate;

  /// Optional friendly name.
  final String? nickname;

  /// Id of the selected owner.
  final String ownerId;

  /// Selected fuel type.
  final FuelType fuelType;

  /// Current odometer reading. Required when creating, ignored when editing:
  /// after creation it changes only through the odometer feature.
  final int? currentOdometerKm;

  /// Engine oil recommended by the manufacturer.
  final String? recommendedEngineOil;

  /// Other manufacturer notes.
  final String? manufacturerNotes;
}

/// State of the vehicle form: the vehicle being edited, or `null` when
/// creating.
///
/// Loaded once when the form opens, so the fields do not change under the
/// user while they type. When editing an id that matches no live vehicle the
/// state is also `null`; the page tells the two cases apart by its id.
class VehicleFormController extends AsyncNotifier<Vehicle?> {
  /// Creates the controller for the vehicle with [vehicleId], or for a new
  /// vehicle when it is `null`.
  VehicleFormController(this.vehicleId);

  /// Id of the vehicle being edited; `null` when creating.
  final String? vehicleId;

  @override
  Future<Vehicle?> build() async {
    final id = vehicleId;
    if (id == null) return null;
    return ref.watch(vehicleRepositoryProvider).getById(id);
  }

  /// Creates or updates the vehicle from [draft].
  ///
  /// Returns the saved vehicle, or the reason it was not saved (for example
  /// [ActionError.duplicatePlate]).
  Future<ActionResult<Vehicle>> save(VehicleDraft draft) {
    final repository = ref.read(vehicleRepositoryProvider);
    final id = vehicleId;
    return runAction(() {
      if (id != null) {
        return repository.update(
          id,
          plate: draft.plate,
          nickname: draft.nickname,
          ownerId: draft.ownerId,
          fuelType: draft.fuelType,
          recommendedEngineOil: draft.recommendedEngineOil,
          manufacturerNotes: draft.manufacturerNotes,
          // The form has no photo field yet: keep the stored one.
          photoPath: state.value?.photoPath,
        );
      }
      final km = draft.currentOdometerKm;
      if (km == null) {
        throw ArgumentError.notNull('draft.currentOdometerKm');
      }
      return repository.create(
        plate: draft.plate,
        nickname: draft.nickname,
        ownerId: draft.ownerId,
        currentOdometerKm: km,
        fuelType: draft.fuelType,
        recommendedEngineOil: draft.recommendedEngineOil,
        manufacturerNotes: draft.manufacturerNotes,
      );
    });
  }
}

/// The [VehicleFormController] for a vehicle id (`null` to create one).
final vehicleFormControllerProvider = AsyncNotifierProvider.autoDispose
    .family<VehicleFormController, Vehicle?, String?>(
  VehicleFormController.new,
);
