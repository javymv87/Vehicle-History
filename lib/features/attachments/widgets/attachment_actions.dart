import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/attachment.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/text_input_dialog.dart';
import '../controllers/attachment_actions_controller.dart';
import 'attachment_source_sheet.dart';

// The user-facing flows around the attachment actions, shared by the entry
// detail, the Documents tab, the owner detail and the viewer: each shows
// the sheet or dialog it needs and the resulting snackbar.

/// Asks for a source and adds the picked files to [target], then confirms
/// with "N attachments added" or shows why nothing was added.
Future<void> addAttachments(
  BuildContext context,
  WidgetRef ref,
  AttachmentTarget target,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(attachmentActionsControllerProvider.notifier);
  final source = await showAttachmentSourceSheet(context);
  if (source == null) return;
  switch (await controller.addFrom(target, source)) {
    case ActionSuccess(value: 0):
      break;
    case ActionSuccess(:final value):
      showSavedSnackBar(messenger, l10n.attachmentAdded(value));
    case ActionFailure(:final error):
      showErrorSnackBar(messenger, error.message(l10n));
  }
}

/// Opens [attachment] with the phone's app, or says why it could not.
Future<void> openAttachment(
  BuildContext context,
  WidgetRef ref,
  Attachment attachment,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final result =
      await ref.read(attachmentActionsControllerProvider.notifier).open(
            attachment,
          );
  if (result case ActionFailure(:final error)) {
    showErrorSnackBar(messenger, error.message(l10n));
  }
}

/// "Save to…": copies the file of [attachment] where the user chooses.
Future<void> saveAttachmentTo(
  BuildContext context,
  WidgetRef ref,
  Attachment attachment,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final result =
      await ref.read(attachmentActionsControllerProvider.notifier).saveTo(
            attachment,
          );
  switch (result) {
    case ActionSuccess(value: true):
      showSavedSnackBar(messenger, l10n.attachmentSaved);
    case ActionSuccess():
      break;
    case ActionFailure(:final error):
      showErrorSnackBar(messenger, error.message(l10n));
  }
}

/// Edits the caption of [attachment] in a dialog; a blank caption clears
/// it.
Future<void> editAttachmentCaption(
  BuildContext context,
  WidgetRef ref,
  Attachment attachment,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(attachmentActionsControllerProvider.notifier);
  final caption = await showTextInputDialog(
    context,
    title: l10n.actionEditCaption,
    label: l10n.fieldCaption,
    initialText: attachment.caption ?? '',
    textCapitalization: TextCapitalization.sentences,
    allowEmpty: true,
  );
  if (caption == null) return;
  switch (await controller.updateCaption(attachment.id, caption)) {
    case ActionSuccess():
      showSavedSnackBar(messenger, l10n.captionSaved);
    case ActionFailure(:final error):
      showErrorSnackBar(messenger, error.message(l10n));
  }
}

/// Deletes [attachment] after confirmation, then offers "Undo". Calls
/// [onDeleted] (for instance to close the viewer) once it is deleted.
///
/// Resolves to whether it was deleted.
Future<bool> deleteAttachment(
  BuildContext context,
  WidgetRef ref,
  Attachment attachment, {
  VoidCallback? onDeleted,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // Read now: the controller outlives the page, the page's `ref` may not.
  final controller = ref.read(attachmentActionsControllerProvider.notifier);
  final confirmed = await confirmDelete(
    context,
    title: l10n.deleteAttachmentTitle,
    message: l10n.deleteAttachmentMessage(attachment.fileName),
  );
  if (!confirmed) return false;
  switch (await controller.delete(attachment.id)) {
    case ActionSuccess():
      onDeleted?.call();
      showUndoSnackBar(
        messenger,
        l10n,
        l10n.attachmentDeleted,
        onUndo: () async {
          final undone = await controller.undo(attachment.id);
          if (undone case ActionFailure(:final error)) {
            showErrorSnackBar(messenger, error.message(l10n));
          }
        },
      );
      return true;
    case ActionFailure(:final error):
      showErrorSnackBar(messenger, error.message(l10n));
      return false;
  }
}
