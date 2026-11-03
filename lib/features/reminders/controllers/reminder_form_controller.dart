import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/reminder.dart';
import '../../../data/models/reminder_kind.dart';
import '../../../data/models/vehicle.dart';
import '../../../shared/utils/action_result.dart';

/// Identifies one reminder form: the vehicle, and the reminder being
/// edited (`null` to create one).
typedef ReminderFormKey = ({String vehicleId, String? reminderId});

/// What the reminder form needs once loaded.
class ReminderFormData {
  /// Creates the loaded form data.
  const ReminderFormData({
    required this.vehicle,
    required this.reminder,
    this.usedKinds = const {},
  });

  /// The vehicle, or `null` when no live vehicle has the id in the path.
  final Vehicle? vehicle;

  /// The reminder being edited; `null` when creating, or when the id in the
  /// path matches no live reminder of this vehicle.
  final Reminder? reminder;

  /// The unique kinds the vehicle's other live, open reminders already use:
  /// they do not appear in the picker (`Docs/04_maintenance_logic.md`).
  final Set<ReminderKind> usedKinds;
}

/// State of the reminder form, loaded once when the form opens so the
/// fields do not change under the user while they type.
class ReminderFormController extends AsyncNotifier<ReminderFormData> {
  /// Creates the controller for the form identified by [key].
  ReminderFormController(this.key);

  /// Vehicle of the form, and the reminder edited (`null` when creating).
  final ReminderFormKey key;

  @override
  Future<ReminderFormData> build() async {
    final vehicle =
        await ref.watch(vehicleRepositoryProvider).getById(key.vehicleId);
    if (vehicle == null) {
      return const ReminderFormData(vehicle: null, reminder: null);
    }
    final repository = ref.watch(reminderRepositoryProvider);
    final reminders = await repository.getByVehicle(vehicle.id);
    final reminderId = key.reminderId;
    Reminder? edited;
    for (final reminder in reminders) {
      if (reminder.id == reminderId) edited = reminder;
    }
    return ReminderFormData(
      vehicle: vehicle,
      reminder: edited,
      usedKinds: {
        for (final reminder in reminders)
          if (reminder.id != reminderId &&
              !reminder.isCompleted &&
              reminder.kind.uniquePerVehicle)
            reminder.kind,
      },
    );
  }

  /// Creates the reminder from [draft], or updates the edited one.
  ///
  /// Returns the saved reminder, or the reason it was not saved (for
  /// example [ActionError.reminderKindInUse]).
  Future<ActionResult<Reminder>> save(ReminderDraft draft) {
    final repository = ref.read(reminderRepositoryProvider);
    final reminderId = key.reminderId;
    return runAction(() {
      if (reminderId != null) return repository.update(reminderId, draft);
      return repository.create(vehicleId: key.vehicleId, draft: draft);
    });
  }
}

/// The [ReminderFormController] for a vehicle and a reminder id (`null` to
/// create one).
final reminderFormControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ReminderFormController, ReminderFormData, ReminderFormKey>(
  ReminderFormController.new,
);
