import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/attachment.dart';
import '../../../l10n/app_localizations.dart';
import '../controllers/attachment_actions_controller.dart';
import '../controllers/attachment_list_controller.dart';
import '../controllers/attachment_selection_controller.dart';
import 'attachment_actions.dart';

/// The app bar of a page with an attachment list (U29): [appBar] as long
/// as nothing is selected, and while attachments of [target] are selected
/// the contextual bar of the selection mode, the same on the entry detail,
/// the vehicle's Documents tab and the owner detail: "Cancel selection",
/// "N selected", then "Select all", "Share", "Save to…" and "Delete".
class AttachmentSelectionAppBar extends ConsumerWidget
    implements PreferredSizeWidget {
  /// Creates the bar of a page listing the attachments of [target], showing
  /// [appBar] outside the selection mode.
  const AttachmentSelectionAppBar({
    super.key,
    required this.target,
    required this.appBar,
  });

  /// The entry, vehicle or owner whose attachments the page lists.
  final AttachmentTarget target;

  /// The page's own app bar.
  final PreferredSizeWidget appBar;

  @override
  Size get preferredSize => appBar.preferredSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(attachmentSelectionProvider(target));
    if (selected.isEmpty) return appBar;
    final l10n = AppLocalizations.of(context);
    final selection = ref.read(attachmentSelectionProvider(target).notifier);
    final all = ref.watch(attachmentsProvider(target)).value ?? const [];
    // In display order, whatever the order they were selected in.
    final chosen = [
      for (final attachment in all)
        if (selected.contains(attachment.id)) attachment,
    ];
    final busy = ref.watch(attachmentActionsControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      leading: IconButton(
        tooltip: l10n.actionCancelSelection,
        icon: const Icon(Icons.close),
        onPressed: selection.clear,
      ),
      title: Text(l10n.attachmentsSelected(selected.length)),
      actions: [
        if (chosen.length < all.length)
          IconButton(
            tooltip: l10n.actionSelectAll,
            icon: const Icon(Icons.select_all),
            onPressed: () => selection.selectAll(all.map((a) => a.id)),
          ),
        IconButton(
          tooltip: l10n.actionShare,
          icon: const Icon(Icons.share),
          onPressed: busy || chosen.isEmpty
              ? null
              : () => shareAttachments(
                    context,
                    ref,
                    chosen,
                    onDone: selection.clear,
                  ),
        ),
        IconButton(
          tooltip: l10n.actionSaveTo,
          icon: const Icon(Icons.save_alt),
          onPressed: busy || chosen.isEmpty
              ? null
              : () => saveAttachmentsTo(
                    context,
                    ref,
                    chosen,
                    onDone: selection.clear,
                  ),
        ),
        IconButton(
          tooltip: l10n.actionDelete,
          icon: const Icon(Icons.delete_outline),
          onPressed: busy || chosen.isEmpty
              ? null
              : () => deleteAttachments(
                    context,
                    ref,
                    chosen,
                    onDeleted: selection.clear,
                  ),
        ),
      ],
      // No progress bar here: it would change the bar's height. The list
      // itself shows one while an action works on files.
    );
  }
}
