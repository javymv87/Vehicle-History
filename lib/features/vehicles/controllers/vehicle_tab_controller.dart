import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The tabs of the vehicle page, in display order (`Docs/03_features.md`,
/// U11, U25).
enum VehicleTab {
  /// The history entries, the default tab.
  history('history'),

  /// The odometer readings.
  mileage('mileage'),

  /// The vehicle's own attachments: registration, insurance policy, ...
  documents('documents'),

  /// The vehicle's own fields.
  details('details');

  const VehicleTab(this.queryValue);

  /// Value of the `tab` query parameter that opens this tab (U15), e.g.
  /// `/vehicles/<id>?tab=mileage`. Stable: deep links depend on it.
  final String queryValue;

  /// The tab named by the `tab` query parameter [value]; the history for a
  /// missing or unknown value.
  static VehicleTab fromQuery(String? value) => values.firstWhere(
        (tab) => tab.queryValue == value,
        orElse: () => history,
      );
}

/// A request to show [tab] on the open page of the vehicle [vehicleId].
///
/// Each request is a new object, so asking twice for the same tab still
/// notifies the listener.
class VehicleTabRequest {
  /// Creates the request.
  const VehicleTabRequest(this.vehicleId, this.tab);

  /// Vehicle whose page should switch.
  final String vehicleId;

  /// Tab to show.
  final VehicleTab tab;
}

/// Lets an action that finishes after its page is gone (the "Update" of the
/// odometer offer) bring the vehicle page, if open, to a tab.
///
/// The state is the last request, or `null`. The vehicle page listens and
/// switches when the request names its vehicle; with no page open the
/// request is simply ignored.
class VehicleTabRequestController extends Notifier<VehicleTabRequest?> {
  @override
  VehicleTabRequest? build() => null;

  /// Asks the page of the vehicle [vehicleId] to show [tab].
  void request(String vehicleId, VehicleTab tab) =>
      state = VehicleTabRequest(vehicleId, tab);
}

/// The app-wide [VehicleTabRequestController].
final vehicleTabRequestProvider =
    NotifierProvider<VehicleTabRequestController, VehicleTabRequest?>(
  VehicleTabRequestController.new,
);
