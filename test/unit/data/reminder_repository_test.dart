import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/archive_reason.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/reminder.dart';
import 'package:vehicle_history/data/models/reminder_kind.dart';
import 'package:vehicle_history/data/models/reminder_status.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/audit_log_repository.dart';
import 'package:vehicle_history/data/repositories/drift_log_entry_repository.dart';
import 'package:vehicle_history/data/repositories/drift_mileage_reading_repository.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_reminder_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';
import 'package:vehicle_history/data/repositories/reminder_closer.dart';
import 'package:vehicle_history/data/repositories/repository_exceptions.dart';
import 'package:vehicle_history/data/repositories/trash_cleanup_service.dart';

import 'test_support.dart';

/// The anchor day of the recurring reminders below.
const CalendarDate anchorDay = CalendarDate(2026, 3, 1);

/// An engine-oil draft: every 15 000 km or 12 months, done on [anchorDay] at
/// 80 000 km.
ReminderDraft oilDraft({
  ReminderKind kind = ReminderKind.engineOil,
  String title = 'Olio motore',
  double? km = 15000,
  int? months = 12,
  CalendarDate? lastDone = anchorDay,
  double? lastDoneKm = 80000,
  CalendarDate? due,
  int? leadDays,
  double? leadKm,
}) =>
    ReminderDraft(
      kind: kind,
      title: title,
      refIntervalKm: km,
      refIntervalMonths: months,
      lastDoneDate: lastDone,
      lastDoneKm: lastDoneKm,
      dueDate: due,
      leadDays: leadDays,
      leadKm: leadKm,
    );

/// A one-shot draft of [kind] due on [due].
ReminderDraft oneShotDraft(
  CalendarDate due, {
  ReminderKind kind = ReminderKind.roadTax,
}) =>
    ReminderDraft(kind: kind, title: 'Bollo', dueDate: due);

/// Matches a [ReminderRuleException] for [rule].
Matcher throwsRule(ReminderRule rule) => throwsA(
      isA<ReminderRuleException>().having((e) => e.rule, 'rule', rule),
    );

