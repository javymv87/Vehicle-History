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
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/utils/money.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/detail_field.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../../shared/widgets/section_header.dart';
import '../../attachments/widgets/attachment_actions.dart';
import '../../attachments/widgets/attachment_selection_app_bar.dart';
import '../../attachments/widgets/attachments_section.dart';
import '../../reports/controllers/fuel_chains_controller.dart';
import '../../reports/widgets/segment_texts.dart';
import '../../settings/controllers/settings_controller.dart';
import '../../vehicles/controllers/vehicle_archive_controller.dart';
import '../../vehicles/controllers/vehicle_detail_controller.dart';
import '../controllers/log_entry_deletion_controller.dart';
import '../controllers/log_entry_history_controller.dart';
import '../widgets/log_entry_type_icon.dart';

/// Detail of one history entry (`Docs/03_features.md`, U7): every field,
/// with edit and delete; a refuel adds its fields and what it means for
/// the consumption. Both ids come from the path; an unknown or deleted
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
        body: MessageView(icon: Icons.error_outline, message: l10n.loadError),
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
    // An archived vehicle: everything visible, nothing to change.
    final readOnly = ref.watch(vehicleReadOnlyProvider(entry.vehicleId));
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
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: Icon(entry.type.icon),
            title: Text(entry.type.label(l10n)),
            subtitle: Text(l10n.fieldEntryType),
          ),
          DetailField(
            label: l10n.fieldEntryDate,
            value: l10n.dateValue(entry.date.toLocalDateTime()),
          ),
          if (km != null)
            DetailField(
              label: l10n.fieldEntryKm,
              value: units.distance.format(km),
              note: l10n.entryKmNote,
            ),
          if (cost != null)
            DetailField(
              label:
                  refuel == null ? l10n.fieldEntryCost : l10n.fieldRefuelAmount,
              value: formatEuroCents(cost, l10n.localeName),
            ),
          if (refuel != null) ...[
            if (ref
                    .watch(vehicleByIdProvider(entry.vehicleId))
                    .value
                    ?.fuelType
                    .hasFuelChoice ??
                false)
              DetailField(
                label: l10n.fieldRefuelFuel,
                value: refuel.fuel.label(l10n),
              ),
            if (refuel.volume case final volume?) ...[
              DetailField(
                label: refuel.fuel.quantity == FuelQuantity.mass
                    ? l10n.fieldRefuelMass
                    : l10n.fieldRefuelVolume,
                value: units.fuelQuantity(refuel.fuel).format(volume),
              ),
              if (cost != null && volume > 0)
                DetailField(
                  label: l10n.fieldRefuelPrice,
                  value: units.formatUnitPrice(
                    refuel.fuel,
                    cost / 100 / volume,
                  ),
                ),
            ],
            DetailField(
              label: l10n.fieldRefuelFullTank,
              value: refuel.fullTank ? l10n.valueYes : l10n.valueNo,
            ),
            DetailField(
              label: l10n.fieldRefuelMissed,
              value: refuel.missedPrevious ? l10n.valueYes : l10n.valueNo,
            ),
            const Divider(height: 32),
            SectionHeader(title: l10n.refuelConsumptionTitle),
            _RefuelConsumption(entry: entry, readOnly: readOnly),
          ],
          if (entry.description case final description?)
            DetailField(label: l10n.fieldEntryDescription, value: description),
          const Divider(height: 32),
          SectionHeader(
            title: l10n.attachmentsTitle,
            actionLabel: l10n.addAttachment,
            onAction: () => addAttachments(context, ref, target),
          ),
          AttachmentsSection(
            target: target,
            emptyText: l10n.noAttachments,
          ),
        ],
      ),
    );
  }
}

/// What a refuel means for the consumption (`Docs/03_features.md`, refuel
/// detail): the segment it closes with its figures, or why there is none
/// yet. A suspicious segment adds an amber line and a link to the edit
/// form, where the missed-refuel flag is set; the reports never write.
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
    final amber = theme.extension<StatusColors>()!.dueSoon;
    final segment = switch (role) {
      ClosesSegment(:final segment) => segment,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            segment == null
                ? refuelRoleText(role, l10n, units)!
                : segmentStateText(segment, l10n, units),
            key: const ValueKey('refuel-consumption'),
            style: theme.textTheme.bodyLarge,
          ),
          if (segment != null && segment.suspicious) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.warning_amber, color: amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.segmentSuspicious,
                    style: theme.textTheme.bodyMedium?.copyWith(color: amber),
                  ),
                ),
              ],
            ),
            if (!readOnly)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => context.push(
                    AppRoutes.editEntry(entry.vehicleId, entry.id),
                  ),
                  child: Text(l10n.actionEditRefuel),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
