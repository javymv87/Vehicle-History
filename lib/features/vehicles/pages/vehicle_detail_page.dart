import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/router/navigation.dart';
import '../../../data/models/attachment.dart';
import '../../../data/models/trashed_vehicle.dart';
import '../../../data/models/vehicle.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/detail_field.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../../shared/widgets/vehicle_kind_icon.dart';
import '../../attachments/controllers/attachment_selection_controller.dart';
import '../../attachments/widgets/attachment_actions.dart';
import '../../attachments/widgets/attachment_selection_app_bar.dart';
import '../../attachments/widgets/attachments_section.dart';
import '../../entries/controllers/log_entry_history_controller.dart';
import '../../entries/widgets/log_entry_history_view.dart';
import '../../mileage/widgets/mileage_history_view.dart';
import '../../settings/controllers/settings_controller.dart';
import '../controllers/vehicle_archive_controller.dart';
import '../controllers/vehicle_deletion_controller.dart';
import '../controllers/vehicle_detail_controller.dart';
import '../controllers/vehicle_list_controller.dart';
import '../controllers/vehicle_tab_controller.dart';
import '../widgets/archive_banner.dart';
import '../widgets/archive_dialog.dart';

/// The page of one vehicle: its history first, then its odometer readings,
/// its documents and its details. The vehicle id comes from the path; an
/// unknown or deleted id shows a not-found page. An archived vehicle opens
/// read-only: a banner under the app bar, no add, edit or delete affordance
/// anywhere, only "Reactivate" and "Move to Trash".
class VehicleDetailPage extends ConsumerWidget {
  /// Creates the page for the vehicle with [vehicleId], opened on
  /// [initialTab].
  const VehicleDetailPage({
    super.key,
    required this.vehicleId,
    this.initialTab = VehicleTab.history,
  });

  /// Id of the vehicle, from the path.
  final String vehicleId;

  /// Tab shown when the page opens, from the `tab` query parameter (U15).
  final VehicleTab initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(vehicleDetailProvider(vehicleId));
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
      data: (item) => item == null
          ? NotFoundPage(message: l10n.vehicleNotFound)
          : _VehicleDetailView(item: item, initialTab: initialTab),
    );
  }
}

/// The loaded vehicle page (`Docs/03_features.md`, U1–U2, U11–U15, U25): a
/// compact header, then four tabs, History (the default), Mileage,
/// Documents and Details, and a button that adds what the tab shows. The
/// overflow menu archives the vehicle, or reactivates it, and moves it to
/// the Trash.
class _VehicleDetailView extends ConsumerStatefulWidget {
  const _VehicleDetailView({required this.item, required this.initialTab});

  final VehicleWithOwner item;
  final VehicleTab initialTab;

  @override
  ConsumerState<_VehicleDetailView> createState() => _VehicleDetailViewState();
}

