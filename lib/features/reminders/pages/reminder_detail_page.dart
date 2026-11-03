import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/router/navigation.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/odometer_checks.dart';
import '../../../data/models/reminder.dart';
import '../../../data/models/reminder_status.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/utils/unit_formatter.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/detail_field.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../../shared/widgets/section_header.dart';
import '../../entries/controllers/log_entry_history_controller.dart';
import '../../mileage/controllers/odometer_update_offer_controller.dart';
import '../../mileage/widgets/odometer_update_offer.dart';
import '../../settings/controllers/settings_controller.dart';
import '../../vehicles/controllers/vehicle_archive_controller.dart';
import '../../vehicles/controllers/vehicle_tab_controller.dart';
import '../controllers/reminder_actions_controller.dart';
import '../controllers/reminder_list_controller.dart';
import '../widgets/reminder_dialogs.dart';
import '../widgets/reminder_texts.dart';
import '../widgets/reminder_tile.dart';

/// The page of one reminder (`Docs/08_recordatorios.md`): status, next due,
/// the applied and reference criteria, the snooze, the anchor with its
/// entry, note, manual reference and source, and the reminder's history.
/// Its actions are "Mark done", Postpone, the criterion ones, Edit and
/// Delete; none on an archived vehicle, only Delete on a completed one.
class ReminderDetailPage extends ConsumerWidget {
  /// Creates the page of the reminder [reminderId] of the vehicle
  /// [vehicleId], both from the path.
  const ReminderDetailPage({
    super.key,
    required this.vehicleId,
    required this.reminderId,
  });

  /// Id of the vehicle, from the path.
  final String vehicleId;

  /// Id of the reminder, from the path.
  final String reminderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final key = (vehicleId: vehicleId, reminderId: reminderId);
    return ref.watch(reminderDetailProvider(key)).when(
          skipLoadingOnReload: true,
          loading: () => Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => Scaffold(
            appBar: AppBar(),
            body: MessageView(
              icon: Icons.error_outline,
              message: l10n.loadError,
            ),
          ),
          data: (view) => view == null
              ? NotFoundPage(message: l10n.reminderNotFound)
              : _ReminderDetailView(view: view),
        );
  }
}

/// The loaded reminder page.
class _ReminderDetailView extends ConsumerWidget {
  const _ReminderDetailView({required this.view});

  final ReminderView view;

  /// Opens the mark-done dialog; afterwards the toast, or the odometer
  /// offer when the new entry has more km than the vehicle (E3).
  Future<void> _markDone(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Captured now: the offer's "Update" runs after this page may be gone.
    final router = GoRouter.of(context);
    final units = readUnitFormatter(context, ref);
    final offer = ref.read(odometerUpdateOfferControllerProvider.notifier);
    final readings = ref.read(mileageReadingRepositoryProvider);
    final vehicle = view.vehicle;
    final entry = await showMarkDoneDialog(
      context,
      reminder: view.reminder,
      vehicle: vehicle,
    );
    if (entry == null) return;
    final entryKm = entry.km;
    final lastReading = await readings.getLast(vehicle.id);
    if (entryKm != null &&
        shouldOfferOdometerUpdate(
          entryKm: entryKm,
          entryDate: entry.date,
          currentOdometerKm: vehicle.currentOdometerKm,
          lastReadingDate: lastReading?.date,
          today: calendarDateOf(DateTime.now()),
        )) {
      showOdometerUpdateOffer(
        messenger: messenger,
        router: router,
        l10n: l10n,
        units: units,
        offer: offer,
        vehicleId: vehicle.id,
        date: entry.date,
        km: entryKm,
        currentKm: vehicle.currentOdometerKm,
      );
    } else {
      showSavedSnackBar(messenger, l10n.reminderChangeClose);
    }
  }

