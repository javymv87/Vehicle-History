import 'package:flutter/material.dart';

import '../../data/models/vehicle_kind.dart';

/// Icon of a [VehicleKind], shared by the kind choice, the list and the
/// detail, so a kind always looks the same.
extension VehicleKindIcon on VehicleKind {
  /// The Material icon of this kind.
  IconData get icon => switch (this) {
        VehicleKind.car => Icons.directions_car,
        VehicleKind.van => Icons.airport_shuttle,
        VehicleKind.motorcycle => Icons.two_wheeler,
        VehicleKind.moped => Icons.moped,
      };
}
