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
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../entries/controllers/log_entry_history_controller.dart';
import '../../mileage/controllers/odometer_update_offer_controller.dart';
import '../../mileage/widgets/odometer_update_offer.dart';
import '../../settings/controllers/settings_controller.dart';
import '../../vehicles/controllers/vehicle_archive_controller.dart';
import '../../vehicles/controllers/vehicle_tab_controller.dart';
import '../controllers/reminder_actions_controller.dart';
import '../controllers/reminder_list_controller.dart';
import '../widgets/reminder_card.dart';
import '../widgets/reminder_dialogs.dart';
import '../widgets/reminder_texts.dart';
import '../widgets/reminder_tile.dart';

/// The page of one reminder (`Docs/08_recordatorios.md`), one card per
/// question, the most important first: header (vehicle and origin), the
/// status card with the next due, the criterion (applied over reference,
/// postponement, own warning), the last time with its entry, the note,
/// and the folded history.
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
    final note = reminder.note;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(reminder.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (canWrite) ...[
            IconButton(
              tooltip: l10n.reminderActionMarkDone,
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () => _markDone(context, ref),
            ),
            IconButton(
              tooltip: l10n.actionEdit,
              icon: const Icon(Icons.edit_outlined),
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
      // One card per question, the most important first; 20 dp between
      // blocks and at the sides.
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _Header(view: view),
          const SizedBox(height: 20),
          _StatusCard(view: view, units: units),
          if (!reminder.isOneShot ||
              reminder.isSnoozed ||
              reminder.leadDays != null ||
              reminder.leadKm != null) ...[
            const SizedBox(height: 20),
            _CriterionCard(
              view: view,
              units: units,
              onRestoreReference:
                  canWrite ? () => _restoreReference(context, ref) : null,
            ),
          ],
          if (!reminder.isOneShot &&
              (reminder.lastDoneDate != null ||
                  reminder.lastDoneKm != null)) ...[
            const SizedBox(height: 20),
            _LastTimeCard(reminder: reminder, units: units),
          ],
          if (note != null) ...[
            const SizedBox(height: 20),
            Text(
              note,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _History(reminder: reminder, units: units),
        ],
      ),
    );
  }
}

/// The header: the kind icon in a 48 dp circle, the vehicle, and where the
/// reminder comes from ("Created by hand", "From the manual · p. 174").
/// The title is the app bar's.
class _Header extends StatelessWidget {
  const _Header({required this.view});

