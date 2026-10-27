import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/drive/drive_auth_service.dart';
import 'package:vehicle_history/data/drive/drive_models.dart';
import 'package:vehicle_history/data/drive/drive_settings.dart';
import 'package:vehicle_history/data/platform/network_state.dart';

import '../support/fake_backup.dart';
import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

/// The Google Drive section of the Backup page and the startup run: status
/// line, link, upload and restore confirmations, no dialogs at start.
void main() {
  const me = DriveAccount('me@example.com');
  late BackupFakes backup;

  setUp(() {
    backup = BackupFakes();
    backup.service.local = sampleLocal;
  });

  Future<void> pumpBackup(WidgetTester tester) => pumpApp(
        tester,
        FakeStore(),
        location: AppRoutes.backup,
        backup: backup,
      );

  /// Scrolls the Backup page until [text] is visible.
  Future<void> showText(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Links [me] and uploads a first copy, as a previous session would have.
  Future<void> linkedAndUploaded() async {
    await backup.settings.writeDriveAccount(me);
    await backup.driveService.upload(expectedUploadId: null);
  }

  testWidgets('without an account: the explanation and both ways to link',
      (tester) async {
    await pumpBackup(tester);
    await showText(tester, 'Link a phone account');

    expect(find.textContaining('No account linked.'), findsOneWidget);
    expect(find.text('Upload to Drive'), findsNothing);
    expect(backup.driveClient.listings, 0);
    await showText(tester, 'Link an account manually');
    expect(find.textContaining('Sign in in the browser'), findsOneWidget);
  });

  testWidgets(
      'linking manually shows the mode and the browser-session notice once',
      (tester) async {
    await pumpBackup(tester);
    await showText(tester, 'Link an account manually');

    await tester.tap(find.text('Link an account manually'));
    await tester.pumpAndSettle();

    expect(find.text('Browser session'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Browser session'), findsNothing);

    await showText(tester, 'Linked manually (only in this app)');
    expect(find.text('Link a phone account'), findsNothing);
    expect(
      await backup.settings.readDriveAccount(),
      const DriveAccount('me@example.com', mode: DriveAuthMode.manual),
    );
  });

  testWidgets(
      'unlinking a manual account revokes it, and says so when Google '
      'could not be told', (tester) async {
    await backup.settings.writeDriveAccount(
      const DriveAccount('me@example.com', mode: DriveAuthMode.manual),
    );
    backup.driveManualAuth.unlinkFailure =
        const DriveRevocationFailedException('offline');
    await pumpBackup(tester);
    await showText(tester, 'Unlink');

    await tester.tap(find.text('Unlink'));
    await tester.pumpAndSettle();
    expect(find.textContaining("withdraws this app's access"), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Unlink').last);
    await tester.pumpAndSettle();

    expect(backup.driveManualAuth.unlinks, 1);
    expect(backup.driveAuth.unlinks, 0);
    expect(find.textContaining('Google could not be told'), findsOneWidget);
    expect(await backup.settings.readDriveAccount(), isNull);
  });

  testWidgets(
      'linking an account with no copy in Drive uploads the first one at '
      'once', (tester) async {
    await pumpBackup(tester);
    await showText(tester, 'Link a phone account');

    await tester.tap(find.text('Link a phone account'));
    await tester.pumpAndSettle();

    expect(find.text('Linked to me@example.com'), findsOneWidget);
    expect(backup.driveClient.uploads, hasLength(1));
    await showText(tester, 'Copy linked to: me@example.com');
    expect(find.text('Drive: up to date'), findsOneWidget);
    expect(find.textContaining('Last upload:'), findsOneWidget);
  });

  testWidgets(
      'linked and aligned: status up to date, buttons at least 48 dp, '
      'nothing uploaded at start', (tester) async {
    await linkedAndUploaded();
    await pumpBackup(tester);
    await showText(tester, 'Restore from Drive');

    expect(find.text('Drive: up to date'), findsOneWidget);
    expect(backup.driveClient.uploads, hasLength(1));
    for (final label in ['Upload to Drive', 'Restore from Drive']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('only local changed: uploaded at start, no dialog',
      (tester) async {
    await linkedAndUploaded();
    backup.service.local = LocalSyncState(
      stamp: DateTime.utc(2026, 10, 22),
      counts: sampleLocal.counts,
    );
    await pumpApp(tester, FakeStore(), backup: backup);

    expect(find.byType(AlertDialog), findsNothing);
    expect(backup.driveClient.uploads, hasLength(2));
  });

  testWidgets(
      'a copy never compared: no dialog, no upload, a discreet message '
      'with the way to the Backup page', (tester) async {
    await backup.settings.writeDriveAccount(me);
    backup.driveClient.put(me.email, uploadId: 'theirs', stamp: 'none');
    await pumpApp(tester, FakeStore(), backup: backup);

    expect(find.byType(AlertDialog), findsNothing);
    expect(backup.driveClient.uploads, isEmpty);
    expect(find.textContaining('copy not compared'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Backup'));
    await tester.pumpAndSettle();
    await showText(tester, 'Upload to Drive');
    expect(find.textContaining('copy not compared'), findsWidgets);
  });

  testWidgets(
      'a newer copy in Drive shows a banner on the home screen, no dialog, '
      'and it leads to the Backup page', (tester) async {
    await linkedAndUploaded();
    backup.driveClient.put(me.email, uploadId: 'theirs', stamp: 'none');
    await pumpApp(tester, FakeStore(), backup: backup);

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text(
        'Drive: newer copy in Drive (from another phone). '
        'Restore before editing.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Backup'));
    await tester.pumpAndSettle();
    await showText(tester, 'Restore from Drive');
    expect(find.text('Restore from Drive'), findsOneWidget);
  });

  testWidgets('both changed: the home banner says so, nothing uploaded',
      (tester) async {
    await linkedAndUploaded();
    backup.service.local = LocalSyncState(
      stamp: DateTime.utc(2026, 10, 22),
      counts: sampleLocal.counts,
    );
    backup.driveClient.put(me.email, uploadId: 'theirs', stamp: 'none');
    await pumpApp(tester, FakeStore(), backup: backup);

    expect(
      find.text('Drive: both this phone and Drive have changed'),
      findsOneWidget,
    );
    expect(backup.driveClient.uploads, hasLength(1));
  });

  testWidgets(
      'uploading over a newer copy asks first, with both dates; cancel '
      'uploads nothing', (tester) async {
    await linkedAndUploaded();
    backup.driveClient.put(
      me.email,
      uploadId: 'theirs',
      stamp: stampCode(DateTime.utc(2026, 10, 21, 12)),
    );
    await pumpBackup(tester);
    await showText(tester, 'Upload to Drive');
    expect(
      find.text('Drive: newer copy in Drive (from another phone)'),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing, reason: 'banner instead');

    await tester.tap(find.text('Upload to Drive'));
    await tester.pumpAndSettle();
    expect(find.text('Replace the copy in Drive?'), findsOneWidget);
    expect(find.textContaining('Oct 21, 2026'), findsOneWidget);
    expect(find.textContaining('Oct 18, 2026'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backup.driveClient.uploads, hasLength(1));
  });

  testWidgets(
      'restore shows what the copy holds and what it replaces, then '
      'imports it', (tester) async {
    await linkedAndUploaded();
    await pumpBackup(tester);
    await showText(tester, 'Restore from Drive');

    await tester.tap(find.text('Restore from Drive'));
    await tester.pumpAndSettle();
    expect(find.text('Restore from Drive?'), findsOneWidget);
    expect(
      find.textContaining('will be replaced by the copy in Drive'),
      findsOneWidget,
    );
    expect(
      find.text('Importing replaces all the current data.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();
    expect(backup.service.imports, 1);
    expect(find.text('Copy restored from Drive'), findsOneWidget);
    expect(
      (await backup.settings.readSyncPoint())?.direction,
      SyncDirection.download,
    );
  });

  testWidgets(
      'restoring onto an empty phone says it has no data, with no loss '
      'warning', (tester) async {
    await backup.settings.writeDriveAccount(me);
    backup.driveClient.put(me.email, uploadId: 'theirs', stamp: 'none');
    backup.service.local = emptyLocal;
    await pumpBackup(tester);
    await showText(tester, 'Restore from Drive');

    await tester.tap(find.text('Restore from Drive'));
    await tester.pumpAndSettle();
    expect(find.text('This phone has no data yet.'), findsOneWidget);
    expect(find.textContaining('they will be lost'), findsNothing);
  });

  testWidgets('restore with changes not in Drive warns they will be lost',
      (tester) async {
    await linkedAndUploaded();
    backup.service.local = LocalSyncState(
      stamp: DateTime.utc(2026, 10, 22),
      counts: sampleLocal.counts,
    );
    // Offline at start: the change stays local.
    backup.network.kind = NetworkKind.none;
    await pumpBackup(tester);
    await showText(tester, 'Restore from Drive');

    await tester.tap(find.text('Restore from Drive'));
    await tester.pumpAndSettle();
    expect(find.textContaining('they will be lost'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backup.service.imports, 0);
  });

  testWidgets('changing account warns that the old backup stays',
      (tester) async {
    await linkedAndUploaded();
    await pumpBackup(tester);
    await showText(tester, 'Change account');

    await tester.tap(find.text('Change account'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('the previous backup stays in the old account'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await backup.settings.readDriveAccount(), me);
  });

  testWidgets('unlinking forgets the account and the common point',
      (tester) async {
    await linkedAndUploaded();
    await pumpBackup(tester);
    await showText(tester, 'Unlink');

    await tester.tap(find.text('Unlink'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Unlink').last);
    await tester.pumpAndSettle();

    expect(find.text('Account unlinked'), findsOneWidget);
    expect(await backup.settings.readDriveAccount(), isNull);
    expect(await backup.settings.readSyncPoint(), isNull);
  });

  testWidgets(
      'a manual import with a linked account says the automatic copy '
      'pauses', (tester) async {
    await linkedAndUploaded();
    backup.picker.pickResult = true;
    await pumpBackup(tester);

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('The automatic Drive copy will pause'),
      findsOneWidget,
    );
  });
}