  /// Opens the snooze dialog.
  Future<void> _snooze(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final snoozed = await showSnoozeDialog(
      context,
      reminder: view.reminder,
      due: view.due,
    );
    if (snoozed != null) {
      showSavedSnackBar(messenger, l10n.reminderChangeSnooze);
    }
  }

  /// Opens the override dialog.
  Future<void> _override(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final changed = await showOverrideDialog(context, reminder: view.reminder);
    if (changed != null) {
      showSavedSnackBar(messenger, l10n.reminderChangeOverride);
    }
  }

  /// Runs [action] and shows [done] on success, or the error.
  Future<void> _run(
    BuildContext context,
    Future<ActionResult<Object?>> Function() action,
    String done,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    switch (await action()) {
      case ActionSuccess():
        showSavedSnackBar(messenger, done);
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  /// Asks, then puts the reference criterion back.
  Future<void> _restoreReference(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final units = readUnitFormatter(context, ref);
    final actions = ref.read(reminderActionsControllerProvider.notifier);
    final confirmed = await confirmAction(
      context,
      title: l10n.reminderRestoreReferenceTitle,
      message: l10n.reminderRestoreReferenceMessage(
        referenceCriterionText(view.reminder, l10n, units),
      ),
      confirmLabel: l10n.reminderActionRestoreReference,
    );
    if (!confirmed || !context.mounted) return;
    await _run(
      context,
      () => actions.restoreReference(view.reminder.id),
      l10n.reminderChangeRestoreReference,
    );
  }

  /// Asks, deletes, goes back to the vehicle and offers Undo.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Read before popping: the controller outlives this page.
    final actions = ref.read(reminderActionsControllerProvider.notifier);
    final reminder = view.reminder;
    final confirmed = await confirmDelete(
      context,
      title: l10n.deleteReminderTitle(reminder.title),
      message: l10n.deleteReminderMessage,
    );
    if (!confirmed || !context.mounted) return;
    switch (await actions.delete(reminder.id)) {
      case ActionSuccess():
        if (!context.mounted) return;
        context.popOrGo(
          AppRoutes.vehicle(reminder.vehicleId, tab: VehicleTab.reminders),
        );
        showUndoSnackBar(
          messenger,
          l10n,
          l10n.reminderDeleted,
          onUndo: () async {
            final undone = await actions.undoDelete(reminder.id);
            if (undone case ActionFailure(:final error)) {
              showErrorSnackBar(messenger, error.message(l10n));
            }
          },
        );
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = unitFormatterOf(context, ref);
    final reminder = view.reminder;
    final vehicle = view.vehicle;
    final readOnly = ref.watch(vehicleReadOnlyProvider(vehicle.id));
    final completed = reminder.isCompleted;
    final actions = ref.read(reminderActionsControllerProvider.notifier);
    final canWrite = !readOnly && !completed;
    return Scaffold(
      appBar: AppBar(
        title: Text(reminder.title),
        actions: [
          if (canWrite) ...[
            IconButton(
              tooltip: l10n.reminderActionMarkDone,
              icon: const Icon(Icons.task_alt),
              onPressed: () => _markDone(context, ref),
            ),
            IconButton(
              tooltip: l10n.actionEdit,
              icon: const Icon(Icons.edit),
              onPressed: () => context.push(
                AppRoutes.editReminder(vehicle.id, reminder.id),
              ),
            ),
          ],
          if (!readOnly)
            PopupMenuButton<VoidCallback>(
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                if (canWrite) ...[
                  reminder.isSnoozed
                      ? PopupMenuItem(
                          value: () => _run(
                            context,
                            () => actions.unsnooze(reminder.id),
                            l10n.reminderChangeUnsnooze,
                          ),
                          child: Text(l10n.reminderActionUnsnooze),
                        )
                      : PopupMenuItem(
                          value: () => _snooze(context),
                          child: Text(l10n.reminderActionSnooze),
                        ),
                  if (!reminder.isOneShot)
                    PopupMenuItem(
                      value: () => _override(context),
                      child: Text(
                        reminder.overrideActive
                            ? l10n.reminderActionEditOverride
                            : l10n.reminderActionOverride,
                      ),
                    ),
                  if (reminder.overrideActive)
                    PopupMenuItem(
                      value: () => _restoreReference(context, ref),
                      child: Text(l10n.reminderActionRestoreReference),
                    ),
                ],
                PopupMenuItem(
                  value: () => _delete(context, ref),
                  child: Text(l10n.actionDelete),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: CircleAvatar(
              child: Icon(
                reminder.kind.icon,
                semanticLabel: reminder.kind.label(l10n),
              ),
            ),
            title: Text(reminder.kind.label(l10n)),
            subtitle: Text(vehicle.displayNameWithPlate(l10n)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ReminderStatusLine(
              status: view.due.status,
              detail: reminderDueLine(reminder, view.due, l10n, units),
            ),
          ),
          if (!completed) _NextDue(view: view, units: units),
          _Criteria(view: view, units: units),
          if (reminder.isSnoozed) ...[
            SectionHeader(title: l10n.reminderChipSnoozed),
            DetailField(
              label: l10n.reminderSnoozedUntil(
                snoozeTargetText(reminder, l10n, units),
              ),
              value: l10n.reminderReason(reminder.snoozeReason ?? ''),
            ),
          ],
          _Anchor(reminder: reminder, units: units),
          if (reminder.leadDays != null || reminder.leadKm != null)
            DetailField(
              label: l10n.reminderLeadLabel,
              value: joinParts(l10n, [
                if (reminder.leadDays case final days?)
                  l10n.reminderLeadDaysValue(days),
                if (reminder.leadKm case final km?)
                  l10n.reminderLeadDistanceValue(units.distance.format(km)),
              ]),
            ),
          if (reminder.note case final note?)
            DetailField(label: l10n.reminderFieldNote, value: note),
          if (reminder.manualRef case final manualRef?)
            DetailField(label: l10n.reminderFieldManualRef, value: manualRef),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              reminder.source == ReminderSource.generated
                  ? l10n.reminderSourceGenerated
                  : l10n.reminderSourceManual,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          _History(reminder: reminder, units: units),
        ],
      ),
    );
  }
}

/// "Next due": the due value of each axis with what is left, after the
/// snooze if any.
class _NextDue extends StatelessWidget {
  const _NextDue({required this.view, required this.units});

  final ReminderView view;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final due = view.due;
    final date = due.effectiveDate;
    final km = due.effectiveKm;
    if (date == null && km == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.reminderNextDue),
        if (date != null)
          DetailField(
            label: l10n.reminderAxisDate,
            value: l10n.dateValue(date.toLocalDateTime()),
            note: dueDateText(due, l10n),
          ),
        if (km != null)
          DetailField(
            label: l10n.reminderAxisDistance,
            value: units.distance.format(km),
            note: dueDistanceText(due, l10n, units),
          ),
      ],
    );
  }
}

/// The criterion; when overridden, the applied one first, large, then the
/// reference one small with what the manufacturer would say, and the
/// warning when the applied one is laxer.
class _Criteria extends StatelessWidget {
  const _Criteria({required this.view, required this.units});