  final ReminderView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final reminder = view.reminder;
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          child: Icon(
            reminder.kind.icon,
            semanticLabel: reminder.kind.label(l10n),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vehicleLine(view.vehicle, l10n),
                style: theme.textTheme.titleMedium,
              ),
              Text(
                joinParts(l10n, [
                  reminder.source == ReminderSource.generated
                      ? l10n.reminderSourceGenerated
                      : l10n.reminderSourceManual,
                  reminder.manualRef ?? '',
                ]),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The status card, tinted by the state: the state word with its icon,
/// then the next due as the hero value (both axes side by side when the
/// reminder has two), each with what is left. A completed one-shot shows
/// its completion day.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.view, required this.units});

  final ReminderView view;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final reminder = view.reminder;
    final due = view.due;
    final status = due.status;
    final style = reminderStatusStyle(status, theme);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final word = switch (status) {
      ReminderStatus.dueSoon => l10n.reminderStatusHeadlineDueSoon,
      _ => status.label(l10n),
    };
    // An axis of the reference that the override turned off.
    final noTimeLimit = reminder.overrideActive &&
        reminder.refIntervalMonths != null &&
        reminder.appliedIntervalMonths == null;
    final noDistanceLimit = reminder.overrideActive &&
        reminder.refIntervalKm != null &&
        reminder.appliedIntervalKm == null;
    final date = due.effectiveDate;
    final km = due.effectiveKm;
    final completedAt = reminder.completedAt;

    final Widget body;
    if (completedAt != null) {
      body = _Hero(
        value: l10n.dateValue(completedAt.toLocal()),
        color: style.color,
      );
    } else if (date != null && km != null) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Axis(
              label: l10n.reminderAxisByDistance(units.distance.symbol),
              value: units.distance.format(km),
              remaining: remainingDistanceText(due, l10n, units),
              color: style.color,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _Axis(
              label: l10n.reminderAxisDate,
              value: l10n.dateValue(date.toLocalDateTime()),
              remaining: remainingDateText(due, l10n),
              color: style.color,
            ),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Hero(
            value: date != null
                ? l10n.dateValue(date.toLocalDateTime())
                : units.distance.format(km ?? 0),
            color: style.color,
          ),
          Text(
            joinParts(l10n, [
              (date != null
                      ? remainingDateText(due, l10n)
                      : remainingDistanceText(due, l10n, units)) ??
                  '',
              if (noTimeLimit) l10n.reminderNoTimeLimit,
              if (noDistanceLimit)
                l10n.reminderNoDistanceLimit(units.distance.symbol),
            ]),
            style: muted,
          ),
        ],
      );
    }

    return Container(
      key: const ValueKey('reminder-status-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.10),
        border: Border.all(color: style.color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(style.icon, size: 20, color: style.color),
              const SizedBox(width: 8),
              Text(
                word,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: style.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}

/// The hero value of the status card.
class _Hero extends StatelessWidget {
  const _Hero({required this.value, required this.color});

  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        value,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      );
}

/// One axis of a two-axis status card: its label, its due value and what
/// is left.
class _Axis extends StatelessWidget {
  const _Axis({
    required this.label,
    required this.value,
    required this.remaining,
    required this.color,
  });

  final String label;
  final String value;
  final String? remaining;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = this.remaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CardLabel(label),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (remaining != null)
          Text(
            remaining,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// The criterion card: the reference, or the applied criterion over the
/// reference with what the reference would say on the axes that differ;
/// the postponement and the reminder's own warning when set.
class _CriterionCard extends StatelessWidget {
  const _CriterionCard({
    required this.view,
    required this.units,
    required this.onRestoreReference,
  });

  final ReminderView view;
  final UnitFormatter units;

  /// Puts the reference back; `null` on a read-only reminder.
  final VoidCallback? onRestoreReference;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final reminder = view.reminder;
    final due = view.due;
    final manual = reminder.source == ReminderSource.generated;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final amber = reminderStatusStyle(ReminderStatus.dueSoon, theme).color;
    final overridden = reminder.overrideActive;
    final restore = onRestoreReference;
    return ReminderCard(
      label:
          overridden ? l10n.reminderAppliedCriterion : l10n.reminderCriterion,
      trailing: Wrap(
        spacing: 6,
        children: [
          if (overridden && due.laxerThanReference)
            ReminderChip(
              label: l10n.reminderChipLaxer,
              icon: Icons.warning_amber_outlined,
              color: amber,
            ),
          if (reminder.isSnoozed) ReminderChip(label: l10n.reminderChipSnoozed),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reminder.isOneShot
                ? l10n.reminderModeOneShot
                : overridden
                    ? appliedCriterionText(reminder, l10n, units)
                    : referenceCriterionText(reminder, l10n, units),
            style: theme.textTheme.titleMedium,
          ),
          if (!reminder.isOneShot && !overridden)
            Text(
              manual
                  ? l10n.reminderManufacturerSays
                  : l10n.reminderOwnReference,
              style: muted,
            ),
          if (overridden) ...[
            Text(
              joinParts(l10n, [
                if (reminder.overrideReason case final reason?)
                  l10n.reminderQuoted(reason),
                if (reminder.overrideAt case final at?)
                  l10n.reminderOverriddenOn(at.toLocal()),
              ]),
              style: muted,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            Text(
              () {
                final reference = criterionText(
                  km: reminder.refIntervalKm,
                  months: reminder.refIntervalMonths,
                  sentence: false,
                  l10n: l10n,
                  units: units,
                );
                return manual
                    ? l10n.reminderManufacturerCriterion(reference)
                    : l10n.reminderReferenceLine(reference);
              }(),
              style: muted,
            ),
            if (due.referenceDueDate case final date? when date != due.dueDate)
              Text(
                l10n.reminderReferenceByTime(date.toLocalDateTime()),
                style: muted,
              ),
            if (due.referenceDueKm case final km? when km != due.dueKm)
              Text(
                l10n.reminderReferenceByDistance(
                  units.distance.symbol,
                  units.distance.format(km),
                ),
                style: muted,
              ),
            if (restore != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: restore,
                  child: Text(l10n.reminderActionRestoreReference),
                ),
              ),
          ],
          if (reminder.isSnoozed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                joinParts(l10n, [
                  snoozedUntilText(reminder, l10n, units),
                  if (reminder.snoozeReason case final reason?)
                    l10n.reminderQuoted(reason),
                ]),
                style: muted,
              ),
            ),
          if (reminder.leadDays != null || reminder.leadKm != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.reminderLeadLine(
                  joinParts(l10n, [
                    if (reminder.leadDays case final days?)
                      l10n.reminderLeadDaysValue(days),
                    if (reminder.leadKm case final km?)
                      l10n.reminderLeadDistanceValue(
                        units.distance.format(km),
                      ),
                  ]),
                ),
                style: muted,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Last time": the anchor day and odometer, and a link to the entry that
/// last closed the reminder while it is still there.
class _LastTimeCard extends ConsumerWidget {
  const _LastTimeCard({required this.reminder, required this.units});

  final Reminder reminder;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final entryId = reminder.lastEntryId;
    final linked = entryId == null
        ? null
        : ref.watch(logEntryDetailProvider(entryId)).value;
    return ReminderCard(
      child: Row(
        children: [
          Icon(Icons.history, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardLabel(l10n.reminderAnchor),
                Text(
                  joinParts(l10n, [
                    if (reminder.lastDoneDate case final day?)
                      l10n.dateValue(day.toLocalDateTime()),
                    if (reminder.lastDoneKm case final km?)
                      units.distance.format(km),
                  ]),
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
          if (linked != null && linked.vehicleId == reminder.vehicleId)
            TextButton(
              onPressed: () =>
                  context.push(AppRoutes.entry(linked.vehicleId, linked.id)),
              child: Text(l10n.reminderAnchorEntryLink),
            ),
        ],
      ),
    );
  }
}

/// "Reminder history": a folded outlined row with the number of changes;
/// opened in place, one line per change, newest first, e.g. "3 Nov 2026 ·
/// Criterion customised · Every 80,000 km · no time limit · “reason”".
class _History extends ConsumerStatefulWidget {
  const _History({required this.reminder, required this.units});

  final Reminder reminder;
  final UnitFormatter units;

  @override
  ConsumerState<_History> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<_History> {
  bool _open = false;

  /// What the change of [change] set, as one short text.
  String _detail(ReminderChange change, AppLocalizations l10n) {
    final units = widget.units;
    final asReminder = widget.reminder.copyWith(
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final changes =
        ref.watch(reminderChangesProvider(widget.reminder.id)).value;
    if (changes == null || changes.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('reminder-history-row'),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.reminderHistoryTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    l10n.reminderHistoryCount(changes.length),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(_open ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_open)
            for (final change in changes)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
      ),
    );
  }
}
