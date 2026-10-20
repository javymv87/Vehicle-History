import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/feedback.dart';
import '../controllers/backup_controller.dart';
import '../widgets/import_confirmation_dialog.dart';

/// The Backup page (U20): when the last export happened, what the package
/// contains, and the Export and Import buttons, with a progress indicator
/// while one of them works. Opened from the overflow menu of the home lists.
class BackupPage extends ConsumerWidget {
  /// Creates the Backup page.
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final task = ref.watch(backupControllerProvider);
    final lastExportAt = ref.watch(lastExportAtProvider).value;
    final busy = task != null;
    // Full-width buttons, at least 48 dp tall (U20).
    const buttonSize = Size.fromHeight(48);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            lastExportAt == null
                ? l10n.backupNeverExported
                : l10n.backupLastExport(
                    lastExportAt.toLocal(),
                    lastExportAt.toLocal(),
                  ),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Text(l10n.backupExplanation),
          const SizedBox(height: 8),
          Text(l10n.backupImportExplanation),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: buttonSize),
            onPressed: busy ? null : () => _export(context, ref),
            icon: const Icon(Icons.save_alt),
            label: Text(l10n.actionExport),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: buttonSize),
            onPressed: busy ? null : () => _import(context, ref),
            icon: const Icon(Icons.restore),
            label: Text(l10n.actionImport),
          ),
          if (task != null) ...[
            const SizedBox(height: 24),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              switch (task) {
                BackupTask.exporting => l10n.backupExporting,
                BackupTask.importing => l10n.backupImporting,
              },
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  /// Exports the package; "Backup exported" once saved, nothing on cancel.
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    switch (await ref.read(backupControllerProvider.notifier).export()) {
      case ActionSuccess(value: true):
        showSavedSnackBar(messenger, l10n.backupExported);
      case ActionSuccess():
        break;
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  /// Picks a package, shows what it contains, and imports it after the
  /// destructive confirmation. On success the app opens on the vehicle
  /// list with "Backup imported".
  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    // Captured now: the import closes the database, and the whole router is
    // rebuilt on the new connection while it finishes, so this page and its
    // context may be gone by then.
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final controller = ref.read(backupControllerProvider.notifier);

    final picked = await controller.pickPackage();
    final PickedPackage package;
    switch (picked) {
      case ActionSuccess(:final value?):
        package = value;
      case ActionSuccess():
        return;
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
        return;
    }
    if (!context.mounted) return;
    if (!await confirmImport(context, package.manifest)) return;

    switch (await controller.importPackage(package.bytes)) {
      case ActionSuccess():
        router.go(AppRoutes.vehicles);
        showSavedSnackBar(messenger, l10n.backupImported);
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }
}
