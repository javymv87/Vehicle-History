import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../data/models/attachment.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/file_size.dart';
import '../controllers/attachment_actions_controller.dart';
import '../controllers/attachment_list_controller.dart';
import '../controllers/attachment_selection_controller.dart';
import 'attachment_actions.dart';
import 'attachment_selection_app_bar.dart';
import 'attachment_thumbnail.dart';

/// The attachments of [target] (U23, U25, U26): a grid of thumbnails for
/// the images, which open the full-screen viewer, then one row per PDF or
/// other file (icon, name, size), which opens with the phone's app and has
/// a menu with "Share", "Save to…", "Edit caption" and "Delete".
///
/// A long press on any of them starts the selection mode (U29): taps then
/// select and unselect, the page's [AttachmentSelectionAppBar] offers the
/// actions on the selection, and Back ends the mode instead of leaving the
/// page.
///
/// Not scrollable itself: it is placed inside the page's list. Shows
/// [emptyText] when there is nothing, and a progress bar while an
/// attachment action works on files.
class AttachmentsSection extends ConsumerWidget {
  /// Creates the section for [target].
  const AttachmentsSection({
    super.key,
    required this.target,
    required this.emptyText,
  });

  /// The entry, vehicle or owner whose attachments are shown.
  final AttachmentTarget target;

  /// Text shown when [target] has no attachments.
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final attachments = ref.watch(attachmentsProvider(target));
    final busy = ref.watch(attachmentActionsControllerProvider);
    final selected = ref.watch(attachmentSelectionProvider(target));
    final list = attachments.value;
    // What was deleted meanwhile (here, from the viewer) leaves the selection.
    ref.listen(attachmentsProvider(target), (previous, next) {
      if (next.value case final live?) {
        ref
            .read(attachmentSelectionProvider(target).notifier)
            .keepOnly({for (final a in live) a.id});
      }
    });
    if (list == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    final images = [
      for (final a in list)
        if (a.isImage) a,
    ];
    final documents = [
      for (final a in list)
        if (!a.isImage) a,
    ];
    return PopScope(
      // In the selection mode Back ends the mode, not the page.
      canPop: selected.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          ref.read(attachmentSelectionProvider(target).notifier).clear();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (busy) ...[
            const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(l10n.attachmentsWorking),
            ),
          ],
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(emptyText),
            ),
          if (images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final image in images) _ImageTile(attachment: image),
                ],
              ),
            ),
          for (final document in documents)
            AttachmentFileTile(attachment: document),
        ],
      ),
    );
  }
}

/// One image of [AttachmentsSection]: its thumbnail, opening the viewer,
/// or selected and unselected in the selection mode, with a check mark.
class _ImageTile extends ConsumerWidget {
  const _ImageTile({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final provider = attachmentSelectionProvider(attachment.target);
    final selection = ref.watch(provider);
    final isSelected = selection.contains(attachment.id);
    final selecting = selection.isNotEmpty;
    return Semantics(
      selected: selecting ? isSelected : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: selecting
            ? () => ref.read(provider.notifier).toggle(attachment.id)
            : () => context.push(AppRoutes.attachment(attachment.id)),
        onLongPress: () => ref.read(provider.notifier).toggle(attachment.id),
        child: Stack(
          children: [
            AnimatedScale(
              // A selected picture shrinks a little, as in a gallery.
              scale: isSelected ? 0.88 : 1,
              duration: const Duration(milliseconds: 120),
              child: AttachmentThumbnail(
                path: ref.watch(attachmentFilePathProvider(attachment)),
                kind: attachment.kind,
                label: attachment.caption ?? attachment.fileName,
              ),
            ),
            if (selecting)
              Positioned(
                top: 4,
                left: 4,
                child: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected ? scheme.primary : Colors.white,
                  shadows: const [Shadow(blurRadius: 4)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What the menu of an [AttachmentFileTile] can do.
enum _FileAction { share, saveTo, editCaption, delete }

/// One PDF or other file of [AttachmentsSection]: icon, name, caption, size
/// and day, opening with the phone's app, with a menu of actions. A file
/// missing on the phone says "File not found" instead of its size. In the
/// selection mode a tap selects it and a check box replaces the menu.
class AttachmentFileTile extends ConsumerWidget {
  /// Creates the row of [attachment].
  const AttachmentFileTile({super.key, required this.attachment});

  /// The attachment shown.
  final Attachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final exists =
        ref.watch(attachmentFileExistsProvider(attachment)).value ?? true;
    final provider = attachmentSelectionProvider(attachment.target);
    final selection = ref.watch(provider);
    final isSelected = selection.contains(attachment.id);
    final selecting = selection.isNotEmpty;
    final details = l10n.attachmentSizeAndDate(
      formatFileSize(attachment.sizeBytes, l10n),
      attachment.createdAt.toLocal(),
    );
    return ListTile(
      leading: Icon(
        exists ? attachmentKindIcon(attachment.kind) : Icons.broken_image,
        color: exists ? null : theme.colorScheme.error,
      ),
      title: Text(attachment.fileName),
      subtitle: Text(
        [
          if (attachment.caption case final caption?) caption,
          if (exists) details else l10n.attachmentFileMissing,
        ].join('\n'),
      ),
      isThreeLine: attachment.caption != null,
      selected: isSelected,
      onTap: selecting
          ? () => ref.read(provider.notifier).toggle(attachment.id)
          : () => openAttachment(context, ref, attachment),
      onLongPress: () => ref.read(provider.notifier).toggle(attachment.id),
      trailing: selecting
          ? Checkbox(
              value: isSelected,
              onChanged: (_) =>
                  ref.read(provider.notifier).toggle(attachment.id),
            )
          : _menu(context, ref, theme, l10n),
    );
  }

  /// The menu of actions on this one file.
  Widget _menu(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    return PopupMenuButton<_FileAction>(
      onSelected: (action) => switch (action) {
        _FileAction.share => shareAttachments(context, ref, [attachment]),
        _FileAction.saveTo => saveAttachmentTo(context, ref, attachment),
        _FileAction.editCaption =>
          editAttachmentCaption(context, ref, attachment),
        _FileAction.delete => deleteAttachment(context, ref, attachment),
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _FileAction.share,
          child: Text(l10n.actionShare),
        ),
        PopupMenuItem(
          value: _FileAction.saveTo,
          child: Text(l10n.actionSaveTo),
        ),
        PopupMenuItem(
          value: _FileAction.editCaption,
          child: Text(l10n.actionEditCaption),
        ),
        PopupMenuItem(
          value: _FileAction.delete,
          child: Text(
            l10n.actionDelete,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }
}
