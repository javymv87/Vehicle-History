import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/router/navigation.dart';
import '../../../app/theme/status_colors.dart';
import '../../../data/models/attachment.dart';
import '../../../data/models/fuel_consumption.dart';
import '../../../data/models/log_entry.dart';
import '../../../data/models/refuel.dart';
import '../../../data/models/reminder.dart';
import '../../../data/models/vehicle.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/utils/money.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/detail_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../../shared/widgets/state_line.dart';
import '../../../shared/widgets/status_card.dart';
import '../../attachments/controllers/attachment_list_controller.dart';
import '../../attachments/widgets/attachment_actions.dart';
import '../../attachments/widgets/attachment_selection_app_bar.dart';
import '../../attachments/widgets/attachments_section.dart';
import '../../reminders/controllers/reminder_list_controller.dart';
import '../../reminders/widgets/reminder_texts.dart';
import '../../reports/controllers/fuel_chains_controller.dart';
import '../../reports/widgets/segment_texts.dart';
import '../../settings/controllers/settings_controller.dart';
import '../../vehicles/controllers/vehicle_archive_controller.dart';
import '../../vehicles/controllers/vehicle_detail_controller.dart';
import '../controllers/log_entry_deletion_controller.dart';
import '../controllers/log_entry_history_controller.dart';
import '../widgets/log_entry_type_icon.dart';

/// Detail of one history entry (`Docs/03_features.md`, U7), built as a
/// detail archetype: the header (type icon, vehicle, the reminder it
/// closed), the status card (what was done, when, at what km and for how
/// much), for a refuel the consumption card, then the attachments; edit
/// and delete in the app bar. Both ids come from the path; an unknown or deleted
/// entry, or one reached through another vehicle's path, shows a not-found
/// page.
class LogEntryDetailPage extends ConsumerWidget {
  /// Creates the page for the entry [entryId] of the vehicle [vehicleId].
  const LogEntryDetailPage({
    super.key,
    required this.vehicleId,
    required this.entryId,
  });

  /// Id of the vehicle, from the path.
  final String vehicleId;

  /// Id of the entry, from the path.
  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(logEntryDetailProvider(entryId));
    return detail.when(
      skipLoadingOnReload: true,
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(),
        body: EmptyState(icon: Icons.error_outline, message: l10n.loadError),
      ),
      data: (entry) => entry == null || entry.vehicleId != vehicleId
          ? NotFoundPage(message: l10n.entryNotFound)
          : _LogEntryDetailView(entry: entry),
    );
  }
}

/// The loaded entry detail.
class _LogEntryDetailView extends ConsumerWidget {
  const _LogEntryDetailView({required this.entry});

  final LogEntry entry;

  /// Deletes the entry after confirmation, then offers "Undo".
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmDelete(
      context,
      title: l10n.deleteEntryTitle,
      message: l10n.deleteEntryMessage,
    );
    if (!confirmed || !context.mounted) return;

