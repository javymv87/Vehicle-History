import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../data/drive/sync_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../controllers/drive_controller.dart';
import 'drive_status_text.dart';

/// Whether the home screen shows the Drive banner: Drive holds a copy this
/// phone does not have (another phone uploaded it), alone or on top of local
/// changes. Two phones sharing one Drive copy must restore before editing.
bool driveShowsBanner(DriveViewState view) =>
    view.status?.state == SyncState.cloudChanged ||
    view.status?.state == SyncState.diverged;

/// A discreet banner at the top of the home screen for
/// [driveShowsBanner]: the status line and a way to the Backup page. Never a
/// dialog; it stays until the state changes (after a restore or an upload).
class DriveBanner extends ConsumerWidget {
  /// Creates the banner; it takes no space when not needed.
  const DriveBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(driveControllerProvider);
    if (!driveShowsBanner(view)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cloudChanged = view.status?.state == SyncState.cloudChanged;
    return Material(
      color: scheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                Icons.cloud_sync_outlined,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cloudChanged
                      ? '${driveStatusText(l10n, view)}. '
                          '${l10n.driveBannerRestoreFirst}'
                      : driveStatusText(l10n, view),
                  style: TextStyle(color: scheme.onTertiaryContainer),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: scheme.onTertiaryContainer,
                ),
                onPressed: () => context.push(AppRoutes.backup),
                child: Text(l10n.backupTitle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
