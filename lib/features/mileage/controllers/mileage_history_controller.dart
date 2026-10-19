import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/mileage_reading.dart';

/// The odometer readings of a vehicle, by vehicle id: newest first, the
/// initial reading last, refreshed after every write (`Docs/03_features.md`,
/// U12). Empty for a vehicle that is missing or deleted.
final mileageReadingsProvider =
    StreamProvider.autoDispose.family<List<MileageReading>, String>(
  (ref, vehicleId) =>
      ref.watch(mileageReadingRepositoryProvider).watchByVehicle(vehicleId),
);
