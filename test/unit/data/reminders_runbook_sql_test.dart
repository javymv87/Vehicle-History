import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/reminder.dart';
import 'package:vehicle_history/data/models/reminder_kind.dart';
import 'package:vehicle_history/data/models/reminder_status.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/drift_log_entry_repository.dart';
import 'package:vehicle_history/data/repositories/drift_mileage_reading_repository.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_reminder_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';
import 'package:vehicle_history/data/repositories/reminder_closer.dart';

import 'test_support.dart';

/// Keeps the loading procedure of `Docs/08_recordatorios.md` honest: runs
/// the very statements of `tool/reminders/insert_reminder.sql` on a v11
/// database, as the procedure does on an exported package, and checks that
/// the app reads what they wrote. If the schema changes, this test says the
/// procedure must change too.
void main() {
  late AppDatabase db;
  late FakeClock clock;
  late DriftReminderRepository reminders;
  late Vehicle punto;

  /// The statements of the SQL file, without its comments, in order.
  List<String> statements() {
    final source = File('tool/reminders/insert_reminder.sql')
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('--'))
        .join('\n');
    return [
      for (final statement in source.split(';'))
        if (statement.trim().isNotEmpty) statement.trim(),
    ];
  }

  /// Runs every statement with the named [values], bound in the order the
  /// placeholders appear (a name may repeat).
  Future<void> run(Map<String, Object?> values) async {
    final placeholder = RegExp(r':([a-z_]+)');
    for (final statement in statements()) {
      final names = [
        for (final match in placeholder.allMatches(statement)) match.group(1)!,
      ];
      for (final name in names) {
        expect(values.containsKey(name), isTrue, reason: 'missing :$name');
      }
      await db.customStatement(
        statement.replaceAll(placeholder, '?'),
        [for (final name in names) values[name]],
      );
    }
  }

  setUp(() async {
    db = openTestDatabase();
    clock = FakeClock(DateTime.utc(2026, 11, 2, 12));
    final owners =
        DriftOwnerRepository(db.ownersDao, db.auditLogDao, clock: clock.call);
    final vehicles = DriftVehicleRepository(
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
    reminders = DriftReminderRepository(
      db.remindersDao,
      db.auditLogDao,
      entries: DriftLogEntryRepository(
        db.logEntriesDao,
        db.auditLogDao,
        attachments: attachmentWriterOf(db),
        reminders: closer,
        clock: clock.call,
      ),
      closer: closer,
      clock: clock.call,
    );
    final mario = await owners.create(firstName: 'Mario');
    punto = await vehicles.create(
      plate: 'FG123HI',
      kind: VehicleKind.car,
      make: 'Fiat',
      model: 'Grande Punto',
      ownerId: mario.id,
      currentOdometerKm: 85000,
      fuelType: FuelType.petrolLpg,
    );
  });

  tearDown(() => db.close());

  test('the runbook SQL writes reminders the app reads and keeps', () async {
    // Step 4 of the procedure: the format of an existing timestamp.
    final existing = (await db.customSelect(
      'SELECT updated_at FROM vehicles WHERE id = ?',
      variables: [Variable(punto.id)],
    ).getSingle())
        .read<String>('updated_at');
    final isoUtc = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$');
    expect(existing, matches(isoUtc));
    final instant = DateTime.utc(2026, 11, 3, 9, 15);
    final now = instant.toIso8601String();
    expect(now, matches(isoUtc));
    final before = await db.backupDao.lastModifiedAt();

    // Two realistic items: oil by km and months, coolant by months only.
    final oil = {
      'id': '0a1b2c3d-0000-4000-8000-000000000001',
      'change_id': '0a1b2c3d-0000-4000-8000-000000000002',
      'audit_id': '0a1b2c3d-0000-4000-8000-000000000003',
      'now': now,
      'vehicle_id': punto.id,
      'kind': ReminderKind.engineOil.code,
      'title': 'Olio motore',
      'note': 'Uso gravoso: ogni 10.000 km o 12 mesi',
      'manual_ref': 'p. 174, Piano di manutenzione',
      'ref_interval_km': 15000.0,
      'ref_interval_months': 24,
      'due_date': null,
      'last_done_date': '2026-03-01',
      'last_done_km': 70000.0,
    };
    final coolant = {
      ...oil,
      'id': '0a1b2c3d-0000-4000-8000-000000000004',
      'change_id': '0a1b2c3d-0000-4000-8000-000000000005',
      'audit_id': '0a1b2c3d-0000-4000-8000-000000000006',
      'kind': ReminderKind.coolant.code,
      'title': 'Liquido di raffreddamento',
      'note': null,
      'manual_ref': 'p. 175',
      'ref_interval_km': null,
      'ref_interval_months': 48,
      'last_done_date': '2025-06-15',
      'last_done_km': null,
    };
    await db.transaction(() async {
      await db.customStatement('PRAGMA foreign_keys = ON');
      await run(oil);
      await run(coolant);
    });

    // The app reads both, as generated reminders with no owner decisions.
    final loaded = {
      for (final r in await reminders.getByVehicle(punto.id)) r.kind: r,
    };
    expect(loaded.keys, {ReminderKind.engineOil, ReminderKind.coolant});
    final readOil = loaded[ReminderKind.engineOil]!;
    expect(readOil.id, oil['id']);
    expect(readOil.source, ReminderSource.generated);
    expect(readOil.title, 'Olio motore');
    expect(readOil.manualRef, 'p. 174, Piano di manutenzione');
    expect(readOil.refIntervalKm, 15000);
    expect(readOil.refIntervalMonths, 24);
    expect(readOil.lastDoneDate, const CalendarDate(2026, 3, 1));
    expect(readOil.lastDoneKm, 70000);
    expect(readOil.overrideActive, isFalse);
    expect(readOil.isSnoozed, isFalse);
    expect(readOil.leadDays, isNull);
    expect(readOil.lastEntryId, isNull);
    expect(readOil.createdAt, instant);
    expect(readOil.updatedAt, instant);
    final readCoolant = loaded[ReminderKind.coolant]!;
    expect(readCoolant.refIntervalKm, isNull);
    expect(readCoolant.lastDoneKm, isNull);

    // Their status, as the app computes it.
    const today = CalendarDate(2026, 11, 3);
    expect(
      evaluateReminder(
        readOil,
        today: today,
        currentKm: punto.currentOdometerKm,
        lead: const ReminderLead(),
      ).status,
      // 70,000 + 15,000 km is already behind the 85,000 km odometer.
      ReminderStatus.overdue,
    );
    final coolantDue = evaluateReminder(
      readCoolant,
      today: today,
      currentKm: punto.currentOdometerKm,
      lead: const ReminderLead(),
    );
    expect(coolantDue.dueDate, const CalendarDate(2029, 6, 15));
    expect(coolantDue.status, ReminderStatus.ok);

    // Each has its create change and its create audit row.
    final changes = await reminders.watchChanges(readOil.id).first;
    expect(changes.single.type, ReminderChangeType.create);
    expect(changes.single.lastDoneKm, 70000);
    expect(changes.single.changedAt, instant);
    final audit =
        await db.auditLogDao.getForEntity(AuditEntityType.reminder, readOil.id);
    expect(audit.single.operation, AuditOperation.create);

    // The partial unique index refuses a second open oil reminder.
    await expectLater(
      run({
        ...oil,
        'id': '0a1b2c3d-0000-4000-8000-000000000007',
        'change_id': '0a1b2c3d-0000-4000-8000-000000000008',
        'audit_id': '0a1b2c3d-0000-4000-8000-000000000009',
      }),
      throwsA(anything),
    );

    // The data stamp moved to the instant written, and the file is sound.
    expect(before, isNotNull);
    expect(await db.backupDao.lastModifiedAt(), instant);
    expect((await db.backupDao.liveCounts()).reminders, 2);
    expect(
      await db.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
    final integrity =
        await db.customSelect('PRAGMA integrity_check').getSingle();
    expect(integrity.data.values.single, 'ok');

    // The app can work on them afterwards, like on its own.
    clock.advance(const Duration(days: 2));
    final custom = await reminders.overrideCriterion(
      readOil.id,
      appliedKm: 20000,
      reason: 'Uso extraurbano',
    );
    expect(custom.refIntervalKm, 15000);
    expect(custom.appliedIntervalKm, 20000);
  });
}