    // Read before popping: the controller outlives this page, the page's
    // `ref` does not.
    final deletion = ref.read(logEntryDeletionControllerProvider.notifier);
    final result = await deletion.delete(entry.id);
    if (!context.mounted) return;
    switch (result) {
      case ActionSuccess():
        context.popOrGo(AppRoutes.vehicle(entry.vehicleId));
        showUndoSnackBar(
          messenger,
          l10n,
          l10n.entryDeleted,
          onUndo: () async {
            final undone = await deletion.undo(entry.id);
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
    final km = entry.km;
    final cost = entry.costCents;
    final refuel = entry.refuel;
    final units = unitFormatterOf(context, ref);
    final target = AttachmentTarget.logEntry(entry.id);
    final vehicle = ref.watch(vehicleByIdProvider(entry.vehicleId)).value;
    final closed = ref.watch(entryClosedRemindersProvider(entry.id)).value ??
        const <Reminder>[];
    final attachmentCount =
        ref.watch(attachmentsProvider(target)).value?.length ?? 0;
    // An archived vehicle: everything visible, nothing to change.
    final readOnly = ref.watch(vehicleReadOnlyProvider(entry.vehicleId));
    final date = l10n.dateValue(entry.date.toLocalDateTime());
    final distance = km == null ? null : units.distance.format(km);
    final amount = cost == null ? null : formatEuroCents(cost, l10n.localeName);
    final volume = refuel?.volume;
    // The status card's values: for a refuel, how much, at what price and
    // for how much on the first row, then when and at what km; one row
    // (when, km, cost) otherwise.
    final List<List<String>> facts;
    if (refuel == null) {
      facts = [
        [
          date,
          if (distance != null) distance,
          if (amount != null) amount,
        ],
      ];
    } else {
      facts = [
        [
          if (volume != null) units.fuelQuantity(refuel.fuel).format(volume),
          if (volume != null && cost != null && volume > 0)
            units.formatUnitPrice(refuel.fuel, cost / 100 / volume),
          if (amount != null) amount,
        ],
        [
          date,
          if (distance != null) distance,
        ],
      ];
    }
    const gap = SizedBox(height: 20);
    return Scaffold(
      // U29: the contextual bar while attachments are selected.
      appBar: AttachmentSelectionAppBar(
        target: target,
        appBar: AppBar(
          title: Text(entry.type.label(l10n)),
          actions: [
            if (!readOnly) ...[
              IconButton(
                tooltip: l10n.actionEdit,
                icon: const Icon(Icons.edit),
                onPressed: () => context
                    .push(AppRoutes.editEntry(entry.vehicleId, entry.id)),
              ),
              IconButton(
                tooltip: l10n.actionDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, ref),
              ),
            ],
          ],
        ),
      ),
      // One card per question, the most important first (what was done,
      // when, and what it cost); 20 dp between blocks and at the sides.
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _Header(entry: entry, vehicle: vehicle, closed: closed),
          gap,
          StatusCard(
            key: const ValueKey('entry-status-card'),
            value: entry.description ?? entry.type.label(l10n),
            textValue: true,
            facts: facts,
            line: km == null ? null : l10n.entryKmNote,
          ),
          if (refuel != null) ...[
            gap,
            AppCard(
              label: l10n.refuelConsumptionTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RefuelConsumption(entry: entry, readOnly: readOnly),
                  if (vehicle?.fuelType.hasFuelChoice ?? false)
                    DetailField.row(
                      label: l10n.fieldRefuelFuel,
                      value: refuel.fuel.label(l10n),
                    ),
                  DetailField.row(
                    label: l10n.fieldRefuelFullTank,
                    value: refuel.fullTank ? l10n.valueYes : l10n.valueNo,
                  ),
                  DetailField.row(
                    label: l10n.fieldRefuelMissed,
                    value: refuel.missedPrevious ? l10n.valueYes : l10n.valueNo,
                  ),
                ],
              ),
            ),
          ],
          gap,
          AppCard(
            label: l10n.attachmentsCount(attachmentCount),
            action: AppCardAction(
              icon: Icons.add,
              tooltip: l10n.addAttachment,
              onPressed: () => addAttachments(context, ref, target),
            ),
            child: AttachmentsSection(
              target: target,
              emptyText: l10n.noAttachments,
              inset: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// The header: the entry type's icon in a 48 dp circle, the vehicle
/// ("Fiat Punto · FS548KS") and, when the entry closed a reminder, a muted
/// "Closed: Engine oil" line that opens it. The type is the app bar's
/// title.
class _Header extends StatelessWidget {
  const _Header({
    required this.entry,
    required this.vehicle,
    required this.closed,
  });

  final LogEntry entry;
  final Vehicle? vehicle;
  final List<Reminder> closed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final vehicle = this.vehicle;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          child: Icon(entry.type.icon, semanticLabel: entry.type.label(l10n)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (vehicle != null)
                Text(
                  vehicleLine(vehicle, l10n),
                  style: theme.textTheme.titleMedium,
                ),
              for (final reminder in closed)
                InkWell(
                  onTap: () => context.push(
                    AppRoutes.reminder(entry.vehicleId, reminder.id),
                  ),
                  child: Padding(
                    // A comfortable touch target around one line of text.
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            l10n.entryClosedReminder(reminder.title),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: muted,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 18, color: muted),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What a refuel means for the consumption (`Docs/03_features.md`, refuel
/// detail), the first line of the consumption card: the segment it closes
/// with its figures, in the colour of its state with its icon (valid,
/// suspicious, not computable), or why there is none yet. A suspicious
/// segment adds the amber sentence and a link to the edit form, where the
/// missed-refuel flag is set; the reports never write.
class _RefuelConsumption extends ConsumerWidget {
  const _RefuelConsumption({required this.entry, required this.readOnly});

  final LogEntry entry;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = unitFormatterOf(context, ref);
    final chains = ref.watch(fuelChainsProvider(entry.vehicleId)).value;
    final role = chains == null ? null : refuelRoleIn(chains, entry.id);
    if (role == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final status = theme.extension<StatusColors>()!;
    final muted = theme.colorScheme.onSurfaceVariant;
    final segment = switch (role) {
      ClosesSegment(:final segment) => segment,
      _ => null,
    };
    const key = ValueKey('refuel-consumption');
    if (segment == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: StateLine(
          key: key,
          icon: Icons.info_outline,
          text: refuelRoleText(role, l10n, units)!,
          color: muted,
        ),
      );
    }
    final (icon, color) = switch (segment.state) {
      SegmentState.valid => (Icons.check_circle_outline, status.ok),
      SegmentState.suspicious => (Icons.warning_amber, status.dueSoon),
      SegmentState.invalid => (Icons.block, muted),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StateLine(
            key: key,
            icon: icon,
            text: segmentStateText(segment, l10n, units),
            color: color,
          ),
          if (segment.suspicious) ...[
            Padding(
              // Under the text of the line above, past its icon.
              padding: const EdgeInsetsDirectional.only(start: 20, top: 4),
              child: Text(
                l10n.segmentSuspicious,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
            if (!readOnly)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => context.push(
                      AppRoutes.editEntry(entry.vehicleId, entry.id),
                    ),
                    child: Text(l10n.actionEditRefuel),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