  final ReminderView view;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final reminder = view.reminder;
    final due = view.due;
    if (!reminder.overrideActive) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: l10n.reminderCriterion),
          DetailField(
            label: l10n.reminderCriterion,
            value: referenceCriterionText(reminder, l10n, units),
          ),
        ],
      );
    }
    final muted = theme.colorScheme.onSurfaceVariant;
    final amber = reminderStatusStyle(ReminderStatus.dueSoon, theme).color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.reminderAppliedCriterion),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appliedCriterionText(reminder, l10n, units),
                style: theme.textTheme.titleLarge,
              ),
              if (reminder.overrideReason case final reason?)
                Text(l10n.reminderReason(reason)),
              if (reminder.overrideAt case final at?)
                Text(
                  l10n.reminderOverriddenOn(at.toLocal()),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              const SizedBox(height: 12),
              Text(
                l10n.reminderReferenceCriterion,
                style: theme.textTheme.labelLarge?.copyWith(color: muted),
              ),
              Text(
                referenceCriterionText(reminder, l10n, units),
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              if (due.referenceDueDate case final date?)
                Text(
                  l10n.reminderReferenceDueDate(date.toLocalDateTime()),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              if (due.referenceDueKm case final km?)
                Text(
                  l10n.reminderReferenceDueDistance(units.distance.format(km)),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              if (due.laxerThanReference)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        size: 18,
                        color: amber,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n.reminderLaxerWarning,
                          style:
                              theme.textTheme.bodySmall?.copyWith(color: amber),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Last time": the anchor day and odometer, and a link to the entry that
/// last closed the reminder when it is still there.
class _Anchor extends ConsumerWidget {
  const _Anchor({required this.reminder, required this.units});

  final Reminder reminder;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final day = reminder.lastDoneDate;
    final km = reminder.lastDoneKm;
    final entryId = reminder.lastEntryId;
    final entry =
        entryId == null ? null : ref.watch(logEntryDetailProvider(entryId));
    final linked = entry?.value;
    if (day == null && km == null && linked == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.reminderAnchor),
        if (day != null)
          DetailField(
            label: l10n.fieldEntryDate,
            value: l10n.dateValue(day.toLocalDateTime()),
          ),
        if (km != null)
          DetailField(
            label: l10n.fieldEntryKm,
            value: units.distance.format(km),
          ),
        if (linked != null && linked.vehicleId == reminder.vehicleId)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l10n.reminderAnchorEntryLink),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                context.push(AppRoutes.entry(linked.vehicleId, linked.id)),
          ),
      ],
    );
  }
}

