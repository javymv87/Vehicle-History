import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/app_router.dart';
import '../../../app/router/app_routes.dart';
import '../../../l10n/app_localizations.dart';
import '../controllers/drive_controller.dart';
import 'drive_banner.dart';
import 'drive_status_text.dart';

/// Runs the startup step of the Drive copy once the database is ready:
/// the guard and, when allowed, the automatic upload in the background
/// ([DriveController.runAtStartup]). Shows [child] at once and never
/// blocks it.
///
/// A newer copy in Drive (alone or with local changes) shows the home
/// banner ([DriveBanner]). Any other result that needs the user (a copy
/// never compared, a copy from a newer app, the account to link again) is
/// said once by a discreet message with a shortcut to the Backup page.
/// Never a dialog.
class DriveStartup extends ConsumerStatefulWidget {
  /// Wraps [child], the router.
  const DriveStartup({super.key, required this.child});

  /// The app's pages.
  final Widget child;

  @override
  ConsumerState<DriveStartup> createState() => _DriveStartupState();
}

/// Starts the run after the first frame.
class _DriveStartupState extends ConsumerState<DriveStartup> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  /// The startup run, then the message if the status needs attention. The
  /// controller runs it only once per app process: rebuilt after an import,
  /// this widget does nothing.
  Future<void> _run() async {
    final controller = ref.read(driveControllerProvider.notifier);
    final before = ref.read(driveControllerProvider);
    final firstRun = before.status == null && before.failure == null;
    await controller.runAtStartup();
    if (!mounted || !firstRun) return;
    final view = ref.read(driveControllerProvider);
    // Drive has a newer copy: the home banner says so, and stays.
    if (!driveNeedsAttention(view) || driveShowsBanner(view)) return;
    final l10n = AppLocalizations.of(context);
    final router = ref.read(routerProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(driveStatusText(l10n, view)),
          duration: const Duration(seconds: 8),
          persist: false,
          action: SnackBarAction(
            label: l10n.backupTitle,
            onPressed: () => router.push(AppRoutes.backup),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
