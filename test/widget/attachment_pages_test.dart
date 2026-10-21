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
    fakes.attachmentPicker.files[AttachmentSource.file] = [
      pickedFile('Polizza.pdf', [1, 2], mimeType: 'application/pdf'),
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

    await tester.tap(find.byIcon(Icons.more_vert));
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