/// "Reminder history": one line per change, newest first, e.g. "3 Nov
/// 2026 · Criterion customised · Every 80,000 km · time off · “reason”".
class _History extends ConsumerWidget {
  const _History({required this.reminder, required this.units});

  final Reminder reminder;
  final UnitFormatter units;

  /// What the change of [change] set, as one short text.
  String _detail(ReminderChange change, AppLocalizations l10n) {
    final asReminder = reminder.copyWith(
      dueDate: change.dueDate,
      lastDoneDate: change.lastDoneDate,
      lastDoneKm: change.lastDoneKm,
      refIntervalKm: change.refIntervalKm,
      refIntervalMonths: change.refIntervalMonths,
      overrideActive: change.overrideActive,
      appliedIntervalKm: change.appliedIntervalKm,
      appliedIntervalMonths: change.appliedIntervalMonths,
      snoozeUntilDate: change.snoozeUntilDate,
      snoozeUntilKm: change.snoozeUntilKm,
    );
    return switch (change.type) {
      ReminderChangeType.create ||
      ReminderChangeType.edit ||
      ReminderChangeType.restoreReference =>
        referenceCriterionText(asReminder, l10n, units),
      ReminderChangeType.applyOverride =>
        appliedCriterionText(asReminder, l10n, units),
      ReminderChangeType.snooze => snoozeTargetText(asReminder, l10n, units),
      ReminderChangeType.close => joinParts(l10n, [
          if (change.lastDoneDate case final day?)
            l10n.dateValue(day.toLocalDateTime()),
          if (change.lastDoneKm case final km?) units.distance.format(km),
        ]),
      ReminderChangeType.unsnooze || ReminderChangeType.complete => '',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final changes = ref.watch(reminderChangesProvider(reminder.id)).value;
    if (changes == null || changes.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.reminderHistoryTitle),
        for (final change in changes)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              joinParts(l10n, [
                l10n.dateValue(change.changedAt.toLocal()),
                change.type.label(l10n),
                _detail(change, l10n),
                if (change.reason case final reason?)
                  l10n.reminderQuoted(reason),
              ]),
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}
