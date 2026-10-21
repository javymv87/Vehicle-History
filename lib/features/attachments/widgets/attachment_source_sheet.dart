import 'package:flutter/material.dart';

import '../../../data/attachments/attachment_picker.dart';
import '../../../l10n/app_localizations.dart';

/// Asks where a new attachment comes from: Camera, Gallery or File (U22,
/// U25, U26). Resolves to `null` when the sheet is dismissed.
Future<AttachmentSource?> showAttachmentSourceSheet(BuildContext context) {
  return showModalBottomSheet<AttachmentSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => const AttachmentSourceSheet(),
  );
}

/// The content of [showAttachmentSourceSheet]: one 56 dp row per source.
class AttachmentSourceSheet extends StatelessWidget {
  /// Creates the sheet.
  const AttachmentSourceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget option(AttachmentSource source, IconData icon, String label) =>
        ListTile(
          leading: Icon(icon),
          title: Text(label),
          onTap: () => Navigator.of(context).pop(source),
        );
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.attachmentSourceTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          option(
            AttachmentSource.camera,
            Icons.photo_camera_outlined,
            l10n.attachmentSourceCamera,
          ),
          option(
            AttachmentSource.gallery,
            Icons.photo_library_outlined,
            l10n.attachmentSourceGallery,
          ),
          option(
            AttachmentSource.file,
            Icons.attach_file,
            l10n.attachmentSourceFile,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