/// Matches an [InvalidFieldException] on [field], with [reason] when given.
Matcher throwsInvalid(String field, [String? reason]) => throwsA(
      isA<InvalidFieldException>()
          .having((e) => e.field, 'field', field)
          .having((e) => e.reason, 'reason', reason ?? anything),
    );

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late DriftVehicleRepository vehicles;
  late DriftLogEntryRepository entries;
  late DriftReminderRepository reminders;
  late DriftAuditLogRepository audit;
  late Vehicle punto;
  late Vehicle panda;

  setUp(() async {
    db = openTestDatabase();
    // Noon UTC, the same local day in any timezone.
    clock = FakeClock(DateTime.utc(2026, 11, 2, 12));
    final owners =
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
      attachmentFiles: MemoryAttachmentStore(),
      clock: clock.call,
    );
    final closer = ReminderCloser(db.remindersDao, db.auditLogDao);
    entries = DriftLogEntryRepository(
      db.logEntriesDao,
      db.auditLogDao,
      attachments: attachmentWriterOf(db),
      reminders: closer,
      clock: clock.call,
    );
    reminders = DriftReminderRepository(
      db.remindersDao,
      db.auditLogDao,
      entries: entries,
      closer: closer,
      clock: clock.call,
    );
    audit = DriftAuditLogRepository(db.auditLogDao);
    final mario = await owners.create(firstName: 'Mario');
    punto = await vehicles.create(
      plate: 'AB123CD',
      kind: VehicleKind.car,
      ownerId: mario.id,
      currentOdometerKm: 85000,
      fuelType: FuelType.petrolLpg,
    );
    panda = await vehicles.create(
      plate: 'EF456GH',
      kind: VehicleKind.car,
      ownerId: mario.id,
      currentOdometerKm: 1000,
      fuelType: FuelType.diesel,
    );
  });

  tearDown(() => db.close());

  /// Creates a reminder from [draft] on [vehicle] (the Punto by default),
  /// advancing the clock first.
  Future<Reminder> add([ReminderDraft? draft, Vehicle? vehicle]) {
    clock.advance();
    return reminders.create(
      vehicleId: (vehicle ?? punto).id,
      draft: draft ?? oilDraft(),
    );
  }

  /// Adds an entry of [type] on [date] with [km] to [vehicle] (the Punto by
  /// default).
  Future<LogEntry> entry(
    LogEntryType type, {
    CalendarDate date = const CalendarDate(2026, 10, 30),
    double? km = 90000,
    Vehicle? vehicle,
  }) {
    clock.advance();
    return entries.create(
      vehicleId: (vehicle ?? punto).id,
      date: date,
      km: km,
      type: type,
    );
  }

  /// The history of [id], oldest first.
  Future<List<ReminderChange>> changesOf(String id) async =>
      (await reminders.watchChanges(id).first).reversed.toList();

  /// The audit operations recorded for the reminder [id], oldest first.
  Future<List<AuditOperation>> auditOf(String id) async => [
        for (final row
            in await audit.getForEntity(AuditEntityType.reminder, id))
          row.operation,
      ];

  group('create', () {
    test('stores a recurring reminder with its create change and audit row',
        () async {
      final created = await add(
        oilDraft(title: '  Olio  ', leadDays: 10, leadKm: 500),
      );
      final read = await reminders.getById(created.id);
      expect(read, created);
      expect(read!.title, 'Olio');
      expect(read.source, ReminderSource.manual);
      expect(read.refIntervalKm, 15000);
      expect(read.lastDoneKm, 80000);
      expect(read.leadDays, 10);
      final changes = await changesOf(created.id);
      expect(changes, hasLength(1));
      expect(changes.single.type, ReminderChangeType.create);
      expect(changes.single.refIntervalMonths, 12);
      expect(changes.single.lastDoneDate, anchorDay);
      expect(await auditOf(created.id), [AuditOperation.create]);
    });

    test('a one-shot reminder may fall due in the future', () async {
      final created = await add(oneShotDraft(const CalendarDate(2027, 1, 31)));
      expect(created.isOneShot, isTrue);
      expect(created.lastDoneDate, isNull);
      expect((await changesOf(created.id)).single.dueDate, created.dueDate);
    });

    test('refuses every shape the table forbids, before SQLite does', () async {
      await expectLater(add(oilDraft(title: '  ')), throwsInvalid('title'));
      await expectLater(
        add(oilDraft(km: null, months: null)),
        throwsInvalid('refIntervalKm'),
      );
      await expectLater(
        add(oilDraft(due: const CalendarDate(2027, 1, 1))),
        throwsInvalid('dueDate'),
      );
      await expectLater(
        add(oilDraft(lastDone: null)),
        throwsInvalid('lastDoneDate', InvalidFieldException.required),
      );
      await expectLater(
        add(oilDraft(lastDoneKm: null)),
        throwsInvalid('lastDoneKm', InvalidFieldException.required),
      );
      await expectLater(
        add(oilDraft(lastDone: const CalendarDate(2026, 11, 3))),
        throwsInvalid('lastDoneDate', InvalidFieldException.inFuture),
      );
      await expectLater(add(oilDraft(km: 0)), throwsInvalid('refIntervalKm'));
      await expectLater(
        add(oilDraft(months: -1)),
        throwsInvalid('refIntervalMonths'),
      );
      await expectLater(add(oilDraft(leadDays: -1)), throwsInvalid('leadDays'));
      await expectLater(
        add(oilDraft(lastDoneKm: -5)),
        throwsInvalid('lastDoneKm'),
      );
      expect(await reminders.watchByVehicle(punto.id).first, isEmpty);
    });

    test('a months-only reminder needs no km anchor', () async {
      final created = await add(oilDraft(km: null, lastDoneKm: null));
      expect(created.usesKm, isFalse);
    });

    test('one open reminder per unique kind and vehicle', () async {
      await add();
      await expectLater(
        add(oilDraft(title: 'Altro olio')),
        throwsA(isA<ReminderKindAlreadyUsedException>()),
      );
      // Another vehicle may have one.
      await add(oilDraft(), panda);
      // "Other" and "other document" repeat.
      await add(oilDraft(kind: ReminderKind.other, title: 'A'));
      await add(oilDraft(kind: ReminderKind.other, title: 'B'));
      await add(oneShotDraft(anchorDay, kind: ReminderKind.otherDocument));
      await add(oneShotDraft(anchorDay, kind: ReminderKind.otherDocument));
    });

    test('a completed one-shot frees its kind', () async {
      final tax = await add(oneShotDraft(const CalendarDate(2026, 10, 31)));
      final paid = await entry(LogEntryType.legalDue, km: null);
      await reminders.close(tax.id, paid.id);
      await add(oneShotDraft(const CalendarDate(2027, 10, 31)));
    });

    test('refuses an archived or deleted vehicle', () async {
      await vehicles.archive(
        panda.id,
        reason: ArchiveReason.sold,
        date: const CalendarDate(2026, 11, 1),
      );
      await expectLater(
        add(oilDraft(), panda),
        throwsA(isA<VehicleArchivedException>()),
      );
      await vehicles.delete(punto.id);
      await expectLater(add(), throwsA(isA<EntityNotFoundException>()));
    });
  });

  group('update', () {
    test('edits the reference and records an edit change', () async {
      final created = await add();
      clock.advance();
      final updated = await reminders.update(
        created.id,
        oilDraft(km: 20000, months: 24, title: 'Olio 5W-40'),
      );
      expect(updated.refIntervalKm, 20000);
      expect(updated.title, 'Olio 5W-40');
      expect(updated.updatedAt, clock());
      expect(await reminders.getById(created.id), updated);
      final changes = await changesOf(created.id);
      expect(
        [for (final c in changes) c.type],
        [ReminderChangeType.create, ReminderChangeType.edit],
      );
      expect(changes.last.refIntervalKm, 20000);
      expect(
        await auditOf(created.id),
        [AuditOperation.create, AuditOperation.update],
      );
    });

    test('refuses a kind already used on the vehicle', () async {
      await add();
      final filter = await add(oilDraft(kind: ReminderKind.oilFilter));
      await expectLater(
        reminders.update(filter.id, oilDraft()),
        throwsA(isA<ReminderKindAlreadyUsedException>()),
      );
    });

    test('refuses turning an overridden reminder into a one-shot', () async {
      final created = await add();
      await reminders.overrideCriterion(
        created.id,
        appliedMonths: 24,
        reason: 'Pochi km',
      );
      await expectLater(
        reminders.update(
          created.id,
          oilDraft(
            km: null,
            months: null,
            lastDone: null,
            lastDoneKm: null,
            due: const CalendarDate(2027, 1, 1),
          ),
        ),
        throwsInvalid('dueDate'),
      );
    });

    test('a completed reminder is read-only', () async {
      final tax = await add(oneShotDraft(const CalendarDate(2026, 10, 31)));
      await reminders.close(
        tax.id,
        (await entry(LogEntryType.legalDue, km: null)).id,
      );
      await expectLater(
        reminders.update(tax.id, oneShotDraft(const CalendarDate(2027, 1, 1))),
        throwsRule(ReminderRule.completed),
      );
      await expectLater(
        reminders.snooze(
          tax.id,
          untilDate: const CalendarDate(2027, 1, 1),
          reason: 'x',
        ),
        throwsRule(ReminderRule.completed),
      );
    });
  });

  group('override', () {
    test('sets the applied criterion with its reason; the reference stays',
        () async {
      final created = await add();
      clock.advance();
      final custom = await reminders.overrideCriterion(
        created.id,
        appliedKm: 10000,
        reason: '  Uso cittadino  ',
      );
      expect(custom.overrideActive, isTrue);
      expect(custom.appliedIntervalKm, 10000);
      expect(custom.appliedIntervalMonths, isNull);
      expect(custom.overrideReason, 'Uso cittadino');
      expect(custom.overrideAt, clock());
      expect(custom.refIntervalKm, 15000);
      expect(custom.refIntervalMonths, 12);
      final change = (await changesOf(created.id)).last;
      expect(change.type, ReminderChangeType.applyOverride);
      expect(change.reason, 'Uso cittadino');
      expect(change.overrideActive, isTrue);
      expect(change.appliedIntervalKm, 10000);
      expect(
        await auditOf(created.id),
        [AuditOperation.create, AuditOperation.update],
      );
    });

    test('editing an active override is the same call', () async {
      final created = await add();
      await reminders.overrideCriterion(
        created.id,
        appliedKm: 10000,
        reason: 'a',
      );
      final edited = await reminders.overrideCriterion(
        created.id,
        appliedKm: 80000,
        reason: 'non arrivo a 100.000 in 5 anni',
      );
      expect(edited.appliedIntervalKm, 80000);
      expect(isLaxerThanReference(edited), isTrue);
      expect((await changesOf(created.id)), hasLength(3));
    });

    test('refuses both axes disabled, a blank reason, a bad value', () async {
      final created = await add();
      await expectLater(
        reminders.overrideCriterion(created.id, reason: 'x'),
        throwsInvalid('appliedIntervalKm'),
      );
      await expectLater(
        reminders.overrideCriterion(created.id, appliedKm: 1, reason: ' '),
        throwsInvalid('overrideReason'),
      );
      await expectLater(
        reminders.overrideCriterion(created.id, appliedMonths: 0, reason: 'x'),
        throwsInvalid('appliedIntervalMonths'),
      );
      expect((await reminders.getById(created.id))!.overrideActive, isFalse);
    });

    test('refuses a one-shot reminder', () async {
      final tax = await add(oneShotDraft(const CalendarDate(2027, 1, 1)));
      await expectLater(
        reminders.overrideCriterion(tax.id, appliedMonths: 12, reason: 'x'),
        throwsRule(ReminderRule.oneShot),
      );
    });

    test('a new km axis requires the km of the last time, written as anchor',
        () async {
      final timeOnly = await add(oilDraft(km: null, lastDoneKm: null));
      await expectLater(
        reminders.overrideCriterion(
          timeOnly.id,
          appliedKm: 10000,
          appliedMonths: 12,
          reason: 'Aggiungo i km',
        ),
        throwsInvalid('lastDoneKm', InvalidFieldException.required),
      );
      final custom = await reminders.overrideCriterion(
        timeOnly.id,
        appliedKm: 10000,
        appliedMonths: 12,
        reason: 'Aggiungo i km',
        anchorKm: 79000,
      );
      expect(custom.lastDoneKm, 79000);
      expect((await changesOf(timeOnly.id)).last.lastDoneKm, 79000);
      // With an anchor km already there, another is refused.
      await expectLater(
        reminders.overrideCriterion(
          timeOnly.id,
          appliedKm: 12000,
          reason: 'x',
          anchorKm: 1,
        ),
        throwsInvalid('lastDoneKm'),
      );
    });

    test('restoreReference clears the override and keeps the km anchor',
        () async {
      final timeOnly = await add(oilDraft(km: null, lastDoneKm: null));
      await reminders.overrideCriterion(
        timeOnly.id,
        appliedKm: 10000,
        reason: 'x',
        anchorKm: 79000,
      );
      final restored = await reminders.restoreReference(timeOnly.id);
      expect(restored.overrideActive, isFalse);
      expect(restored.appliedIntervalKm, isNull);
      expect(restored.overrideReason, isNull);
      expect(restored.overrideAt, isNull);
      expect(restored.lastDoneKm, 79000);
      expect(
        [for (final c in await changesOf(timeOnly.id)) c.type],
        [
          ReminderChangeType.create,
          ReminderChangeType.applyOverride,
          ReminderChangeType.restoreReference,
        ],
      );
      await expectLater(
        reminders.restoreReference(timeOnly.id),
        throwsRule(ReminderRule.notOverridden),
      );
    });
  });

  group('snooze', () {
    test('postpones past the applied due, never the reference one', () async {
      // Reference: 12 months (due 1 Mar 2027); applied: 24 months (due
      // 1 Mar 2028).
      final created = await add(oilDraft(km: null, lastDoneKm: null));
      await reminders.overrideCriterion(
        created.id,
        appliedMonths: 24,
        reason: 'Poco uso',
      );
      await expectLater(
        reminders.snooze(
          created.id,
          untilDate: const CalendarDate(2027, 9, 1),
          reason: 'x',
        ),
        throwsInvalid('snoozeUntilDate', InvalidFieldException.notLater),
      );
      await expectLater(
        reminders.snooze(
          created.id,
          untilDate: const CalendarDate(2028, 3, 1),
          reason: 'x',
        ),
        throwsInvalid('snoozeUntilDate', InvalidFieldException.notLater),
      );
      final snoozed = await reminders.snooze(
        created.id,
        untilDate: const CalendarDate(2028, 3, 2),
        reason: ' In officina dopo ',
      );
      expect(snoozed.snoozeUntilDate, const CalendarDate(2028, 3, 2));
      expect(snoozed.snoozeReason, 'In officina dopo');
      final change = (await changesOf(created.id)).last;
      expect(change.type, ReminderChangeType.snooze);
      expect(change.reason, 'In officina dopo');
      expect(change.snoozeUntilDate, const CalendarDate(2028, 3, 2));
    });

    test('on the km axis too, and only on an axis that has a due value',
        () async {
      final created = await add();
      await expectLater(
        reminders.snooze(created.id, untilKm: 95000, reason: 'x'),
        throwsInvalid('snoozeUntilKm', InvalidFieldException.notLater),
      );
      final snoozed =
          await reminders.snooze(created.id, untilKm: 96000, reason: 'x');
      expect(snoozed.snoozeUntilKm, 96000);
      final timeOnly = await add(
        oilDraft(kind: ReminderKind.coolant, km: null, lastDoneKm: null),
      );
      await expectLater(
        reminders.snooze(timeOnly.id, untilKm: 1, reason: 'x'),
        throwsInvalid('snoozeUntilKm'),
      );
      final tax = await add(oneShotDraft(const CalendarDate(2027, 1, 1)));
      await expectLater(
        reminders.snooze(tax.id, untilKm: 100000, reason: 'x'),
        throwsInvalid('snoozeUntilKm'),
      );
    });

    test('needs an axis and a reason', () async {
      final created = await add();
      await expectLater(
        reminders.snooze(created.id, reason: 'x'),
        throwsInvalid('snoozeUntilDate'),
      );
      await expectLater(
        reminders.snooze(created.id, untilKm: 99000, reason: '  '),
        throwsInvalid('snoozeReason'),
      );
    });

    test('unsnooze clears it, and refuses when not postponed', () async {
      final created = await add();
      await reminders.snooze(created.id, untilKm: 99000, reason: 'x');
      final cleared = await reminders.unsnooze(created.id);
      expect(cleared.isSnoozed, isFalse);
      expect(cleared.snoozeReason, isNull);
      expect(
        (await changesOf(created.id)).last.type,
        ReminderChangeType.unsnooze,
      );
      await expectLater(
        reminders.unsnooze(created.id),
        throwsRule(ReminderRule.notSnoozed),
      );
    });
  });

  group('close', () {
    test(
        'a maintenance entry moves the anchor; the snooze goes, the '
        'override stays', () async {
      final created = await add();
      await reminders.overrideCriterion(
        created.id,
        appliedKm: 10000,
        reason: 'Città',
      );
      await reminders.snooze(created.id, untilKm: 95000, reason: 'x');
      final work = await entry(LogEntryType.maintenance, km: 91000.5);
      clock.advance();
      final closed = await reminders.close(created.id, work.id);
      expect(closed.lastDoneDate, work.date);
      expect(closed.lastDoneKm, 91000.5);
      expect(closed.lastEntryId, work.id);
      expect(closed.isSnoozed, isFalse);
      expect(closed.overrideActive, isTrue);
      expect(closed.appliedIntervalKm, 10000);
      expect(closed.updatedAt, clock());
      final change = (await changesOf(created.id)).last;
      expect(change.type, ReminderChangeType.close);
      expect(change.entryId, work.id);
      expect(change.lastDoneKm, 91000.5);
      expect(change.snoozeUntilKm, isNull);
      expect((await auditOf(created.id)).last, AuditOperation.update);
    });

    test('the anchor is a copy: editing the entry later never moves it',
        () async {
      final created = await add();
      final work = await entry(LogEntryType.repair, km: 91000);
      await reminders.close(created.id, work.id);
      await entries.update(
        work.id,
        date: const CalendarDate(2026, 10, 31),
        km: 92000,
        type: LogEntryType.repair,
      );
      final read = (await reminders.getById(created.id))!;
      expect(read.lastDoneKm, 91000);
      expect(read.lastDoneDate, const CalendarDate(2026, 10, 30));
    });

    test('only the closing entry types of the kind', () async {
      final oil = await add();
      await expectLater(
        reminders.close(oil.id, (await entry(LogEntryType.refuel)).id),
        throwsRule(ReminderRule.entryTypeCannotClose),
      );
      await expectLater(
        reminders.close(
          oil.id,
          (await entry(LogEntryType.legalDue, km: null)).id,
        ),
        throwsRule(ReminderRule.entryTypeCannotClose),
      );
      final inspection = await add(
        oilDraft(kind: ReminderKind.inspection, km: null, lastDoneKm: null),
      );
      await expectLater(
        reminders.close(
          inspection.id,
          (await entry(LogEntryType.maintenance)).id,
        ),
        throwsRule(ReminderRule.entryTypeCannotClose),
      );
      final paid = await entry(LogEntryType.expense, km: null);
      expect(
        (await reminders.close(inspection.id, paid.id)).lastEntryId,
        paid.id,
      );
    });

    test('refuses an entry of another vehicle', () async {
      final oil = await add();
      final other = await entry(LogEntryType.maintenance, vehicle: panda);
      await expectLater(
        reminders.close(oil.id, other.id),
        throwsRule(ReminderRule.entryOfOtherVehicle),
      );
    });

    test('never moves the anchor back; the same day is accepted', () async {
      final oil = await add();
      await expectLater(
        reminders.close(
          oil.id,
          (await entry(
            LogEntryType.maintenance,
            date: const CalendarDate(2026, 2, 28),
          ))
              .id,
        ),
        throwsInvalid('date', InvalidFieldException.beforeAnchor),
      );
      await expectLater(
        reminders.close(
          oil.id,
          (await entry(LogEntryType.maintenance, km: 79999)).id,
        ),
        throwsInvalid('km', InvalidFieldException.belowAnchor),
      );
      final sameDay = await entry(
        LogEntryType.maintenance,
        date: anchorDay,
        km: 80000,
      );
      expect(
        (await reminders.close(oil.id, sameDay.id)).lastDoneDate,
        anchorDay,
      );
    });

    test('needs the km when the reminder has a km interval', () async {
      final inspection = await add(
        oilDraft(kind: ReminderKind.inspection, km: 100000),
      );
      await expectLater(
        reminders.close(
          inspection.id,
          (await entry(LogEntryType.expense, km: null)).id,
        ),
        throwsInvalid('km', InvalidFieldException.required),
      );
    });

    test('needs the km while the reference has km, even with that axis off',
        () async {
      // Reference every 100 000 km or 24 months; the override turns the km
      // axis off. Closing without km would leave the km anchor empty while
      // `ref_interval_km` is set, which the table forbids.
      final inspection = await add(
        oilDraft(kind: ReminderKind.inspection, km: 100000, months: 24),
      );
      await reminders.overrideCriterion(
        inspection.id,
        appliedMonths: 24,
        reason: 'Solo per tempo',
      );
      await expectLater(
        reminders.close(
          inspection.id,
          (await entry(LogEntryType.legalDue, km: null)).id,
        ),
        throwsInvalid('km', InvalidFieldException.required),
      );
      final read = (await reminders.getById(inspection.id))!;
      expect(read.lastDoneKm, 80000);
      expect(read.lastEntryId, isNull);
      final withKm = await entry(LogEntryType.legalDue, km: 90000);
      expect(
        (await reminders.close(inspection.id, withKm.id)).lastDoneKm,
        90000,
      );
    });

    test('needs the km when only the applied criterion has km', () async {
      final tax = await add(
        oilDraft(kind: ReminderKind.inspection, km: null, lastDoneKm: null),
      );
      await reminders.overrideCriterion(
        tax.id,
        appliedKm: 50000,
        appliedMonths: 12,
        reason: 'Anche a km',
        anchorKm: 79000,
      );
      await expectLater(
        reminders.close(
          tax.id,
          (await entry(LogEntryType.expense, km: null)).id,
        ),
        throwsInvalid('km', InvalidFieldException.required),
      );
    });

    test('refuses an entry dated after today', () async {
      final tax = await add(oneShotDraft(const CalendarDate(2026, 12, 31)));
      final planned = await entry(
        LogEntryType.legalDue,
        km: null,
        date: const CalendarDate(2026, 11, 20),
      );
      await expectLater(
        reminders.close(tax.id, planned.id),
        throwsInvalid('date', InvalidFieldException.inFuture),
      );
    });

    test('a one-shot reminder is completed, once', () async {
      final tax = await add(oneShotDraft(const CalendarDate(2026, 10, 31)));
      final paid = await entry(LogEntryType.legalDue, km: null);
      clock.advance();
      final done = await reminders.close(tax.id, paid.id);
      expect(done.completedAt, clock());
      expect(done.lastEntryId, paid.id);
      expect(done.lastDoneDate, isNull);
      expect((await changesOf(tax.id)).last.type, ReminderChangeType.complete);
      await expectLater(
        reminders.close(tax.id, paid.id),
        throwsRule(ReminderRule.completed),
      );
    });

    test('an archived vehicle is read-only', () async {
      final oil = await add();
      final work = await entry(LogEntryType.maintenance);
      await vehicles.archive(
        punto.id,
        reason: ArchiveReason.sold,
        date: const CalendarDate(2026, 11, 1),
      );
      await expectLater(
        reminders.close(oil.id, work.id),
        throwsA(isA<VehicleArchivedException>()),
      );
      await expectLater(
        reminders.snooze(oil.id, untilKm: 99000, reason: 'x'),
        throwsA(isA<VehicleArchivedException>()),
      );
      await expectLater(
        reminders.delete(oil.id),
        throwsA(isA<VehicleArchivedException>()),
      );
    });
  });

  group('closing from the entry form', () {
    test('the entry and the close land together', () async {
      final oil = await add();
      final work = await entries.create(
        vehicleId: punto.id,
        date: const CalendarDate(2026, 10, 30),
        km: 91000,
        type: LogEntryType.maintenance,
        closesReminderId: oil.id,
      );
      expect((await reminders.getById(oil.id))!.lastEntryId, work.id);
      expect(
        await reminders.watchClosingEntryIds(punto.id).first,
        {work.id},
      );
      expect(await reminders.watchClosedBy(work.id).first, [
        isA<Reminder>().having((r) => r.id, 'id', oil.id),
      ]);
    });

    test('a refused close writes no entry', () async {
      final oil = await add();
      await expectLater(
        entries.create(
          vehicleId: punto.id,
          date: const CalendarDate(2026, 10, 30),
          km: 70000,
          type: LogEntryType.maintenance,
          closesReminderId: oil.id,
        ),
        throwsInvalid('km', InvalidFieldException.belowAnchor),
      );
      expect(await entries.getByVehicle(punto.id), isEmpty);
      expect((await reminders.getById(oil.id))!.lastEntryId, isNull);
    });

    test('an edited entry can close a reminder', () async {
      final oil = await add();
      final work = await entry(LogEntryType.maintenance, km: 90500);
      await entries.update(
        work.id,
        date: work.date,
        km: 90500,
        type: LogEntryType.maintenance,
        closesReminderId: oil.id,
      );
      expect((await reminders.getById(oil.id))!.lastDoneKm, 90500);
    });
  });

  group('markDone', () {
    test('creates a maintenance entry and closes the reminder with it',
        () async {
      final oil = await add();
      final done = await reminders.markDone(
        oil.id,
        date: const CalendarDate(2026, 11, 1),
        km: 92000,
        costCents: 8900,
        description: 'Olio motore',
      );
      expect(done.entry.type, LogEntryType.maintenance);
      expect(done.entry.costCents, 8900);
      expect(done.reminder.lastEntryId, done.entry.id);
      expect(done.reminder.lastDoneKm, 92000);
      expect(await entries.getById(done.entry.id), done.entry);
    });

    test('a legal kind creates a legal deadline, km optional', () async {
      final tax = await add(
        oilDraft(kind: ReminderKind.roadTax, km: null, lastDoneKm: null),
      );
      final done = await reminders.markDone(
        tax.id,
        date: const CalendarDate(2026, 11, 1),
      );
      expect(done.entry.type, LogEntryType.legalDue);
      expect(done.entry.km, isNull);
      expect(done.reminder.lastDoneDate, const CalendarDate(2026, 11, 1));
    });

    test('a refusal writes nothing', () async {
      final oil = await add();
      await expectLater(
        reminders.markDone(oil.id, date: const CalendarDate(2026, 11, 1)),
        throwsInvalid('km'),
      );
      expect(await entries.getByVehicle(punto.id), isEmpty);
      expect((await changesOf(oil.id)), hasLength(1));
    });
  });

  group('delete and restore', () {
    test('a soft delete hides only the reminder; restore brings it back',
        () async {
      final oil = await add();
      final coolant = await add(oilDraft(kind: ReminderKind.coolant));
      await reminders.delete(oil.id);
      expect(await reminders.getById(oil.id), isNull);
      expect(await reminders.watchByVehicle(punto.id).first, [coolant]);
      final restored = await reminders.restore(oil.id);
      expect(await reminders.getById(oil.id), restored);
      expect(
        await auditOf(oil.id),
        [AuditOperation.create, AuditOperation.delete, AuditOperation.restore],
      );
    });

    test('restore is refused when the kind was taken meanwhile', () async {
      final oil = await add();
      await reminders.delete(oil.id);
      await add();
      await expectLater(
        reminders.restore(oil.id),
        throwsA(isA<ReminderKindAlreadyUsedException>()),
      );
    });

    test('restore is refused once the vehicle is in the Trash', () async {
      final oil = await add();
      await reminders.delete(oil.id);
      await vehicles.delete(punto.id);
      await expectLater(
        reminders.restore(oil.id),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });

  group('reads', () {
    test(
        'the active list leaves out archived and trashed vehicles, '
        'completed and deleted reminders', () async {
      final oil = await add();
      final tax = await add(oneShotDraft(const CalendarDate(2026, 10, 31)));
      await reminders.close(
        tax.id,
        (await entry(LogEntryType.legalDue, km: null)).id,
      );
      final deleted = await add(oilDraft(kind: ReminderKind.coolant));
      await reminders.delete(deleted.id);
      final pandaOil = await add(oilDraft(), panda);
      final active = await reminders.watchActiveAcrossVehicles().first;
      expect(
        {for (final a in active) a.reminder.id},
        {oil.id, pandaOil.id},
      );
      expect(
        active.firstWhere((a) => a.reminder.id == oil.id).vehicle.plate,
        'AB123CD',
      );
      await vehicles.archive(
        panda.id,
        reason: ArchiveReason.sold,
        date: const CalendarDate(2026, 11, 1),
      );
      await vehicles.delete(punto.id);
      expect(await reminders.watchActiveAcrossVehicles().first, isEmpty);
      // The vehicle tab lists the archived vehicle's reminders, read-only.
      expect(await reminders.watchByVehicle(panda.id).first, hasLength(1));
      expect(await reminders.watchByVehicle(punto.id).first, isEmpty);
    });

    test('closable: open reminders whose kind accepts the type', () async {
      final oil = await add();
      final tax = await add(
        oilDraft(kind: ReminderKind.roadTax, km: null, lastDoneKm: null),
      );
      expect(
        [
          for (final r in await reminders
              .watchClosable(punto.id, LogEntryType.repair)
              .first)
            r.id,
        ],
        [oil.id],
      );
      expect(
        [
          for (final r in await reminders
              .watchClosable(punto.id, LogEntryType.expense)
              .first)
            r.id,
        ],
        [tax.id],
      );
      expect(
        await reminders.watchClosable(punto.id, LogEntryType.refuel).first,
        isEmpty,
      );
    });
  });

  group('Trash, cleanup and stamp', () {
    test('the vehicle counts its live reminders', () async {
      await add();
      final tax = await add(oneShotDraft(const CalendarDate(2027, 1, 1)));
      final gone = await add(oilDraft(kind: ReminderKind.coolant));
      await reminders.delete(gone.id);
      expect((await vehicles.countContents(punto.id)).reminderCount, 2);
      await vehicles.delete(punto.id);
      final trashed = await vehicles.watchTrashed().first;
      expect(trashed.single.contents.reminderCount, 2);
      expect(tax.isOneShot, isTrue);
    });

    test('purging a vehicle removes its reminders and their history first',
        () async {
      final oil = await add();
      await reminders.close(
        oil.id,
        (await entry(LogEntryType.maintenance)).id,
      );
      final deleted = await add(oilDraft(kind: ReminderKind.coolant));
      await reminders.delete(deleted.id);
      final pandaOil = await add(oilDraft(), panda);
      await vehicles.delete(punto.id);
      await vehicles.purge(punto.id);
      Future<int> count(String sql) async =>
          (await db.customSelect(sql).getSingle()).read<int>('c');
      expect(
        await count(
          "SELECT COUNT(*) AS c FROM reminders WHERE vehicle_id = '${punto.id}'",
        ),
        0,
      );
      expect(
        await count(
          'SELECT COUNT(*) AS c FROM reminder_changes '
          "WHERE reminder_id IN ('${oil.id}', '${deleted.id}')",
        ),
        0,
      );
      expect(await reminders.getById(pandaOil.id), isNotNull);
      expect(await changesOf(pandaOil.id), hasLength(1));
    });

    test('the 30-day cleanup removes a deleted reminder with its history',
        () async {
      final old = await add();
      final recent = await add(oilDraft(kind: ReminderKind.coolant));
      final keep = await add(oilDraft(kind: ReminderKind.brakeFluid));
      await reminders.delete(old.id);
      clock.advance(const Duration(days: 20));
      await reminders.delete(recent.id);
      final now = clock().add(const Duration(days: 10));
      final before = await db.backupDao.lastModifiedAt();
      final report = await TrashCleanupService(
        db.trashDao,
        db.auditLogDao,
        MemoryAttachmentStore(),
      ).runStartupCleanup(now);
      expect(report.reminders, 1);
      expect(await db.remindersDao.getDeletedById(old.id), isNull);
      expect(await changesOf(old.id), isEmpty);
      expect(await db.remindersDao.getDeletedById(recent.id), isNotNull);
      expect(await reminders.getById(keep.id), isNotNull);
      expect((await auditOf(old.id)).last, AuditOperation.purge);
      expect(await db.backupDao.lastModifiedAt(), now);
      expect(now.isAfter(before!), isTrue);
    });

    test('a reminder of a vehicle in the Trash goes only with the vehicle',
        () async {
      final oil = await add();
      await reminders.delete(oil.id);
      final deletedAt = clock();
      clock.advance(const Duration(days: 20));
      await vehicles.delete(punto.id);
      // The reminder is 31 days deleted, its vehicle only 11 in the Trash.
      final report = await TrashCleanupService(
        db.trashDao,
        db.auditLogDao,
        MemoryAttachmentStore(),
      ).runStartupCleanup(deletedAt.add(const Duration(days: 31)));
      expect(report.reminders, 0);
      expect(await db.remindersDao.getDeletedById(oil.id), isNotNull);
    });

    test('a purged closing entry clears the link, not the anchor', () async {
      final oil = await add();
      final work = await entry(LogEntryType.maintenance, km: 91000);
      await reminders.close(oil.id, work.id);
      await entries.delete(work.id);
      await TrashCleanupService(
        db.trashDao,
        db.auditLogDao,
        MemoryAttachmentStore(),
      ).runStartupCleanup(clock().add(const Duration(days: 31)));
      final read = (await reminders.getById(oil.id))!;
      expect(read.lastEntryId, isNull);
      expect(read.lastDoneKm, 91000);
    });

    test('every reminder write moves the data stamp', () async {
      final oil = await add();
      expect(await db.backupDao.lastModifiedAt(), oil.updatedAt);
      clock.advance();
      final snoozed =
          await reminders.snooze(oil.id, untilKm: 99000, reason: 'x');
      expect(await db.backupDao.lastModifiedAt(), snoozed.updatedAt);
      clock.advance();
      await reminders.delete(oil.id);
      expect(await db.backupDao.lastModifiedAt(), clock());
    });
  });
}
