import 'package:flutter/material.dart';

import '../../../data/backup/backup_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/file_size.dart';

/// Asks the user to confirm importing the package described by [preview]:
/// what it contains, its attachment files and their size, how many files
/// are missing from it, when it was last changed, and, in bold, that the
/// import replaces all the current data (U20).
///
/// Resolves to `true` only when the user taps "Import", which is drawn in
/// the error colour like every destructive action; cancel is the default.
Future<bool> confirmImport(
  BuildContext context,
  ImportPreview preview,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => ImportConfirmationDialog(preview: preview),
  );
  return confirmed ?? false;
}

/// The dialog shown by [confirmImport].
class ImportConfirmationDialog extends StatelessWidget {
  /// Creates the dialog for the package described by [preview].
  const ImportConfirmationDialog({super.key, required this.preview});

  /// What the package holds.
  final ImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final counts = preview.manifest.counts;
    final lastModified = preview.manifest.lastModifiedAt;
    return AlertDialog(
      // Long messages with very large text scroll instead of overflowing.
      scrollable: true,
      title: Text(l10n.importConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lastModified == null
                ? l10n.importConfirmContentsEmpty
                : l10n.importConfirmContents(
                    counts.vehicles,
                    counts.logEntries,
                    counts.mileageReadings,
                    lastModified.toLocal(),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.importConfirmAttachments(
              preview.attachmentCount,
              formatFileSize(preview.attachmentBytes, l10n),
            ),
          ),
          if (preview.missingFiles > 0) ...[
            const SizedBox(height: 8),
            Text(
              l10n.importConfirmMissingFiles(preview.missingFiles),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            l10n.importConfirmWarning,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.actionImport),
        ),
      ],
    );
  }
}
