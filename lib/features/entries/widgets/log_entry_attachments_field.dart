import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/attachment.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/feedback.dart';
import '../../attachments/controllers/attachment_list_controller.dart';
import '../../attachments/widgets/attachment_source_sheet.dart';
import '../../attachments/widgets/attachment_thumbnail.dart';
import '../controllers/log_entry_attachments_controller.dart';
import '../controllers/log_entry_form_controller.dart';

/// The "Attachments" section of the entry form (U22): the entry's saved
/// attachments (when editing) and the files picked in this form, each with
/// a remove button, then a tile that adds more. Nothing is written until
/// the form is saved; cancelling the form discards the picked files.
class LogEntryAttachmentsField extends ConsumerWidget {
  /// Creates the section of the form identified by [formKey].
  const LogEntryAttachmentsField({super.key, required this.formKey});

  /// Vehicle of the form, and the entry edited (`null` when creating).
  final LogEntryFormKey formKey;

  /// Size of a tile, in logical pixels.
  static const double _tileSize = 88;

  /// Asks for a source and stages the picked files.
  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller =
        ref.read(logEntryAttachmentsControllerProvider(formKey).notifier);
    final source = await showAttachmentSourceSheet(context);
    if (source == null) return;
    if (await controller.add(source) case ActionFailure(:final error)) {
      showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final draft = ref.watch(logEntryAttachmentsControllerProvider(formKey));
    final controller =
        ref.read(logEntryAttachmentsControllerProvider(formKey).notifier);
    final entryId = formKey.entryId;
    final saved = entryId == null
        ? const <Attachment>[]
        : [
            for (final a in ref
                    .watch(
                      attachmentsProvider(AttachmentTarget.logEntry(entryId)),
                    )
                    .value ??
                const <Attachment>[])
              if (!draft.removedIds.contains(a.id)) a,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.attachmentsTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final attachment in saved)
              _RemovableTile(
                name: attachment.fileName,
                onRemove: () => controller.removeSaved(attachment.id),
                child: AttachmentThumbnail(
                  path: ref.watch(attachmentFilePathProvider(attachment)),
                  kind: attachment.kind,
                  label: attachment.caption ?? attachment.fileName,
                  size: _tileSize,
                ),
              ),
            for (final file in draft.staged)
              _RemovableTile(
                name: file.fileName,
                onRemove: () => controller.removeStaged(file),
                child: AttachmentThumbnail(
                  path: file.path,
                  kind: file.kind,
                  label: file.fileName,
                  size: _tileSize,
                ),
              ),
            _AddTile(
              size: _tileSize,
              busy: draft.busy,
              onTap: draft.busy ? null : () => _add(context, ref),
            ),
          ],
        ),
        if (draft.busy) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          Text(l10n.attachmentsWorking),
        ],
      ],
    );
  }
}

/// A tile of the form with a remove button in its corner, and the file
/// name under it.
class _RemovableTile extends StatelessWidget {
  const _RemovableTile({
    required this.name,
    required this.onRemove,
    required this.child,
  });

  final String name;
  final VoidCallback onRemove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SizedBox(
      width: LogEntryAttachmentsField._tileSize,
      child: Column(
        children: [
          Stack(
            children: [
              child,
              PositionedDirectional(
                top: 0,
                end: 0,
                child: IconButton.filledTonal(
                  tooltip: l10n.attachmentRemove,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  onPressed: onRemove,
                ),
              ),
            ],
          ),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// The tile that adds attachments, with a spinner while files are copied.
class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.size,
    required this.busy,
    required this.onTap,
  });

  final double size;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: l10n.addAttachment,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('entry-add-attachment'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outline),
          ),
          child: Center(
            child: busy
                ? const CircularProgressIndicator()
                : Icon(
                    Icons.add_photo_alternate_outlined,
                    color: scheme.primary,
                  ),
          ),
        ),
      ),
    );
  }
}
