import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/calendar_date.dart';
import '../../../data/models/log_entry_type.dart';
import '../../../data/models/reminder.dart';
import '../../../data/models/reminder_status.dart';
import '../../../data/models/vehicle.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../settings/controllers/settings_controller.dart';
import '../../vehicles/controllers/vehicle_detail_controller.dart';

/// A reminder with its computed state (`evaluateReminder`) and, on the
/// Home list, its vehicle: what a row or the detail page shows. The state
/// is computed here, on every read, and never stored.
class ReminderView {
  /// Creates the view.
  const ReminderView({
    required this.reminder,
    required this.due,
    required this.vehicle,
    this.lead = const ReminderLead(),
  });

  /// Computes the view of [reminder] on [today], with its [vehicle]'s
  /// odometer and the global [lead].
  factory ReminderView.of(
    Reminder reminder, {
    required Vehicle vehicle,
    required CalendarDate today,
    required ReminderLead lead,
  }) =>
      ReminderView(
        reminder: reminder,
        due: evaluateReminder(
          reminder,
          today: today,
          currentKm: vehicle.currentOdometerKm,
          lead: lead,
        ),
        vehicle: vehicle,
        lead: lead,
      );

  /// The reminder.
  final Reminder reminder;

  /// Its status and due values.
  final ReminderDue due;

  /// Its vehicle.
  final Vehicle vehicle;

  /// The global warning the status was computed with; the reminder's own,
  /// when set, takes precedence on each axis.
  final ReminderLead lead;
}

/// The Reminders page of Home: what needs attention, and how many open
/// reminders are fine.
class ReminderAgenda {
  /// Creates the agenda.
  const ReminderAgenda({required this.due, required this.okCount});

  /// Splits [views] (open reminders, most urgent first) into the overdue
  /// and due-soon ones, in their order, and the count of the others.
  factory ReminderAgenda.of(List<ReminderView> views) {
    final due = [
      for (final view in views)
        if (view.due.status == ReminderStatus.overdue ||
            view.due.status == ReminderStatus.dueSoon)
          view,
    ];
    return ReminderAgenda(due: due, okCount: views.length - due.length);
  }

  /// Overdue and due-soon reminders, most urgent first.
  final List<ReminderView> due;

  /// Open reminders that are up to date (not listed on Home).
  final int okCount;
}

/// Sorts [views] by urgency (`compareByUrgency`): overdue first, then by
/// remaining days, then by remaining km.
List<ReminderView> sortedByUrgency(Iterable<ReminderView> views) =>
    views.toList()..sort((a, b) => compareByUrgency(a.due, b.due));

/// Today's calendar day on the phone, the "today" of every status.
/// Overridden in tests.
final reminderTodayProvider = Provider.autoDispose<CalendarDate>(
  (ref) => calendarDateOf(DateTime.now()),
);

/// The global lead, or its defaults until it is read.
ReminderLead _leadOf(Ref ref) =>
    ref.watch(reminderLeadProvider).value ?? const ReminderLead();

/// The live, open reminders of every active vehicle, most urgent first.
/// Archived vehicles and the Trash are left out by the repository.
final activeRemindersProvider =
    StreamProvider.autoDispose<List<ReminderView>>((ref) {
  final lead = _leadOf(ref);
  final today = ref.watch(reminderTodayProvider);
  return ref.watch(reminderRepositoryProvider).watchActiveAcrossVehicles().map(
        (items) => sortedByUrgency([
          for (final item in items)
            ReminderView.of(
              item.reminder,
              vehicle: item.vehicle,
              today: today,
              lead: lead,
            ),
        ]),
      );
});

/// The Reminders page of Home (`Docs/08_recordatorios.md`): an agenda of
/// the overdue and due-soon reminders of the active vehicles.
final reminderAgendaProvider = Provider.autoDispose<AsyncValue<ReminderAgenda>>(
  (ref) => ref.watch(activeRemindersProvider).whenData(ReminderAgenda.of),
);

