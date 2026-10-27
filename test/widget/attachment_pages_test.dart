import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/attachments/attachment_picker.dart';
import 'package:vehicle_history/data/models/attachment.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/features/attachments/widgets/attachment_thumbnail.dart';
import 'package:vehicle_history/features/vehicles/controllers/vehicle_tab_controller.dart';

import '../support/fake_backup.dart';
import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

/// The attachments on screen (U22–U26): the entry form stages and
/// discards, the detail lists, the paperclip, the Documents tab, the owner
/// documents and the viewer caption.
void main() {
  late FakeStore store;
  late BackupFakes fakes;
  late String ownerId;
  late String vehicleId;

  setUp(() {
    store = FakeStore();
    fakes = BackupFakes();
    ownerId = store.addOwner('Mario').id;
    vehicleId = store
        .addVehicle(
          'AB123CD',
          ownerId: ownerId,
          km: 12345,
          make: 'Fiat',
          model: 'Punto',
        )
        .id;
  });

  /// A file as staged, for attachments added straight into the store.
  StagedFile staged(String name, {int size = 1024}) => StagedFile(
        path: '/staged/$name',
        fileName: name,
        mimeType: mimeTypeForFileName(name),
        sizeBytes: size,
      );

  /// Scrolls [finder] into view and taps it.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Picks [name] from the gallery through the add tile of the entry form.
  Future<void> pickIntoForm(WidgetTester tester, String name) async {
    fakes.attachmentPicker.files[AttachmentSource.gallery] = [
      pickedFile(name, [1, 2, 3]),
    ];
    await tapVisible(
      tester,
      find.byKey(const ValueKey('entry-add-attachment')),
    );
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
  }

  group('entry form (U22)', () {
    testWidgets('stages a picked photo, and discards it on cancel',
        (tester) async {
      await pumpApp(
        tester,
        store,
        location: AppRoutes.vehicle(vehicleId),
        backup: fakes,
      );
      await tester.tap(find.text('New entry'));
      await tester.pumpAndSettle();

      await pickIntoForm(tester, 'tagliando.jpg');
      expect(find.text('tagliando.jpg'), findsOneWidget);
      expect(fakes.attachmentStore.staged, hasLength(1));

      // Removed from the form before saving: gone from the form.
      await tapVisible(tester, find.byTooltip('Remove attachment'));
      expect(find.text('tagliando.jpg'), findsNothing);

      await pickIntoForm(tester, 'second.jpg');
      await tester.pageBack();
      await tester.pumpAndSettle();

      // The form is gone: its staging session is discarded.
      expect(fakes.attachmentStore.staged, isEmpty);
      expect(store.attachments, isEmpty);
    });

    testWidgets('saving the entry saves the staged files with it',
        (tester) async {
      await pumpApp(
        tester,
        store,
        location: AppRoutes.newEntry(vehicleId),
        backup: fakes,
      );
      await tester.tap(find.text('Note'));
      await tester.pumpAndSettle();
      await pickIntoForm(tester, 'fattura.pdf');

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      final attachment = store.attachments.values.single;
      expect(attachment.fileName, 'fattura.pdf');
      expect(attachment.kind, AttachmentKind.pdf);
      expect(attachment.target.entityType, AttachmentEntityType.logEntry);
      expect(store.entries.keys, [attachment.target.entityId]);
    });
  });

  testWidgets(
      'the entry detail shows images as thumbnails and documents as rows '
      '(U23), and the history row shows the paperclip (U24)', (tester) async {
    final entry = store.addEntry(
      vehicleId,
      date: const CalendarDate(2024, 3, 1),
      description: 'Tagliando',
    );
    store
      ..addAttachment(AttachmentTarget.logEntry(entry.id), staged('a.jpg'))
      ..addAttachment(
        AttachmentTarget.logEntry(entry.id),
        staged('Fattura.pdf', size: 2048),
      );

    await pumpApp(
      tester,
      store,
      location: AppRoutes.vehicle(vehicleId),
      backup: fakes,
    );
    expect(find.byIcon(Icons.attach_file), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '2 attachments',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Tagliando'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Fattura.pdf'), 100);
    expect(find.text('Attachments'), findsOneWidget);
    expect(find.text('Fattura.pdf'), findsOneWidget);
    expect(find.textContaining('2 KB'), findsOneWidget);
    // One thumbnail for the image, the PDF as a row.
    expect(find.byType(AttachmentThumbnail), findsOneWidget);

    // Opening the document goes to the phone's app.
    await tester.tap(find.text('Fattura.pdf'));
    await tester.pumpAndSettle();
    expect(fakes.fileOpener.opened, hasLength(1));
  });

  testWidgets(
      'the Documents tab (U25) adds a document with its button and deletes '
      'it with Undo', (tester) async {
    var sourceDeleted = false;
    fakes.attachmentPicker.files[AttachmentSource.file] = [
      pickedFile(
        'Polizza.pdf',
        [1, 2],
        mimeType: 'application/pdf',
        onDeleteSource: () => sourceDeleted = true,
      ),
    ];
    await pumpApp(
      tester,
      store,
      location: AppRoutes.vehicle(vehicleId, tab: VehicleTab.documents),
      backup: fakes,
    );
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('No documents yet.'), findsOneWidget);

    await tester.tap(find.text('Add document'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(find.text('Polizza.pdf'), findsOneWidget);
    expect(find.text('Attachment added'), findsOneWidget);
    expect(
      store.attachments.values.single.target,
      AttachmentTarget.vehicle(vehicleId),
    );
    // The picker's own copy in the cache is gone once ours is saved.
    expect(sourceDeleted, isTrue);

    // The file's own menu, not the page's overflow menu.
    await tester.tap(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete this attachment?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Polizza.pdf'), findsNothing);
    expect(find.text('Attachment deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Polizza.pdf'), findsOneWidget);
  });

  group('selection mode (U29)', () {
    /// Two documents of the owner, shown on the owner detail.
    Future<void> pumpOwnerWithTwo(WidgetTester tester) async {
      store
        ..addAttachment(AttachmentTarget.owner(ownerId), staged('Patente.pdf'))
        ..addAttachment(AttachmentTarget.owner(ownerId), staged('DNI.pdf'));
      await pumpApp(
        tester,
        store,
        location: AppRoutes.owner(ownerId),
        backup: fakes,
      );
      await tester.scrollUntilVisible(find.text('DNI.pdf'), 100);
    }

    testWidgets(
        'a long press starts it; select all, share and Back end it as '
        'expected', (tester) async {
      await pumpOwnerWithTwo(tester);
      await tester.longPress(find.text('Patente.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      // The menu gives way to a check box.
      expect(find.byIcon(Icons.more_vert), findsNothing);

      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      // A tap now unselects instead of opening.
      await tester.tap(find.text('DNI.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(fakes.fileOpener.opened, isEmpty);

      // Back ends the mode and stays on the page.
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(find.text('1 selected'), findsNothing);
      expect(find.text('Patente.pdf'), findsOneWidget);

      await tester.longPress(find.text('Patente.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      expect(
        [for (final file in fakes.nativeFiles.shares.single) file.name],
        ['Patente.pdf', 'DNI.pdf'],
      );
      expect(find.text('2 selected'), findsNothing);
    });

    testWidgets('several are saved to a folder with their names',
        (tester) async {
      await pumpOwnerWithTwo(tester);
      await tester.longPress(find.text('Patente.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DNI.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save to…'));
      await tester.pumpAndSettle();

      expect(
        [for (final file in fakes.nativeFiles.folderSaves.single) file.name],
        ['Patente.pdf', 'DNI.pdf'],
      );
      expect(fakes.nativeFiles.saves, isEmpty);
      expect(find.text('2 files saved'), findsOneWidget);
    });

    testWidgets('several are deleted together and one Undo brings them back',
        (tester) async {
      await pumpOwnerWithTwo(tester);
      await tester.longPress(find.text('Patente.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 attachments?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.liveAttachments, isEmpty);
      expect(find.text('2 attachments deleted'), findsOneWidget);
      expect(find.text('2 selected'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.liveAttachments, hasLength(2));
    });

    testWidgets(
        'on the Documents tab the add button hides while selecting, and '
        'leaving the tab ends the mode', (tester) async {
      store.addAttachment(
        AttachmentTarget.vehicle(vehicleId),
        staged('Polizza.pdf'),
      );
      await pumpApp(
        tester,
        store,
        location: AppRoutes.vehicle(vehicleId, tab: VehicleTab.documents),
        backup: fakes,
      );
      await tester.longPress(find.text('Polizza.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Add document'), findsNothing);

      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsNothing);
    });
  });

  testWidgets('the owner detail has its documents section (U26)',
      (tester) async {
    store.addAttachment(
      AttachmentTarget.owner(ownerId),
      staged('Patente.pdf'),
    );
    await pumpApp(
      tester,
      store,
      location: AppRoutes.owner(ownerId),
      backup: fakes,
    );
    await tester.scrollUntilVisible(find.text('Patente.pdf'), 100);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Add document'), findsOneWidget);
  });

  testWidgets('the viewer shows the position and edits the caption',
      (tester) async {
    final first = store.addAttachment(
      AttachmentTarget.vehicle(vehicleId),
      staged('a.jpg'),
    );
    store.addAttachment(AttachmentTarget.vehicle(vehicleId), staged('b.jpg'));
    await pumpApp(
      tester,
      store,
      location: AppRoutes.attachment(first.id),
      backup: fakes,
    );
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Add a caption'), findsOneWidget);

    await tester.tap(find.text('Add a caption'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Libretto, fronte');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Libretto, fronte'), findsOneWidget);
    expect(store.attachments[first.id]!.caption, 'Libretto, fronte');

    // Swiping shows the second image.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);
  });

  testWidgets('a denied camera says so', (tester) async {
    fakes.attachmentPicker.failure =
        const AttachmentPickException(AttachmentPickFailure.cameraDenied);
    await pumpApp(
      tester,
      store,
      location: AppRoutes.vehicle(vehicleId, tab: VehicleTab.documents),
      backup: fakes,
    );
    await tester.tap(find.text('Add document'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Camera access was denied'), findsOneWidget);
  });
}
