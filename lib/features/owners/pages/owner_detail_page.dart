import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/router/navigation.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/attachment.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/detail_field.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../../shared/widgets/vehicle_kind_icon.dart';
import '../../attachments/widgets/attachment_actions.dart';
import '../../attachments/widgets/attachments_section.dart';
import '../../attachments/widgets/attachment_selection_app_bar.dart';
import '../controllers/owner_deletion_controller.dart';
import '../controllers/owner_detail_controller.dart';

/// Detail of one owner, with their vehicles. The owner id comes from the
/// path; an unknown or deleted id shows a not-found page.
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
        body: MessageView(icon: Icons.error_outline, message: l10n.loadError),
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
    final birthDate = owner.birthDate;
    final target = AttachmentTarget.owner(owner.id);
    return Scaffold(
      // U29: the contextual bar while documents are selected.
      appBar: AttachmentSelectionAppBar(
        target: target,
        appBar: AppBar(
          title: Text(owner.fullName),
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
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          DetailField(label: l10n.fieldFirstName, value: owner.firstName),
          if (owner.lastName case final lastName?)
            DetailField(label: l10n.fieldLastName, value: lastName),
          if (birthDate != null)
            DetailField(
              label: l10n.fieldBirthDate,
              value: l10n.dateValue(birthDate.toLocalDateTime()),
            ),
          if (owner.nationality case final nationality?)
            DetailField(
              label: l10n.fieldNationality,
              // A known ISO code shows the country name in the app language;
              // anything else (typed by hand) is shown as typed.
              value: ref.watch(countryNamesProvider).value?.displayNationality(
                        nationality,
                        Localizations.localeOf(context).languageCode,
                      ) ??
                  nationality,
            ),
          if (owner.phone case final phone?)
            DetailField(label: l10n.fieldPhone, value: phone),
          if (owner.email case final email?)
            DetailField(label: l10n.fieldEmail, value: email),
          if (owner.notes case final notes?)
            DetailField(label: l10n.fieldNotes, value: notes),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l10n.vehiclesTitle, style: theme.textTheme.titleMedium),
          ),
          if (detail.vehicles.isEmpty)
            ListTile(title: Text(l10n.ownerNoVehicles))
          else
            for (final vehicle in detail.vehicles)
              ListTile(
                leading: Icon(vehicle.kind.icon),
                title: Text(vehicle.makeAndModel ?? vehicle.plate),
                subtitle: Text(
                  vehicle.makeAndModel != null
                      ? vehicle.plate
                      : vehicle.nickname ?? vehicle.fuelType.label(l10n),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.vehicle(vehicle.id)),
              ),
          const Divider(height: 32),
          // U26: the owner's documents (driving licence, ID card, ...).
          SectionHeader(
            title: l10n.documentsTitle,
            actionLabel: l10n.addDocument,
            onAction: () => addAttachments(context, ref, target),
          ),
          AttachmentsSection(
            target: target,
            emptyText: l10n.noDocuments,
          ),
        ],
      ),
    );
  }
}
