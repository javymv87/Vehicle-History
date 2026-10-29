import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/archive_reason.dart';
import '../../../data/models/calendar_date.dart';
import '../../../data/models/mileage_reading.dart';
import '../../../data/models/vehicle.dart';
import '../../../shared/utils/action_result.dart';
import 'vehicle_detail_controller.dart';

/// Whether the vehicle with the given id is archived, so every screen that
/// can write to it or to what belongs to it hides its add, edit and delete
/// affordances (`Docs/03_features.md`, "Archivo"). `false` while loading
/// and for an unknown vehicle: the repositories refuse the write anyway.
final vehicleReadOnlyProvider = Provider.autoDispose.family<bool, String>(
  (ref, vehicleId) =>
      ref.watch(vehicleByIdProvider(vehicleId)).value?.isArchived ?? false,
);

/// Archives and reactivates vehicles.
///
/// Stateless: both actions finish before their page changes, so nothing
/// outlives the page. A [Notifier] all the same, so the page triggers the
/// actions through `ref.read(...).archive(...)` as every other action.
class VehicleArchiveController extends Notifier<void> {
  @override
  void build() {}

  /// The last reading of the vehicle with [id], prefilled as the final km
  /// of the archive dialog; `null` when it has none.
  Future<MileageReading?> lastReading(String id) =>
      ref.read(mileageReadingRepositoryProvider).getLast(id);

  /// Archives the vehicle with [id] on [date] for [reason], adding the
  /// final reading of [km] when given (`VehicleRepository.archive`).
  ///
  /// Fails with [ActionError.invalidInput] when the reading is refused
  /// (km below the last reading, day out of range), which the dialog has
  /// normally caught already.
  Future<ActionResult<Vehicle>> archive(
    String id, {
    required ArchiveReason reason,
    required CalendarDate date,
    double? km,
    String? note,
  }) =>
      runAction(
        () => ref.read(vehicleRepositoryProvider).archive(
              id,
              reason: reason,
              date: date,
              km: km,
              note: note,
            ),
      );

  /// Reactivates the archived vehicle with [id].
  Future<ActionResult<Vehicle>> reactivate(String id) =>
      runAction(() => ref.read(vehicleRepositoryProvider).reactivate(id));
}

/// The app-wide [VehicleArchiveController].
final vehicleArchiveControllerProvider =
    NotifierProvider<VehicleArchiveController, void>(
  VehicleArchiveController.new,
);
