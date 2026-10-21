import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../data/models/attachment.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/file_size.dart';
import '../controllers/attachment_actions_controller.dart';
import '../controllers/attachment_list_controller.dart';
import 'attachment_actions.dart';
import 'attachment_thumbnail.dart';

/// The attachments of [target] (U23, U25, U26): a grid of thumbnails for
/// the images, which open the full-screen viewer, then one row per PDF or
/// other file (icon, name, size), which opens with the phone's app and has
/// a menu with "Save to…", "Edit caption" and "Delete".
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
    final list = attachments.value;
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
    return Column(
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
    );
  }
}

/// One image of [AttachmentsSection]: its thumbnail, opening the viewer.
class _ImageTile extends ConsumerWidget {
  const _ImageTile({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push(AppRoutes.attachment(attachment.id)),
      child: AttachmentThumbnail(
        path: ref.watch(attachmentFilePathProvider(attachment)),
        kind: attachment.kind,
        label: attachment.caption ?? attachment.fileName,
      ),
    );
  }
}

/// What the menu of an [AttachmentFileTile] can do.
enum _FileAction { saveTo, editCaption, delete }

/// One PDF or other file of [AttachmentsSection]: icon, name, caption, size
/// and day, opening with the phone's app, with a menu of actions. A file
/// missing on the phone says "File not found" instead of its size.
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
      onTap: () => openAttachment(context, ref, attachment),
      trailing: PopupMenuButton<_FileAction>(
        onSelected: (action) => switch (action) {
          _FileAction.saveTo => saveAttachmentTo(context, ref, attachment),
          _FileAction.editCaption =>
            editAttachmentCaption(context, ref, attachment),
          _FileAction.delete => deleteAttachment(context, ref, attachment),
        },
        itemBuilder: (context) => [
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
      ),
    );
  }
}
