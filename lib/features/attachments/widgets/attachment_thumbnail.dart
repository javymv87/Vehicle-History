import 'dart:io';

import 'package:flutter/material.dart';

import '../../../data/models/attachment.dart';
import '../../../l10n/app_localizations.dart';

/// A square preview of an attachment file at [path]: the picture itself for
/// an image, decoded at the size shown (`cacheWidth`, no thumbnail files),
/// or an icon for a PDF or other file. A file that cannot be read shows the
/// "File not found" placeholder.
class AttachmentThumbnail extends StatelessWidget {
  /// Creates the preview of the file at [path], of [kind], [size] wide.
  const AttachmentThumbnail({
    super.key,
    required this.path,
    required this.kind,
    required this.label,
    this.size = 96,
  });

  /// Absolute path of the file.
  final String path;

  /// What the file is.
  final AttachmentKind kind;

  /// What the preview shows, for screen readers (the file name or caption).
  final String label;

  /// Width and height of the preview, in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget content;
    if (kind == AttachmentKind.image) {
      final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
      content = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: pixels,
        semanticLabel: label,
        errorBuilder: (context, error, stackTrace) =>
            const AttachmentMissingPlaceholder(),
      );
    } else {
      content = Semantics(
        label: label,
        child: Icon(
          attachmentKindIcon(kind),
          size: size / 2,
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Center(child: content),
        ),
      ),
    );
  }
}

/// The icon of an attachment of [kind].
IconData attachmentKindIcon(AttachmentKind kind) => switch (kind) {
      AttachmentKind.image => Icons.image_outlined,
      AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
      AttachmentKind.other => Icons.insert_drive_file_outlined,
    };

/// Shown in place of an attachment whose file is missing on the phone: the
/// row is kept, the file is not there.
class AttachmentMissingPlaceholder extends StatelessWidget {
  /// Creates the placeholder.
  const AttachmentMissingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: theme.colorScheme.error),
          Flexible(
            child: Text(
              l10n.attachmentFileMissing,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
