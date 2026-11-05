import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/router/navigation.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/attachment.dart';
import '../../../data/models/owner.dart';
import '../../../data/models/vehicle.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_chip.dart';
import '../../../shared/widgets/detail_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/list_row.dart';
import '../../../shared/widgets/list_sections.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../../shared/widgets/vehicle_kind_icon.dart';
import '../../attachments/controllers/attachment_list_controller.dart';
import '../../attachments/widgets/attachment_actions.dart';
import '../../attachments/widgets/attachment_selection_app_bar.dart';
import '../../attachments/widgets/attachments_section.dart';
import '../../settings/controllers/settings_controller.dart';
import '../controllers/owner_deletion_controller.dart';
import '../controllers/owner_detail_controller.dart';

/// Detail of one owner, built as a detail archetype: the header (name,
/// phone and email), their vehicles (the active ones, then, when there
/// are any, the archived ones in a collapsed "Archived (n)" section,
/// each with its archive chip), the personal details, the notes and the
/// documents. The owner id comes from the path; an
/// unknown or deleted id shows a not-found page.
class OwnerDetailPage extends ConsumerWidget {
  /// Creates the page for the owner with [ownerId].
  const OwnerDetailPage({super.key, required this.ownerId});

  /// Id of the owner, from the path.
  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(ownerDetailProvider(ownerId));
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
      data: (detail) => detail == null
          ? NotFoundPage(message: l10n.ownerNotFound)
          : _OwnerDetailView(detail: detail),
    );
  }
}

/// The loaded owner detail.
class _OwnerDetailView extends ConsumerWidget {
  const _OwnerDetailView({required this.detail});

  final OwnerDetail detail;

  /// Deletes the owner after confirmation, then offers "Undo".
  ///
  /// An owner with vehicles is never deleted: the user gets an explicit
  /// explanation instead of the confirmation.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final owner = detail.owner;
    if (detail.vehicles.isNotEmpty) {
      await _explainHasVehicles(context, l10n);
      return;
    }
    final confirmed = await confirmDelete(
      context,
      title: l10n.deleteOwnerTitle,
      message: l10n.deleteOwnerMessage(owner.fullName),
    );
    if (!confirmed || !context.mounted) return;

