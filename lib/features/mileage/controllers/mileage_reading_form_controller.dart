import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/calendar_date.dart';
import '../../../data/models/mileage_reading.dart';
import '../../../data/models/vehicle.dart';
import '../../../shared/utils/action_result.dart';

/// Identifies one reading form: the vehicle, and the reading being
/// corrected (`null` to add one).
typedef MileageReadingFormKey = ({String vehicleId, String? readingId});

/// What the reading form needs once loaded.
class MileageReadingFormData {
  /// Creates the loaded form data.
  const MileageReadingFormData({
    required this.vehicle,
    required this.lastReading,
    required this.editing,
  });

  /// The vehicle, or `null` when no live vehicle has the id in the path.
  final Vehicle? vehicle;

  /// The vehicle's last reading: the lower bound of a new reading, shown as
  /// a hint. `null` only when the vehicle is missing.
  final MileageReading? lastReading;

  /// The reading being corrected; `null` when adding one, or when the id in
  /// the path is not the vehicle's sole reading (it can no longer be
  /// corrected).
  final MileageReading? editing;
}

/// State of the "Update km" form, loaded once when the form opens so the
/// limits do not change under the user while they type.
class MileageReadingFormController
    extends AsyncNotifier<MileageReadingFormData> {
  /// Creates the controller for the form identified by [key].
  MileageReadingFormController(this.key);

  /// Vehicle of the form, and the reading corrected (`null` when adding).
  final MileageReadingFormKey key;

  @override
  Future<MileageReadingFormData> build() async {
    final vehicle =
        await ref.watch(vehicleRepositoryProvider).getById(key.vehicleId);
    if (vehicle == null) {
      return const MileageReadingFormData(
        vehicle: null,
        lastReading: null,
        editing: null,
      );
    }
    final repository = ref.watch(mileageReadingRepositoryProvider);
    final readingId = key.readingId;
    if (readingId == null) {
      return MileageReadingFormData(
        vehicle: vehicle,
        lastReading: await repository.getLast(vehicle.id),
        editing: null,
      );
    }
    // Only the sole reading of the vehicle can be corrected (U14).
    final readings = await repository.getByVehicle(vehicle.id);
    final sole = readings.length == 1 ? readings.single : null;
    return MileageReadingFormData(
      vehicle: vehicle,
      lastReading: readings.firstOrNull,
      editing: sole?.id == readingId ? sole : null,
    );
  }

  /// Adds the reading of [km] on [date], or corrects the edited one.
  ///
  /// Returns the saved reading, or the reason it was not saved.
  Future<ActionResult<MileageReading>> save({
    required CalendarDate date,
    required int km,
  }) {
    final repository = ref.read(mileageReadingRepositoryProvider);
    final readingId = key.readingId;
    return runAction(() {
      if (readingId != null) {
        return repository.updateInitial(readingId, date: date, km: km);
      }
      return repository.create(vehicleId: key.vehicleId, date: date, km: km);
    });
  }
}

/// The [MileageReadingFormController] for a vehicle and a reading id
/// (`null` to add one).
final mileageReadingFormControllerProvider = AsyncNotifierProvider.autoDispose
    .family<MileageReadingFormController, MileageReadingFormData,
        MileageReadingFormKey>(
  MileageReadingFormController.new,
);