class _VehicleDetailViewState extends ConsumerState<_VehicleDetailView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: VehicleTab.values.length,
    initialIndex: widget.initialTab.index,
    vsync: this,
  )
    // The filter button and the FAB depend on the tab.
    ..addListener(() {
      if (_tabs.indexIsChanging) return;
      // The selection of documents ends when their tab is left.
      if (_tab != VehicleTab.documents) {
        ref.read(attachmentSelectionProvider(_documents).notifier).clear();
      }
      setState(() {});
    });

  /// The vehicle's own attachments, listed on the Documents tab.
  AttachmentTarget get _documents =>
      AttachmentTarget.vehicle(widget.item.vehicle.id);

  /// The tab currently shown.
  VehicleTab get _tab => VehicleTab.values[_tabs.index];

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Deletes the vehicle after a confirmation that says what goes with it
  /// (U16), then offers "Undo". The vehicle moves to the Trash.
  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final vehicle = widget.item.vehicle;
    // Read before popping: the controller outlives this page, the page's
    // `ref` does not.
    final deletion = ref.read(vehicleDeletionControllerProvider.notifier);
    final counted = await deletion.countContents(vehicle.id);
    if (!mounted) return;
    final VehicleContents contents;
    switch (counted) {
      case ActionSuccess(:final value):
        contents = value;
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
        return;
    }
    final confirmed = await confirmDelete(
      context,
      title: l10n.deleteVehicleTitle(vehicle.displayNameWithPlate(l10n)),
      message: contents.attachmentCount == 0
          ? l10n.deleteVehicleMessage(
              contents.entryCount,
              contents.readingCount,
            )
          : l10n.deleteVehicleMessageWithAttachments(
              contents.entryCount,
              contents.readingCount,
              contents.attachmentCount,
            ),
    );
    if (!confirmed || !mounted) return;

    final result = await deletion.delete(vehicle.id);
    if (!mounted) return;
    switch (result) {
      case ActionSuccess():
        context.popOrGo(AppRoutes.vehicles);
        showUndoSnackBar(
          messenger,
          l10n,
          l10n.vehicleDeleted,
          onUndo: () async {
            final undone = await deletion.undo(vehicle.id);
            if (undone case ActionFailure(:final error)) {
              showErrorSnackBar(messenger, error.message(l10n));
            }
          },
        );
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  /// Opens the archive dialog, with the last reading as the final km, and
  /// says so when the vehicle was archived. The page stays open and turns
  /// read-only by itself: the vehicle provider emits the archived vehicle.
  Future<void> _archive() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final vehicle = widget.item.vehicle;
    final lastReading = await ref
        .read(vehicleArchiveControllerProvider.notifier)
        .lastReading(vehicle.id);
    if (!mounted) return;
    final archived = await showArchiveDialog(
      context,
      vehicle: vehicle,
      lastReading: lastReading,
    );
    if (archived != null) {
      showSavedSnackBar(messenger, l10n.vehicleArchivedToast);
    }
  }

  /// Reactivates the vehicle, with no confirmation: it is always allowed
  /// and always reversible.
  Future<void> _reactivate() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(vehicleArchiveControllerProvider.notifier)
        .reactivate(widget.item.vehicle.id);
    switch (result) {
      case ActionSuccess():
        showSavedSnackBar(messenger, l10n.vehicleReactivatedToast);
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vehicle = widget.item.vehicle;
    final readOnly = vehicle.isArchived;
    final filter = ref.watch(logEntryFilterProvider(vehicle.id));
    // An action that outlived its page (the odometer offer) asks for a tab.
    ref.listen(vehicleTabRequestProvider, (previous, request) {
      if (request != null && request.vehicleId == vehicle.id) {
        _tabs.animateTo(request.tab.index);
      }
    });
    final selectingDocuments =
        ref.watch(attachmentSelectionProvider(_documents)).isNotEmpty;
    return Scaffold(
      // U29: the contextual bar while documents are selected.
      appBar: AttachmentSelectionAppBar(
        target: _documents,
        appBar: AppBar(
          actions: [
            if (_tab == VehicleTab.history)
              IconButton(
                tooltip: l10n.filterAction,
                // A dot on the icon tells that filters are active.
                icon: Badge(
                  isLabelVisible: !filter.isEmpty,
                  child: const Icon(Icons.filter_list),
                ),
                onPressed: () => openLogEntryFilters(context, ref, vehicle.id),
              ),
            if (!readOnly)
              IconButton(
                tooltip: l10n.actionEdit,
                icon: const Icon(Icons.edit),
                onPressed: () =>
                    context.push(AppRoutes.editVehicle(vehicle.id)),
              ),
            PopupMenuButton<VoidCallback>(
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: readOnly ? _reactivate : _archive,
                  child: Text(
                    readOnly ? l10n.reactivateAction : l10n.archiveAction,
                  ),
                ),
                PopupMenuItem(
                  value: _delete,
                  child: Text(l10n.moveToTrashAction),
                ),
              ],
            ),
          ],
        ),
      ),
      // No button at all on an archived vehicle: nothing can be added.
      floatingActionButton: readOnly
          ? null
          : switch (_tab) {
              // On Details the button keeps adding entries, as before step 5.
              VehicleTab.history ||
              VehicleTab.details =>
                FloatingActionButton.extended(
                  heroTag: AppRoutes.newEntry(vehicle.id),
                  onPressed: () => context.push(AppRoutes.newEntry(vehicle.id)),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addEntry),
                ),
              VehicleTab.mileage => FloatingActionButton.extended(
                  heroTag: AppRoutes.newMileageReading(vehicle.id),
                  onPressed: () =>
                      context.push(AppRoutes.newMileageReading(vehicle.id)),
                  icon: const Icon(Icons.speed),
                  label: Text(l10n.addMileageReading),
                ),
              // Hidden in the selection mode, as the page's own actions are.
              VehicleTab.documents when selectingDocuments => null,
              VehicleTab.documents => FloatingActionButton.extended(
                  heroTag: 'documents-${vehicle.id}',
                  onPressed: () => addAttachments(context, ref, _documents),
                  icon: const Icon(Icons.note_add_outlined),
                  label: Text(l10n.addDocument),
                ),
            },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (readOnly)
            ArchiveBanner(vehicle: vehicle, onReactivate: _reactivate),
          _VehicleHeader(vehicle: vehicle),
          TabBar(
            controller: _tabs,
            // Four tabs with large text do not fit at 360 dp: they scroll.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l10n.tabHistory),
              Tab(text: l10n.tabMileage),
              Tab(text: l10n.tabDocuments),
              Tab(text: l10n.tabDetails),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                LogEntryHistoryView(vehicleId: vehicle.id),
                MileageHistoryView(vehicleId: vehicle.id),
                ListView(
                  // Room at the bottom so the FAB never covers the last row.
                  padding: const EdgeInsets.only(top: 8, bottom: 88),
                  children: [
                    AttachmentsSection(
                      target: _documents,
                      emptyText: l10n.noDocuments,
                    ),
                  ],
                ),
                _VehicleInfo(item: widget.item),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The compact header always shown above the tabs: kind icon, make and
/// model (the plate for vehicles without them), plate and current km.
class _VehicleHeader extends ConsumerWidget {
  const _VehicleHeader({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = unitFormatterOf(context, ref);
    final theme = Theme.of(context);
    final makeAndModel = vehicle.makeAndModel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          CircleAvatar(
            child: Icon(
              vehicle.kind.icon,
              semanticLabel: vehicle.kind.label(l10n),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Capped in lines: the header stays compact with long names
                // and very large text, leaving the screen to the history.
                Text(
                  makeAndModel ?? vehicle.plate,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  makeAndModel == null
                      ? units.distance.format(vehicle.currentOdometerKm)
                      : l10n.vehicleHeaderSummary(
                          vehicle.plate,
                          units.distance.format(vehicle.currentOdometerKm),
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Details tab: every field of the vehicle, read-only.
class _VehicleInfo extends ConsumerWidget {
  const _VehicleInfo({required this.item});

  final VehicleWithOwner item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = unitFormatterOf(context, ref);
    final vehicle = item.vehicle;
    final owner = item.owner;
    return ListView(
      // Room at the bottom so the FAB never covers the last field.
      padding: const EdgeInsets.only(top: 8, bottom: 88),
      children: [
        ListTile(
          leading: Icon(vehicle.kind.icon),
          title: Text(vehicle.kind.label(l10n)),
          subtitle: Text(l10n.fieldKind),
        ),
        if (vehicle.make case final make?)
          DetailField(label: l10n.fieldMake, value: make),
        if (vehicle.model case final model?)
          DetailField(label: l10n.fieldModel, value: model),
        if (vehicle.modelYear case final year?)
          DetailField(label: l10n.fieldModelYear, value: '$year'),
        if (vehicle.version case final version?)
          DetailField(label: l10n.fieldVersion, value: version),
        DetailField(label: l10n.fieldPlate, value: vehicle.plate),
        if (vehicle.nickname case final nickname?)
          DetailField(label: l10n.fieldNickname, value: nickname),
        if (owner != null)
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(owner.fullName),
            subtitle: Text(l10n.fieldOwner),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.owner(owner.id)),
          ),
        DetailField(
          label: l10n.fieldFuelType,
          value: vehicle.fuelType.label(l10n),
        ),
        DetailField(
          label: l10n.fieldCurrentKm,
          value: units.distance.format(vehicle.currentOdometerKm),
          note: l10n.vehicleKmNote,
        ),
        if (vehicle.recommendedEngineOil case final oil?)
          DetailField(label: l10n.fieldRecommendedOil, value: oil),
        if (vehicle.manufacturerNotes case final notes?)
          DetailField(label: l10n.fieldManufacturerNotes, value: notes),
      ],
    );
  }
}