    // Read before popping: the controller outlives this page, the page's
    // `ref` does not.
    final deletion = ref.read(ownerDeletionControllerProvider.notifier);
    final result = await deletion.delete(owner.id);
    if (!context.mounted) return;
    switch (result) {
      case ActionSuccess():
        context.popOrGo(AppRoutes.owners);
        showUndoSnackBar(
          messenger,
          l10n,
          l10n.ownerDeleted,
          onUndo: () async {
            final undone = await deletion.undo(owner.id);
            if (undone case ActionFailure(:final error)) {
              showErrorSnackBar(messenger, error.message(l10n));
            }
          },
        );
      case ActionFailure(error: ActionError.ownerHasVehicles):
        await _explainHasVehicles(context, l10n);
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  /// Tells the user the owner was not deleted because of their vehicles.
  Future<void> _explainHasVehicles(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return showInfoDialog(
      context,
      title: l10n.ownerNotDeletedTitle,
      message: l10n.errorOwnerHasVehicles,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final owner = detail.owner;
    final active = [
      for (final vehicle in detail.vehicles)
        if (!vehicle.isArchived) vehicle,
    ];
    final archived = [
      for (final vehicle in detail.vehicles)
        if (vehicle.isArchived) vehicle,
    ];
    final birthDate = owner.birthDate;
    final nationality = owner.nationality;
    final target = AttachmentTarget.owner(owner.id);
    final documentCount =
        ref.watch(attachmentsProvider(target)).value?.length ?? 0;
    const gap = SizedBox(height: 20);
    // The cards keep 20 dp at the sides; the vehicle rows bring 16 dp of
    // their own, so they get the 4 dp left.
    Widget inset(Widget child, {double by = 20}) => Padding(
          padding: EdgeInsets.symmetric(horizontal: by),
          child: child,
        );
    return Scaffold(
      // U29: the contextual bar while documents are selected.
      appBar: AttachmentSelectionAppBar(
        target: target,
        // The name is the header's, as on the vehicle page.
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: l10n.actionEdit,
              icon: const Icon(Icons.edit),
              onPressed: () => context.push(AppRoutes.editOwner(owner.id)),
            ),
            IconButton(
              tooltip: l10n.actionDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref),
            ),
          ],
        ),
      ),
      // One block per question, the most important first (who this is
      // and which vehicles are theirs); 20 dp between blocks.
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          inset(_Header(owner: owner)),
          gap,
          if (detail.vehicles.isEmpty)
            EmptyState(
              icon: Icons.directions_car_outlined,
              message: l10n.ownerNoVehicles,
            )
          else
            inset(
              by: 4,
              ListSections<Vehicle>(
                embedded: true,
                sections: [
                  ListSection(title: l10n.vehiclesTitle, items: active),
                ],
                folded: ListSection(
                  title: l10n.archivedVehiclesRow(archived.length),
                  items: archived,
                ),
                foldedIcon: Icon(
                  Icons.archive_outlined,
                  semanticLabel: l10n.archivedVehicleSemantics,
                ),
                row: (vehicle) => _OwnerVehicleRow(vehicle: vehicle),
              ),
            ),
          if (birthDate != null || nationality != null) ...[
            gap,
            inset(
              AppCard(
                label: l10n.ownerDataCard,
                gap: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (birthDate != null)
                      DetailField.row(
                        label: l10n.fieldBirthDate,
                        value: l10n.dateValue(birthDate.toLocalDateTime()),
                      ),
                    if (nationality != null)
                      DetailField.row(
                        label: l10n.fieldNationality,
                        // A known ISO code shows the country name in the app
                        // language; anything else (typed by hand) is shown
                        // as typed.
                        value: ref
                                .watch(countryNamesProvider)
                                .value
                                ?.displayNationality(
                                  nationality,
                                  Localizations.localeOf(context).languageCode,
                                ) ??
                            nationality,
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (owner.notes case final notes?) ...[
            gap,
            inset(
              Text(
                notes,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          gap,
          // U26: the owner's documents (driving licence, ID card, ...).
          inset(
            AppCard(
              label: l10n.documentsCount(documentCount),
              trailing: TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => addAttachments(context, ref, target),
                icon: const Icon(Icons.add),
                label: Text(l10n.addDocument),
              ),
              gap: 0,
              child: AttachmentsSection(
                target: target,
                emptyText: l10n.noDocuments,
                inset: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The header: a person icon in a 48 dp circle, the owner's full name and,
/// when known, their phone and email on a muted line.
class _Header extends StatelessWidget {
  const _Header({required this.owner});

  final Owner owner;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final contacts = [owner.phone, owner.email].nonNulls;
    return Row(
      children: [
        const CircleAvatar(radius: 24, child: Icon(Icons.person)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(owner.fullName, style: theme.textTheme.titleMedium),
              if (contacts.isNotEmpty)
                Text(
                  contacts.join(l10n.partsSeparator),
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

/// One vehicle of the owner, as a list row: kind icon, make and model (the
/// plate when unknown), then the plate (or the nickname or fuel) with the
/// current km; an archived one carries its archive chip ("Sold · Mar
/// 2024"). Opens the vehicle page.
class _OwnerVehicleRow extends ConsumerWidget {
  const _OwnerVehicleRow({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = unitFormatterOf(context, ref);
    final archiveChip = vehicle.archiveChipLabel(l10n, units);
    final makeAndModel = vehicle.makeAndModel;
    return ListRow(
      leading: Icon(vehicle.kind.icon, semanticLabel: vehicle.kind.label(l10n)),
      title: makeAndModel ?? vehicle.plate,
      thirdLine: l10n.vehicleHeaderSummary(
        makeAndModel != null
            ? vehicle.plate
            : vehicle.nickname ?? vehicle.fuelType.label(l10n),
        units.distance.format(vehicle.currentOdometerKm),
      ),
      trailing: [
        if (archiveChip != null)
          AppChip(
            label: archiveChip,
            icon: Icons.archive_outlined,
            iconLabel: l10n.archivedVehicleSemantics,
          ),
      ],
      onTap: () => context.push(AppRoutes.vehicle(vehicle.id)),
    );
  }
}
