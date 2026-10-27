import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/attachments/attachment_store.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/attachment.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/audit_log_repository.dart';
import 'package:vehicle_history/data/repositories/drift_attachment_repository.dart';
import 'package:vehicle_history/data/repositories/drift_log_entry_repository.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_mileage_reading_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';
import 'package:vehicle_history/data/repositories/repository_exceptions.dart';

import 'test_support.dart';

/// The attachments (schema v7): the repository rules, the files moved out
/// of the staging directory, the entry form saving its files with the entry
/// in one transaction, and the real file store.
void main() {
  late AppDatabase db;
  late FakeClock clock;
  late MemoryAttachmentStore store;
  late DriftOwnerRepository owners;
  late DriftVehicleRepository vehicles;
  late DriftLogEntryRepository entries;
  late DriftAttachmentRepository attachments;
  late DriftAuditLogRepository audit;
  late String ownerId;
  late String vehicleId;

  setUp(() async {
    db = openTestDatabase();
    clock = FakeClock(DateTime.utc(2026, 10, 19, 12));
    store = MemoryAttachmentStore();
    final writer = attachmentWriterOf(db, store);
    owners =
        DriftOwnerRepository(db.ownersDao, db.auditLogDao, clock: clock.call);
    vehicles = DriftVehicleRepository(
      db.vehiclesDao,
      db.mileageReadingsDao,
      db.trashDao,
      db.auditLogDao,
      readingRepository: DriftMileageReadingRepository(
        db.mileageReadingsDao,
        db.auditLogDao,
        clock: clock.call,
      ),
      attachmentFiles: store,
      clock: clock.call,
    );
    entries = DriftLogEntryRepository(
      db.logEntriesDao,
      db.auditLogDao,
      attachments: writer,
      clock: clock.call,
    );
    attachments =
        DriftAttachmentRepository(db.attachmentsDao, writer, clock: clock.call);
    audit = DriftAuditLogRepository(db.auditLogDao);
    ownerId = (await owners.create(firstName: 'Mario')).id;
    vehicleId = (await vehicles.create(
      plate: 'AB123CD',
      kind: VehicleKind.car,
      make: 'Fiat',
      model: 'Punto',
      ownerId: ownerId,
      currentOdometerKm: 1000,
      fuelType: FuelType.petrol,
    ))
        .id;
  });

  tearDown(() => db.close());

  /// Today, from the test clock.
  CalendarDate today() => CalendarDate.localDayOf(clock());

  /// Adds a note to the vehicle, with the staged [files].
  Future<String> addEntry({List<StagedFile> files = const []}) async =>
      (await entries.create(
        vehicleId: vehicleId,
        date: today(),
        type: LogEntryType.note,
        description: 'Tagliando',
        attachments: files,
      ))
          .id;

  /// The audit operations of the attachment [id], oldest first.
  Future<List<AuditOperation>> auditOf(String id) async => [
        for (final e
            in await audit.getForEntity(AuditEntityType.attachment, id))
          e.operation,
      ];

  group('kinds and names', () {
    test('the kind comes from the MIME type, or else from the extension', () {
      expect(
        AttachmentKind.of(mimeType: 'image/jpeg', fileName: 'x.bin'),
        AttachmentKind.image,
      );
      expect(
        AttachmentKind.of(mimeType: 'application/pdf', fileName: 'x'),
        AttachmentKind.pdf,
      );
      expect(AttachmentKind.of(fileName: 'Poliza.PDF'), AttachmentKind.pdf);
      expect(AttachmentKind.of(fileName: 'IMG_01.HEIC'), AttachmentKind.image);
      expect(AttachmentKind.of(fileName: 'notes.docx'), AttachmentKind.other);
      expect(AttachmentKind.of(fileName: 'no-extension'), AttachmentKind.other);
    });

    test('the stored name is the id with a plain, lower-case extension', () {
      expect(attachmentRelativePath('a1', 'Foto.JPG'), 'attachments/a1.jpg');
      expect(attachmentRelativePath('a1', 'archive'), 'attachments/a1.bin');
      expect(attachmentRelativePath('a1', 'x.tar gz'), 'attachments/a1.bin');
      expect(attachmentRelativePath('a1', '.hidden'), 'attachments/a1.bin');
      expect(
        attachmentRelativePath('a1', 'x.verylongext'),
        'attachments/a1.bin',
      );
    });
  });

  group('create', () {
    test(
        'moves the staged file into attachments/ and inserts its row, last '
        'in order, with a create audit row', () async {
      final first = await attachments.create(
        AttachmentTarget.vehicle(vehicleId),
        await store.stageBytes(
          [1, 2, 3],
          fileName: 'Libretto.pdf',
          mimeType: 'application/pdf',
        ),
      );
      final second = await attachments.create(
        AttachmentTarget.vehicle(vehicleId),
        await store.stageBytes([4, 5], fileName: 'Foto.jpg'),
      );

      expect(first.kind, AttachmentKind.pdf);
      expect(first.fileName, 'Libretto.pdf');
      expect(first.mimeType, 'application/pdf');
      expect(first.relativePath, 'attachments/${first.id}.pdf');
      expect(first.sizeBytes, 3);
      expect((first.sortOrder, second.sortOrder), (0, 1));
      expect(store.stored[first.relativePath], [1, 2, 3]);
      expect(store.staged, isEmpty);
      expect(
        await attachments.getByTarget(AttachmentTarget.vehicle(vehicleId)),
        [first, second],
      );
      expect(await auditOf(first.id), [AuditOperation.create]);
    });

    test('refuses a target that is missing or not live, writing nothing',
        () async {
      final entry = await addEntry();
      await entries.delete(entry);
      final otherOwner = (await owners.create(firstName: 'Ana')).id;
      await owners.delete(otherOwner);
      final targets = {
        const AttachmentTarget.vehicle('missing'): AuditEntityType.vehicle,
        AttachmentTarget.logEntry(entry): AuditEntityType.logEntry,
        AttachmentTarget.owner(otherOwner): AuditEntityType.owner,
      };
      for (final MapEntry(key: target, value: type) in targets.entries) {
        await expectLater(
          attachments.create(target, await store.stageBytes([1])),
          throwsA(
            isA<EntityNotFoundException>()
                .having((e) => e.entityType, 'entityType', type),
          ),
          reason: '$target',
        );
      }

      // The entries of a vehicle in the Trash are not live either.
      final live = await addEntry();
      await vehicles.delete(vehicleId);
      for (final target in [
        AttachmentTarget.vehicle(vehicleId),
        AttachmentTarget.logEntry(live),
      ]) {
        await expectLater(
          attachments.create(target, await store.stageBytes([1])),
          throwsA(isA<EntityNotFoundException>()),
        );
      }
      expect(store.stored, isEmpty);
      expect(
        (await db.customSelect('SELECT id FROM attachments').get()),
        isEmpty,
      );
    });

    test('refuses a file above 25 MB, before and while staging', () async {
      const tooLarge = StagedFile(
        path: '/memory/attachments_tmp/s/big.jpg',
        fileName: 'big.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: maxAttachmentBytes + 1,
      );
      await expectLater(
        attachments.create(AttachmentTarget.vehicle(vehicleId), tooLarge),
        throwsA(isA<AttachmentTooLargeException>()),
      );
      await expectLater(
        store.stageBytes(List.filled(maxAttachmentBytes + 1, 0)),
        throwsA(isA<AttachmentTooLargeException>()),
      );
      expect(store.staged, isEmpty);
      // Exactly 25 MB is accepted.
      final limit = await store.stageBytes(List.filled(maxAttachmentBytes, 0));
      final saved = await attachments.create(
        AttachmentTarget.vehicle(vehicleId),
        limit,
      );
      expect(saved.sizeBytes, maxAttachmentBytes);
    });

    test('a failed move leaves no row behind', () async {
      final staged = await store.stageBytes([1]);
      store.failMoveOf = staged.path;
      await expectLater(
        attachments.create(AttachmentTarget.vehicle(vehicleId), staged),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await attachments.getByTarget(AttachmentTarget.vehicle(vehicleId)),
        isEmpty,
      );
    });
  });

  group('caption, order, delete and restore', () {
    late Attachment photo;
    late Attachment pdf;

    setUp(() async {
      photo = await attachments.create(
        AttachmentTarget.owner(ownerId),
        await store.stageBytes([1], fileName: 'Patente.jpg'),
      );
      pdf = await attachments.create(
        AttachmentTarget.owner(ownerId),
        await store.stageBytes([2], fileName: 'DNI.pdf'),
      );
    });

    test('the caption is trimmed, blank clears it, and each change is audited',
        () async {
      clock.advance();
      final captioned = await attachments.updateCaption(photo.id, '  Fronte ');
      expect(captioned.caption, 'Fronte');
      expect(captioned.updatedAt, clock());
      expect(
        (await attachments.getByTarget(AttachmentTarget.owner(ownerId)))
            .first
            .caption,
        'Fronte',
      );
      final cleared = await attachments.updateCaption(photo.id, '   ');
      expect(cleared.caption, isNull);
      expect(await auditOf(photo.id), [
        AuditOperation.create,
        AuditOperation.update,
        AuditOperation.update,
      ]);
    });

    test('reorder needs every attachment once and audits only what moved',
        () async {
      await attachments.reorder(
        AttachmentTarget.owner(ownerId),
        [pdf.id, photo.id],
      );
      expect(
        [
          for (final a
              in await attachments.getByTarget(AttachmentTarget.owner(ownerId)))
            a.id,
        ],
        [pdf.id, photo.id],
      );
      expect(await auditOf(pdf.id), [
        AuditOperation.create,
        AuditOperation.update,
      ]);

      for (final wrong in [
        [pdf.id],
        [pdf.id, pdf.id],
        [pdf.id, 'other'],
      ]) {
        await expectLater(
          attachments.reorder(AttachmentTarget.owner(ownerId), wrong),
          throwsA(isA<InvalidFieldException>()),
        );
      }
    });

    test('delete hides the row and keeps the file; undo brings it back',
        () async {
      await attachments.delete(photo.id);
      expect(
        await attachments.getByTarget(AttachmentTarget.owner(ownerId)),
        [pdf],
      );
      expect(store.stored.containsKey(photo.relativePath), isTrue);
      await expectLater(
        attachments.delete(photo.id),
        throwsA(isA<EntityNotFoundException>()),
      );

      final restored = await attachments.restore(photo.id);
      expect(restored.id, photo.id);
      expect(
        await attachments.getByTarget(AttachmentTarget.owner(ownerId)),
        hasLength(2),
      );
      expect(await auditOf(photo.id), [
        AuditOperation.create,
        AuditOperation.delete,
        AuditOperation.restore,
      ]);
    });

    test(
        'a selection is deleted together, one audit row each, and one undo '
        'brings it all back', () async {
      await attachments.deleteMany([photo.id, pdf.id]);
      expect(
        await attachments.getByTarget(AttachmentTarget.owner(ownerId)),
        isEmpty,
      );
      expect(store.stored.containsKey(photo.relativePath), isTrue);
      expect(store.stored.containsKey(pdf.relativePath), isTrue);

      final restored = await attachments.restoreMany([photo.id, pdf.id]);
      expect([for (final a in restored) a.id], [photo.id, pdf.id]);
      expect(
        await attachments.getByTarget(AttachmentTarget.owner(ownerId)),
        hasLength(2),
      );
      for (final id in [photo.id, pdf.id]) {
        expect(await auditOf(id), [
          AuditOperation.create,
          AuditOperation.delete,
          AuditOperation.restore,
        ]);
      }
    });

    test('a selection with one attachment already deleted deletes nothing',
        () async {
      await attachments.delete(pdf.id);
      await expectLater(
        attachments.deleteMany([photo.id, pdf.id]),
        throwsA(isA<EntityNotFoundException>()),
      );
      // Rolled back: the photo is still live, with no delete audited.
      expect(
        await attachments.getByTarget(AttachmentTarget.owner(ownerId)),
        [photo],
      );
      expect(await auditOf(photo.id), [AuditOperation.create]);

      // Likewise, an undo that cannot bring everything back brings nothing.
      await expectLater(
        attachments.restoreMany([pdf.id, photo.id]),
        throwsA(isA<EntityNotFoundException>()),
      );
      expect(
        await attachments.getByTarget(AttachmentTarget.owner(ownerId)),
        [photo],
      );
    });

    test('undo is refused once the owner is gone', () async {
      await attachments.delete(photo.id);
      // An owner without vehicles can be deleted.
      final ana = (await owners.create(firstName: 'Ana')).id;
      final hers = await attachments.create(
        AttachmentTarget.owner(ana),
        await store.stageBytes([3]),
      );
      await attachments.delete(hers.id);
      await owners.delete(ana);
      await expectLater(
        attachments.restore(hers.id),
        throwsA(
          isA<EntityNotFoundException>()
              .having((e) => e.entityType, 'type', AuditEntityType.owner),
        ),
      );
    });

    test('the totals count every row, deleted ones included', () async {
      await attachments.delete(pdf.id);
      expect(
        await attachments.watchTotals().first,
        const AttachmentTotals(count: 2, bytes: 2),
      );
    });

    test('a missing file keeps its row', () async {
      await store.delete(photo.relativePath);
      expect(await attachments.fileExists(photo), isFalse);
      expect(await attachments.fileExists(pdf), isTrue);
      expect(
        await attachments.getByTarget(AttachmentTarget.owner(ownerId)),
        hasLength(2),
      );
      expect(
        attachments.filePathOf(pdf),
        '${MemoryAttachmentStore.root}/${pdf.relativePath}',
      );
    });
  });

  group('the entry form saves its files with the entry', () {
    test('a new entry with two files inserts both, in the picked order',
        () async {
      final a = await store.stageBytes([1], fileName: 'a.jpg');
      final b = await store.stageBytes([2], fileName: 'b.pdf');
      final entry = await addEntry(files: [a, b]);

      final saved =
          await attachments.getByTarget(AttachmentTarget.logEntry(entry));
      expect([for (final s in saved) s.fileName], ['a.jpg', 'b.pdf']);
      expect(store.staged, isEmpty);
      expect(store.stored, hasLength(2));
      expect(
        await attachments.watchEntryCounts(vehicleId).first,
        {entry: 2},
      );
    });

    test(
        'if anything fails, nothing is saved and the files already moved are '
        'removed', () async {
      final a = await store.stageBytes([1], fileName: 'a.jpg');
      final b = await store.stageBytes([2], fileName: 'b.jpg');
      store.failMoveOf = b.path;

      await expectLater(addEntry(files: [a, b]), throwsA(anything));

      expect(await entries.watchByVehicle(vehicleId).first, isEmpty);
      expect(
        (await db.customSelect('SELECT id FROM attachments').get()),
        isEmpty,
      );
      expect(store.stored, isEmpty, reason: 'the moved file was removed');
    });

    test('a file above the limit refuses the save before anything is written',
        () async {
      const tooLarge = StagedFile(
        path: '/memory/attachments_tmp/s/big.jpg',
        fileName: 'big.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: maxAttachmentBytes + 1,
      );
      await expectLater(
        addEntry(files: [tooLarge]),
        throwsA(isA<AttachmentTooLargeException>()),
      );
      expect(await entries.watchByVehicle(vehicleId).first, isEmpty);
    });

    test('editing adds new files and soft-deletes the removed ones', () async {
      final entry = await addEntry(
        files: [
          await store.stageBytes([1], fileName: 'old.jpg'),
        ],
      );
      final old =
          (await attachments.getByTarget(AttachmentTarget.logEntry(entry)))
              .single;

      await entries.update(
        entry,
        date: today(),
        type: LogEntryType.note,
        addedAttachments: [
          await store.stageBytes([2], fileName: 'Fattura.pdf'),
        ],
        removedAttachmentIds: {old.id},
      );

      final now =
          await attachments.getByTarget(AttachmentTarget.logEntry(entry));
      expect([for (final a in now) a.fileName], ['Fattura.pdf']);
      expect(now.single.sortOrder, 1, reason: 'after the deleted one');
      expect(await auditOf(old.id), [
        AuditOperation.create,
        AuditOperation.delete,
      ]);
      // The removed file stays until the 30-day cleanup.
      expect(store.stored.containsKey(old.relativePath), isTrue);
    });

    test('an edit cannot remove an attachment of another entity', () async {
      final entry = await addEntry();
      final foreign = await attachments.create(
        AttachmentTarget.vehicle(vehicleId),
        await store.stageBytes([1]),
      );
      await expectLater(
        entries.update(
          entry,
          date: today(),
          type: LogEntryType.note,
          removedAttachmentIds: {foreign.id},
        ),
        throwsA(isA<EntityNotFoundException>()),
      );
      expect(
        await attachments.getByTarget(AttachmentTarget.vehicle(vehicleId)),
        [foreign],
      );
    });

    test('the paperclip counts leave out deleted entries and attachments',
        () async {
      final kept = await addEntry(
        files: [
          await store.stageBytes([1]),
          await store.stageBytes([2]),
        ],
      );
      final gone = await addEntry(
        files: [
          await store.stageBytes([3]),
        ],
      );
      await entries.delete(gone);
      final hidden =
          (await attachments.getByTarget(AttachmentTarget.logEntry(kept)))
              .first;
      await attachments.delete(hidden.id);
      expect(
        await attachments.watchEntryCounts(vehicleId).first,
        {kept: 1},
      );
    });
  });

  group('IoAttachmentStore on real files', () {
    late Directory dir;
    late IoAttachmentStore files;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('vehicle_history_files_');
      files = IoAttachmentStore(dir.path);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('stages, moves into place, lists, sweeps and wipes', () async {
      final staged = await files.stage(
        'form-1',
        content: Stream.fromIterable([
          [1, 2],
          [3],
        ]),
        fileName: 'Foto.JPG',
        mimeType: 'image/jpeg',
      );
      expect(staged.sizeBytes, 3);
      expect(staged.path, contains('attachments_tmp'));
      expect(File(staged.path).readAsBytesSync(), [1, 2, 3]);

      await files.moveIntoPlace(staged.path, 'attachments/a1.jpg');
      expect(File(staged.path).existsSync(), isFalse);
      expect(await files.exists('attachments/a1.jpg'), isTrue);
      expect(
        File(files.absolutePath('attachments/a1.jpg')).readAsBytesSync(),
        [1, 2, 3],
      );

      File(files.absolutePath('attachments/orphan.pdf')).writeAsBytesSync([9]);
      expect(
        await files.listStored(),
        {'attachments/a1.jpg', 'attachments/orphan.pdf'},
      );
      expect(await deleteOrphanFiles(files, {'attachments/a1.jpg'}), 1);
      expect(await files.listStored(), {'attachments/a1.jpg'});

      await files.stage(
        'form-2',
        content: Stream.value([1]),
        fileName: 'x.pdf',
        mimeType: 'application/pdf',
      );
      await files.discardStaging('form-2');
      expect(
        Directory('${dir.path}/attachments_tmp/form-2').existsSync(),
        isFalse,
      );
      await files.wipeStaging();
      expect(Directory('${dir.path}/attachments_tmp').existsSync(), isFalse);
    });

    test('a file above the limit is refused while copying, leaving nothing',
        () async {
      final chunk = List.filled(1024 * 1024, 0);
      await expectLater(
        files.stage(
          'form',
          content: Stream.fromIterable(List.filled(26, chunk)),
          fileName: 'big.jpg',
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<AttachmentTooLargeException>()),
      );
      expect(
        Directory('${dir.path}/attachments_tmp/form').listSync(),
        isEmpty,
      );
    });
  });
}
