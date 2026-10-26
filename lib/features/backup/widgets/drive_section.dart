import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../data/drive/drive_config.dart';
import '../../../data/drive/drive_models.dart';
import '../../../data/drive/sync_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/feedback.dart';
import '../controllers/drive_controller.dart';
import 'drive_status_text.dart';
import 'import_confirmation_dialog.dart';

/// The Google Drive section of the Backup page (U20): the linked account,
/// the status line, the last upload or restore, Upload to Drive, Restore
/// from Drive, the mobile-data switch, Change account and Unlink. With no
/// account, only the explanation and Link account.
class DriveSection extends ConsumerWidget {
  /// Creates the section.
  const DriveSection({super.key, required this.otherTaskRunning});

  /// The manual export or import is running: every button is disabled.
  final bool otherTaskRunning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final view = ref.watch(driveControllerProvider);
    final account = ref.watch(driveAccountProvider).value;
    final lastSync = ref.watch(driveLastSyncProvider).value;
    final mobileData = ref.watch(driveMobileDataProvider).value ?? false;
    final busy = otherTaskRunning || view.task != null;
    final state = view.status?.state;
    const buttonSize = Size.fromHeight(48);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    if (account == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.driveSectionTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l10n.driveNotLinked),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: buttonSize),
            onPressed: busy ? null : () => _link(context, ref),
            icon: const Icon(Icons.add_to_drive),
            label: Text(l10n.driveLinkAction),
          ),
          if (view.task == DriveTask.linking) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(l10n.driveLinking, textAlign: TextAlign.center),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.driveSectionTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l10n.driveLinkedTo(account.email)),
        const SizedBox(height: 4),
        Text(
          switch (lastSync) {
            null => l10n.driveNeverSynced,
            (:final at, direction: SyncDirection.upload) =>
              l10n.driveLastUpload(at.toLocal(), at.toLocal()),
            (:final at, direction: SyncDirection.download) =>
              l10n.driveLastDownload(at.toLocal(), at.toLocal()),
          },
          style: secondary,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cloud_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                driveStatusText(l10n, view),
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(l10n.driveExplanation(driveKeptCopies), style: secondary),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: buttonSize),
          onPressed: busy || state == SyncState.cloudTooNew
              ? null
              : () => _upload(context, ref),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: Text(l10n.driveUploadAction),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: buttonSize),
          onPressed: busy ||
                  state == SyncState.cloudTooNew ||
                  state == SyncState.noCloudCopy
              ? null
              : () => _restore(context, ref),
          icon: const Icon(Icons.cloud_download_outlined),
          label: Text(l10n.driveRestoreAction),
        ),
        if (view.task case final task?
            when task != DriveTask.checking && task != DriveTask.linking) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: view.progress),
          const SizedBox(height: 8),
          Text(
            _progressText(l10n, task, view.progress),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.driveMobileDataLabel),
          subtitle: Text(l10n.driveMobileDataHint),
          value: mobileData,
          onChanged: busy
              ? null
              : (allowed) => ref
                  .read(driveControllerProvider.notifier)
                  .setMobileData(allowed: allowed),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed:
                  busy ? null : () => _changeAccount(context, ref, account),
              child: Text(l10n.driveChangeAccount),
            ),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: busy ? null : () => _unlink(context, ref, account),
              child: Text(l10n.driveUnlink),
            ),
          ],
        ),
      ],
    );
  }

  /// The words under the progress bar of [task].
  static String _progressText(
    AppLocalizations l10n,
    DriveTask task,
    double? progress,
  ) {
    final percent = ((progress ?? 0) * 100).round();
    return switch (task) {
      DriveTask.uploading => l10n.driveUploadingProgress(percent),
      DriveTask.downloading => l10n.driveDownloadingProgress(percent),
      DriveTask.restoring => l10n.driveRestoring,
      DriveTask.checking || DriveTask.linking => l10n.driveStatusChecking,
    };
  }

  /// Links an account; "Linked to …" once done, nothing on cancel.
  static Future<void> _link(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    switch (await ref.read(driveControllerProvider.notifier).link()) {
      case ActionSuccess(:final value?):
        showSavedSnackBar(messenger, l10n.driveLinked(value.email));
      case ActionSuccess():
        break;
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  /// Warns that the old backup stays in the old account, then links
  /// another one.
  static Future<void> _changeAccount(
    BuildContext context,
    WidgetRef ref,
    DriveAccount account,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmAction(
      context,
      title: l10n.driveChangeAccountTitle,
      message: l10n.driveChangeAccountMessage(account.email),
      confirmLabel: l10n.driveChangeAccount,
    );
    if (!confirmed || !context.mounted) return;
    await _link(context, ref);
  }

  /// Asks, then unlinks the account.
  static Future<void> _unlink(
    BuildContext context,
    WidgetRef ref,
    DriveAccount account,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmAction(
      context,
      title: l10n.driveUnlinkTitle,
      message: l10n.driveUnlinkMessage(account.email),
      confirmLabel: l10n.driveUnlink,
    );
    if (!confirmed) return;
    switch (await ref.read(driveControllerProvider.notifier).unlink()) {
      case ActionSuccess():
        showSavedSnackBar(messenger, l10n.driveUnlinked);
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  /// Uploads a new copy. When it would replace a Drive copy whose data this
  /// phone does not contain, the confirmation repeats the warning, with the
  /// dates of both sides.
  static Future<void> _upload(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(driveControllerProvider.notifier);
    final status = ref.read(driveControllerProvider).status;
    final mayLoseCloudData = switch (status?.state) {
      SyncState.cloudChanged ||
      SyncState.diverged ||
      SyncState.noCommonPoint =>
        true,
      _ => false,
    };
    if (mayLoseCloudData) {
      final confirmed = await confirmAction(
        context,
        title: l10n.driveUploadConfirmTitle,
        message: l10n.driveUploadConfirmMessage(
          driveDateText(l10n, status?.latest?.stampInstant),
          driveDateText(l10n, status?.local.stamp),
        ),
        confirmLabel: l10n.actionUpload,
        destructive: true,
      );
      if (!confirmed) return;
    }
    switch (await controller.upload(expected: status)) {
      case ActionSuccess():
        showSavedSnackBar(messenger, l10n.driveUploaded);
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  /// Downloads the latest copy, shows what it holds and what it replaces
  /// (with the warning when this phone has changes not in Drive), and
  /// restores it after the destructive confirmation through the import
  /// safety net.
  static Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    // Captured now: the restore closes the database and the whole router is
    // rebuilt on the new connection, so this context may be gone by then.
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final controller = ref.read(driveControllerProvider.notifier);
    final status = ref.read(driveControllerProvider).status;

    final PreparedRestore prepared;
    switch (await controller.prepareRestore()) {
      case ActionSuccess(:final value):
        prepared = value;
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
        return;
    }
    if (!context.mounted) {
      await controller.discardRestore();
      return;
    }
    final localStamp = status?.local.stamp;
    final localChanged = switch (status?.state) {
      SyncState.localChanged ||
      SyncState.diverged ||
      SyncState.noCommonPoint =>
        localStamp != null,
      _ => false,
    };
    final confirmed = await confirmImport(
      context,
      prepared.preview,
      title: l10n.driveRestoreConfirmTitle,
      confirmLabel: l10n.actionRestore,
      notes: [
        if (localStamp == null)
          l10n.driveRestoreReplacesEmpty
        else
          l10n.driveRestoreReplaces(driveDateText(l10n, localStamp)),
      ],
      warnings: [if (localChanged) l10n.driveRestoreLosesLocal],
    );
    if (!confirmed) {
      await controller.discardRestore();
      return;
    }
    switch (await controller.restore(prepared)) {
      case ActionSuccess():
        router.go(AppRoutes.vehicles);
        showSavedSnackBar(messenger, l10n.driveRestored);
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }
}
