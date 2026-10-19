import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/calendar_date.dart';
import '../../../data/models/log_entry.dart';
import '../../../data/models/log_entry_type.dart';
import '../../../data/models/mileage_reading.dart';
import '../../../data/models/vehicle.dart';
import '../../../shared/utils/action_result.dart';

/// Identifies one entry form: the vehicle, and the entry being edited
/// (`null` to create one).
typedef LogEntryFormKey = ({String vehicleId, String? entryId});

/// What the entry form needs once loaded: the vehicle (for the "Use current
/// km" chip), its odometer readings (for the km checks E2 and E3) and the
/// entry being edited.
class LogEntryFormData {
  /// Creates the loaded form data.
  const LogEntryFormData({
    required this.vehicle,
    required this.entry,
    this.readings = const [],
  });

  /// The vehicle, or `null` when no live vehicle has the id in the path.
  final Vehicle? vehicle;

  /// The entry being edited; `null` when creating, or when the id in the
  /// path matches no live entry of this vehicle.
  final LogEntry? entry;

  /// The vehicle's odometer readings, newest first; empty when the vehicle
  /// is missing.
  final List<MileageReading> readings;

  /// The vehicle's last odometer reading; `null` when the vehicle is
  /// missing.
  MileageReading? get lastReading => readings.firstOrNull;
}

/// The values typed into the entry form, before they are saved.
///
/// Amounts are already converted to cents and km to an integer: the form
/// validates and parses them, the repository checks the rules again.
class LogEntryDraft {
  /// Creates a draft from the form fields.
  const LogEntryDraft({
    required this.date,
    required this.type,
    this.km,
    this.description,
    this.costCents,
  });

  /// Day of the event.
  final CalendarDate date;

  /// Entry type.
  final LogEntryType type;

  /// Odometer reading, if typed.
  final int? km;

  /// Description as typed; the repository trims it.
  final String? description;

  /// Cost in euro cents, if typed.
  final int? costCents;
}

/// State of the entry form, loaded once when the form opens so the fields
/// do not change under the user while they type.
class LogEntryFormController extends AsyncNotifier<LogEntryFormData> {
  /// Creates the controller for the form identified by [key].
  LogEntryFormController(this.key);

  /// Vehicle of the form, and the entry edited (`null` when creating).
  final LogEntryFormKey key;

  @override
  Future<LogEntryFormData> build() async {
    final vehicle =
        await ref.watch(vehicleRepositoryProvider).getById(key.vehicleId);
    if (vehicle == null) {
      return const LogEntryFormData(vehicle: null, entry: null);
    }
    final readings = await ref
        .watch(mileageReadingRepositoryProvider)
        .getByVehicle(vehicle.id);
    final entryId = key.entryId;
    if (entryId == null) {
      return LogEntryFormData(
        vehicle: vehicle,
        entry: null,
        readings: readings,
      );
    }
    final entry = await ref.watch(logEntryRepositoryProvider).getById(entryId);
    // An entry reached through another vehicle's path is not found here.
    return LogEntryFormData(
      vehicle: vehicle,
      entry: entry?.vehicleId == vehicle.id ? entry : null,
      readings: readings,
    );
  }

  /// Creates or updates the entry from [draft].
  ///
  /// Returns the saved entry, or the reason it was not saved (for example
  /// [ActionError.vehicleNotFound]).
  Future<ActionResult<LogEntry>> save(LogEntryDraft draft) {
    final repository = ref.read(logEntryRepositoryProvider);
    final entryId = key.entryId;
    return runAction(() {
      if (entryId != null) {
        return repository.update(
          entryId,
          date: draft.date,
          km: draft.km,
          type: draft.type,
          description: draft.description,
          costCents: draft.costCents,
        );
      }
      return repository.create(
        vehicleId: key.vehicleId,
        date: draft.date,
        km: draft.km,
        type: draft.type,
        description: draft.description,
        costCents: draft.costCents,
      );
    });
  }
}

/// The [LogEntryFormController] for a vehicle and an entry id (`null` to
/// create one).
final logEntryFormControllerProvider = AsyncNotifierProvider.autoDispose
    .family<LogEntryFormController, LogEntryFormData, LogEntryFormKey>(
  LogEntryFormController.new,
);
