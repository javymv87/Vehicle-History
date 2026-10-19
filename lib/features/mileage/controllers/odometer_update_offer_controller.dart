import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/calendar_date.dart';
import '../../../data/models/mileage_reading.dart';
import '../../../shared/utils/action_result.dart';
import '../../vehicles/controllers/vehicle_tab_controller.dart';

/// Carries out the offer to update the odometer shown after saving an entry
/// (`Docs/03_features.md`, E3): the only bridge from an entry's km to the
/// odometer history, and only on an explicit tap.
///
/// Kept alive (not auto-disposed): the offer snackbar outlives the entry
/// form that showed it. Stateless otherwise.
class OdometerUpdateOfferController extends Notifier<void> {
  @override
  void build() {}

  /// Adds a reading of [km] on [date] to the vehicle [vehicleId], then asks
  /// its page, if open, to show the Mileage tab.
  ///
  /// The repository checks the rules again, so an offer that became stale
  /// (a newer reading added meanwhile) fails instead of writing.
  Future<ActionResult<MileageReading>> accept({
    required String vehicleId,
    required CalendarDate date,
    required int km,
  }) async {
    final result = await runAction(
      () => ref
          .read(mileageReadingRepositoryProvider)
          .create(vehicleId: vehicleId, date: date, km: km),
    );
    if (result is ActionSuccess) {
      ref
          .read(vehicleTabRequestProvider.notifier)
          .request(vehicleId, VehicleTab.mileage);
    }
    return result;
  }
}

/// The app-wide [OdometerUpdateOfferController].
final odometerUpdateOfferControllerProvider =
    NotifierProvider<OdometerUpdateOfferController, void>(
  OdometerUpdateOfferController.new,
);