/// The badge of the Reminders destination: the length of the agenda
/// (overdue plus due soon); 0 while it loads.
final reminderBadgeCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(reminderAgendaProvider).value?.due.length ?? 0,
);

/// The live reminders of the vehicle with this id, completed ones
/// included, most urgent first: the Reminders tab. Waits for the vehicle,
/// whose odometer the statuses need.
final vehicleRemindersProvider =
    StreamProvider.autoDispose.family<List<ReminderView>, String>(
  (ref, vehicleId) {
    final vehicle = ref.watch(vehicleByIdProvider(vehicleId)).value;
    if (vehicle == null) return const Stream.empty();
    final lead = _leadOf(ref);
    final today = ref.watch(reminderTodayProvider);
    return ref.watch(reminderRepositoryProvider).watchByVehicle(vehicleId).map(
          (reminders) => sortedByUrgency([
            for (final reminder in reminders)
              ReminderView.of(
                reminder,
                vehicle: vehicle,
                today: today,
                lead: lead,
              ),
          ]),
        );
  },
);

/// Identifies one reminder by its vehicle and its own id, both from the
/// path.
typedef ReminderKey = ({String vehicleId, String reminderId});

/// The reminder of the detail page, or `null` when the vehicle or the
/// reminder is missing, or the reminder belongs to another vehicle.
final reminderDetailProvider =
    StreamProvider.autoDispose.family<ReminderView?, ReminderKey>((ref, key) {
  final vehicleValue = ref.watch(vehicleByIdProvider(key.vehicleId));
  if (!vehicleValue.hasValue) return const Stream.empty();
  final vehicle = vehicleValue.value;
  if (vehicle == null) return Stream.value(null);
  final lead = _leadOf(ref);
  final today = ref.watch(reminderTodayProvider);
  return ref.watch(reminderRepositoryProvider).watchById(key.reminderId).map(
        (reminder) => reminder == null || reminder.vehicleId != vehicle.id
            ? null
            : ReminderView.of(
                reminder,
                vehicle: vehicle,
                today: today,
                lead: lead,
              ),
      );
});

/// The history of the reminder with this id, newest first.
final reminderChangesProvider =
    StreamProvider.autoDispose.family<List<ReminderChange>, String>(
  (ref, reminderId) =>
      ref.watch(reminderRepositoryProvider).watchChanges(reminderId),
);

/// The ids of the entries of the vehicle with this id that last closed a
/// live reminder: the reminder icon of the history rows.
final reminderClosingEntryIdsProvider =
    StreamProvider.autoDispose.family<Set<String>, String>(
  (ref, vehicleId) =>
      ref.watch(reminderRepositoryProvider).watchClosingEntryIds(vehicleId),
);

/// The live reminders the entry with this id last closed: the read-only
/// "Closed:" line of the entry form.
final entryClosedRemindersProvider =
    StreamProvider.autoDispose.family<List<Reminder>, String>(
  (ref, entryId) =>
      ref.watch(reminderRepositoryProvider).watchClosedBy(entryId),
);

/// Identifies the reminders an entry of [type] can close on a vehicle.
typedef ClosableKey = ({String vehicleId, LogEntryType type});

/// The live, open reminders of a vehicle that an entry of a type can
/// close, most urgent first: the "Closes the reminder" field.
final closableRemindersProvider =
    StreamProvider.autoDispose.family<List<ReminderView>, ClosableKey>(
  (ref, key) {
    final vehicle = ref.watch(vehicleByIdProvider(key.vehicleId)).value;
    if (vehicle == null) return const Stream.empty();
    final lead = _leadOf(ref);
    final today = ref.watch(reminderTodayProvider);
    return ref
        .watch(reminderRepositoryProvider)
        .watchClosable(key.vehicleId, key.type)
        .map(
          (reminders) => sortedByUrgency([
            for (final reminder in reminders)
              ReminderView.of(
                reminder,
                vehicle: vehicle,
                today: today,
                lead: lead,
              ),
          ]),
        );
  },
);
