import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/backup/backup_exceptions.dart';
import 'package:vehicle_history/data/models/attachment.dart';
import 'package:vehicle_history/data/models/setting_key.dart';
import 'package:vehicle_history/data/platform/native_files.dart';

import '../support/fake_backup.dart';
import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

/// The Backup page (U20): last export, export with its cancel, the import
/// confirmation and the rejection messages.
void main() {
  late BackupFakes backup;

  setUp(() => backup = BackupFakes());

  /// Pumps the app on the Backup page.
  Future<void> pumpBackup(WidgetTester tester) async {
    await pumpApp(
      tester,
      FakeStore(),
      location: AppRoutes.backup,
      backup: backup,
    );
  }

  testWidgets('the menu of the vehicle list opens the Backup page',
      (tester) async {
    await pumpApp(tester, FakeStore(), backup: backup);
    await tester.tap(find.byType(PopupMenuButton<VoidCallback>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup'));
    await tester.pumpAndSettle();

    expect(find.text('Last export: never'), findsOneWidget);
  });

  testWidgets(
      'before any export it says never, with both buttons at least '
      '48 dp tall', (tester) async {
    await pumpBackup(tester);

    expect(find.text('Last export: never'), findsOneWidget);
    for (final label in ['Export', 'Import']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('export saves the package, says so and shows the date',
      (tester) async {
    await pumpBackup(tester);

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    expect(find.text('Backup exported'), findsOneWidget);
    expect(
      [for (final save in backup.nativeFiles.saves) save.suggestedName],
      ['vehicle-history-20261020-1830.zip'],
    );
    // Streamed from the temporary package, which is deleted afterwards.
    expect(backup.nativeFiles.saves.single.sourcePath, '/fake/package.zip.tmp');
    expect(backup.service.deletedExports, 1);
    expect(
      backup.settings.values[SettingKey.lastExportAt],
      '2026-10-20T16:30:00.000Z',
    );
    expect(find.text('Last export: never'), findsNothing);
    expect(find.textContaining('Last export: Oct'), findsOneWidget);
  });

  testWidgets('cancelling the save dialog is not an error and stores nothing',
      (tester) async {
    backup.nativeFiles.saveResult = SaveFileOutcome.cancelled;
    await pumpBackup(tester);

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(backup.settings.values[SettingKey.lastExportAt], isNull);
    expect(find.text('Last export: never'), findsOneWidget);
    expect(backup.service.deletedExports, 1);
  });

  testWidgets('a failed save says the backup was not exported', (tester) async {
    backup.nativeFiles.saveFailure = Exception('disk full');
    await pumpBackup(tester);

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    expect(
      find.text('The backup could not be exported. Your data has not changed.'),
      findsOneWidget,
    );
    expect(backup.settings.values[SettingKey.lastExportAt], isNull);
    expect(backup.service.deletedExports, 1);
  });

  testWidgets('the page shows how many attachments the package will carry',
      (tester) async {
    final store = FakeStore();
    const file = StagedFile(
      path: '/staged/a.jpg',
      fileName: 'a.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 2 * 1024 * 1024,
    );
    final owner = store.addOwner('Mario');
    store
      ..addAttachment(AttachmentTarget.owner(owner.id), file)
      ..addAttachment(AttachmentTarget.owner(owner.id), file);
    await pumpApp(
      tester,
      store,
      location: AppRoutes.backup,
      backup: backup,
    );

    expect(find.text('2 attachments, 4 MB'), findsOneWidget);
  });

  testWidgets(
      'import shows what the file contains, and replaces the data '
      'only after the confirmation', (tester) async {
    backup.picker.pickResult = true;
    await pumpBackup(tester);

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Import this backup?'), findsOneWidget);
    expect(
      find.text(
        'This file contains 2 vehicles, 41 entries and 7 readings; last '
        'modified Oct 18, 2026.',
      ),
      findsOneWidget,
    );
    expect(find.text('3 attachments (3.5 MB).'), findsOneWidget);
    expect(
      find.textContaining('1 file is missing from the package'),
      findsOneWidget,
    );
    final warning = tester.widget<Text>(
      find.text('Importing replaces all the current data.'),
    );
    expect(warning.style?.fontWeight, FontWeight.bold);

    // Cancel: nothing happens.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backup.service.imports, 0);
    expect(backup.service.deletedPicks, 1, reason: 'the copy is deleted');

    // Confirm: imported, back on the vehicle list, with the snackbar.
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Import'),
      ),
    );
    await tester.pumpAndSettle();

    expect(backup.service.imports, 1);
    expect(find.text('Backup imported'), findsOneWidget);
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.vehicles,
    );
  });

  testWidgets('cancelling the file picker does nothing', (tester) async {
    await pumpBackup(tester);

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a file that is not a backup is rejected with a clear message',
      (tester) async {
    backup.picker.pickResult = true;
    backup.service.rejectWith = notAPackage;
    await pumpBackup(tester);

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text(
        'This file is not a Vehicle History backup. Nothing was changed.',
      ),
      findsOneWidget,
    );
    expect(backup.service.imports, 0);
  });

  testWidgets('a backup from a newer app is rejected', (tester) async {
    backup.picker.pickResult = true;
    backup.service.rejectWith =
        const BackupRejectedException(BackupRejection.newerSchema);
    await pumpBackup(tester);

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('comes from a newer version of the app'),
      findsOneWidget,
    );
  });

  testWidgets('a failed import says the data has not changed', (tester) async {
    backup.picker.pickResult = true;
    backup.service.importFailure =
        BackupImportFailedException(Exception('migration failed'));
    await pumpBackup(tester);

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Import'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('The import failed; your data has not changed.'),
      findsOneWidget,
    );
  });
}
