import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry.dart';
import 'package:vehicle_history/data/models/log_entry_filter.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/audit_log_repository.dart';
import 'package:vehicle_history/data/repositories/drift_log_entry_repository.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';
import 'package:vehicle_history/data/repositories/repository_exceptions.dart';

import 'test_support.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late DriftVehicleRepository vehicles;
  late DriftLogEntryRepository entries;
  late DriftAuditLogRepository audit;
  late Vehicle punto;
  late Vehicle panda;

  setUp(() async {
    db = openTestDatabase();
    // After every entry date used below: work entries cannot be dated in
    // the future (E1). Noon UTC, the same local day in any timezone.
    clock = FakeClock(DateTime.utc(2026, 11, 2, 12));
    final owners =
        DriftOwnerRepository(db.ownersDao, db.auditLogDao, clock: clock.call);
    vehicles = DriftVehicleRepository(
      db.vehiclesDao,
      db.mileageReadingsDao,
      db.auditLogDao,
      clock: clock.call,
    );
    entries = DriftLogEntryRepository(
      db.logEntriesDao,
      db.auditLogDao,
      clock: clock.call,
    );
    audit = DriftAuditLogRepository(db.auditLogDao);
    final mario = await owners.create(firstName: 'Mario');
    punto = await vehicles.create(
      plate: 'AB123CD',
      kind: VehicleKind.car,
      ownerId: mario.id,
      currentOdometerKm: 85000,
      fuelType: FuelType.petrol,
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

  /// Creates an entry for [vehicle] (the Punto by default), advancing the
  /// clock first so every entry has a distinct creation instant.
  Future<LogEntry> add({
    Vehicle? vehicle,
    CalendarDate date = const CalendarDate(2026, 10, 1),
    int? km = 85000,
    LogEntryType type = LogEntryType.maintenance,
    String? description,
    int? costCents,
  }) {
    clock.advance();
    return entries.create(
      vehicleId: (vehicle ?? punto).id,
      date: date,
      km: km,
      type: type,
      description: description,
      costCents: costCents,
    );
  }

  /// The ids of the Punto's entries that pass [filter], in list order.
  Future<List<String>> ids([
    LogEntryFilter filter = LogEntryFilter.none,
  ]) async {
    final list = await entries.watchByVehicle(punto.id, filter: filter).first;
    return [for (final e in list) e.id];
  }

  group('create', () {
    test('stores every field and trims the description', () async {
      final entry = await add(
        date: const CalendarDate(2026, 3, 4),
        km: 85432,
        description: '  Tagliando 90.000  ',
        costCents: 25050,
      );

      expect(entry.vehicleId, punto.id);
      expect(entry.date, const CalendarDate(2026, 3, 4));
      expect(entry.km, 85432);
      expect(entry.type, LogEntryType.maintenance);
      expect(entry.description, 'Tagliando 90.000');
      expect(entry.costCents, 25050);
      expect(entry.createdAt, clock());
      expect(entry.updatedAt, clock());
      expect(await entries.getById(entry.id), entry);
    });

    test('stores a blank description and no cost as null', () async {
      final entry = await add(description: '   ');
      final stored = (await entries.getById(entry.id))!;
      expect(stored.description, isNull);
      expect(stored.costCents, isNull);
    });

    test('keeps a cost of zero apart from no cost', () async {
      final free = await add(costCents: 0);
      expect((await entries.getById(free.id))!.costCents, 0);
    });

    test('round-trips every entry type', () async {
      for (final type in LogEntryType.values) {
        final entry = await add(type: type);
        expect((await entries.getById(entry.id))!.type, type);
      }
    });

    test('never changes the vehicle odometer', () async {
      await add(km: 99999);
      expect((await vehicles.getById(punto.id))!.currentOdometerKm, 85000);
    });

    test('refuses a missing or deleted vehicle and writes nothing', () async {
      await expectLater(
        entries.create(
          vehicleId: 'no-such-vehicle',
          date: const CalendarDate(2026, 1, 1),
          type: LogEntryType.note,
        ),
        throwsA(
          isA<EntityNotFoundException>()
              .having((e) => e.entityType, 'type', AuditEntityType.vehicle),
        ),
      );
      await vehicles.delete(panda.id);
      await expectLater(
        add(vehicle: panda, type: LogEntryType.note, km: null),
        throwsA(isA<EntityNotFoundException>()),
      );
      final count = await db
          .customSelect('SELECT COUNT(*) AS c FROM log_entries')
          .getSingle();
      expect(count.read<int>('c'), 0);
    });
  });

  group('km rule per type', () {
    const required = {
      LogEntryType.maintenance,
      LogEntryType.repair,
      LogEntryType.refuel,
      LogEntryType.genericCheck,
      LogEntryType.measuredCheck,
    };

    test('the types that require the km are exactly the agreed ones', () {
      expect(
        {
          for (final t in LogEntryType.values)
            if (t.requiresKm) t,
        },
        required,
      );
    });

    for (final type in LogEntryType.values) {
      if (required.contains(type)) {
        test('${type.name} without km is refused', () async {
          await expectLater(
            add(type: type, km: null),
            throwsA(
              isA<InvalidFieldException>()
                  .having((e) => e.field, 'field', 'km'),
            ),
          );
          expect(await ids(), isEmpty);
        });
      } else {
        test('${type.name} without km is accepted', () async {
          final entry = await add(type: type, km: null);
          expect((await entries.getById(entry.id))!.km, isNull);
        });
      }
    }

    test('update applies the same rule', () async {
      final entry = await add(type: LogEntryType.note, km: null);
      await expectLater(
        entries.update(
          entry.id,
          date: entry.date,
          type: LogEntryType.repair,
        ),
        throwsA(isA<InvalidFieldException>()),
      );
      expect((await entries.getById(entry.id))!.type, LogEntryType.note);
    });

    test('a negative km or cost is refused', () async {
      await expectLater(add(km: -1), throwsA(isA<InvalidFieldException>()));
      await expectLater(
        add(costCents: -1),
        throwsA(
          isA<InvalidFieldException>()
              .having((e) => e.field, 'field', 'costCents'),
        ),
      );
      expect(await ids(), isEmpty);
    });

    test('the database refuses a negative km or cost too', () async {
      final entry = await add();
      for (final column in ['km', 'cost_cents']) {
        await expectLater(
          db.customStatement(
            "UPDATE log_entries SET $column = -5 WHERE id = '${entry.id}'",
          ),
          throwsA(anything),
        );
      }
    });
  });

  group('update', () {
    test('replaces every editable field and keeps the rest', () async {
      final entry = await add(description: 'Old', costCents: 100);
      clock.advance();
      final updated = await entries.update(
        entry.id,
        date: const CalendarDate(2025, 12, 31),
        km: null,
        type: LogEntryType.expense,
        description: 'Autostrada',
        costCents: null,
      );

      expect(updated.date, const CalendarDate(2025, 12, 31));
      expect(updated.km, isNull);
      expect(updated.type, LogEntryType.expense);
      expect(updated.description, 'Autostrada');
      expect(updated.costCents, isNull);
      expect(updated.vehicleId, punto.id);
      expect(updated.createdAt, entry.createdAt);
      expect(updated.updatedAt, clock());
      expect(await entries.getById(entry.id), updated);
    });

    test('refuses a deleted entry', () async {
      final entry = await add();
      await entries.delete(entry.id);
      await expectLater(
        entries.update(
          entry.id,
          date: entry.date,
          km: 1,
          type: entry.type,
        ),
        throwsA(
          isA<EntityNotFoundException>()
              .having((e) => e.entityType, 'type', AuditEntityType.logEntry),
        ),
      );
    });
  });

  group('delete and restore', () {
    test('delete hides the entry and restore brings it back', () async {
      final entry = await add();
      await entries.delete(entry.id);
      expect(await entries.getById(entry.id), isNull);
      expect(await ids(), isEmpty);

      clock.advance();
      final restored = await entries.restore(entry.id);
      expect(restored.updatedAt, clock());
      expect(await entries.getById(entry.id), restored);
      expect(await ids(), [entry.id]);
    });

    test('delete of a missing entry fails', () async {
      await expectLater(
        entries.delete('nope'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('restore of a live entry fails and writes nothing', () async {
      final entry = await add();
      await expectLater(
        entries.restore(entry.id),
        throwsA(isA<EntityNotFoundException>()),
      );
      final log = await audit.getForEntity(AuditEntityType.logEntry, entry.id);
      expect(log, hasLength(1));
    });

    test('restore is refused once the vehicle has been deleted', () async {
      final entry = await add();
      await entries.delete(entry.id);
      await vehicles.delete(punto.id);

      await expectLater(
        entries.restore(entry.id),
        throwsA(
          isA<EntityNotFoundException>()
              .having((e) => e.entityType, 'type', AuditEntityType.vehicle),
        ),
      );
      // Still deleted, and no restore was recorded.
      expect(await db.logEntriesDao.getDeletedById(entry.id), isNotNull);
      final log = await audit.getForEntity(AuditEntityType.logEntry, entry.id);
      expect([
        for (final e in log) e.operation,
      ], [
        AuditOperation.create,
        AuditOperation.delete,
      ]);
    });
  });

  group('entries of a deleted vehicle', () {
    test('are hidden, untouched, and come back with the vehicle', () async {
      final entry = await add(description: 'Gomme');
      final stream = entries.watchByVehicle(punto.id);
      final emitted = <List<String>>[];
      final sub = stream.listen((l) => emitted.add([for (final e in l) e.id]));
      addTearDown(sub.cancel);
      await pumpEventQueue();

      await vehicles.delete(punto.id);
      await pumpEventQueue();
      expect(await entries.getById(entry.id), isNull);
      expect(await ids(), isEmpty);
      // Not soft-deleted: the row is exactly as it was.
      expect(await db.logEntriesDao.getDeletedById(entry.id), isNull);

      await vehicles.restore(punto.id);
      await pumpEventQueue();
      expect(await entries.getById(entry.id), entry);
      expect(emitted, [
        [entry.id],
        <String>[],
        [entry.id],
      ]);
    });

    test('cannot be edited or deleted while it is deleted', () async {
      final entry = await add();
      await vehicles.delete(punto.id);
      await expectLater(
        entries.delete(entry.id),
        throwsA(isA<EntityNotFoundException>()),
      );
      await expectLater(
        entries.update(entry.id, date: entry.date, km: 1, type: entry.type),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });

  group('order', () {
    test('newest day first, then newest created first', () async {
      final oldest = await add(date: const CalendarDate(2025, 1, 31));
      final sameDayFirst = await add(date: const CalendarDate(2026, 2, 1));
      final newest = await add(date: const CalendarDate(2026, 10, 19));
      final sameDaySecond = await add(date: const CalendarDate(2026, 2, 1));

      expect(await ids(), [
        newest.id,
        sameDaySecond.id,
        sameDayFirst.id,
        oldest.id,
      ]);
    });

    test('lists only the entries of the requested vehicle', () async {
      final mine = await add();
      await add(vehicle: panda, km: 1000);
      expect(await ids(), [mine.id]);
    });

    test('the list refreshes after every write', () async {
      final emitted = <int>[];
      final sub = entries
          .watchByVehicle(punto.id)
          .listen((list) => emitted.add(list.length));
      addTearDown(sub.cancel);
      await pumpEventQueue();

      final entry = await add();
      await pumpEventQueue();
      await entries.delete(entry.id);
      await pumpEventQueue();
      expect(emitted, [0, 1, 0]);
    });
  });

  group('filters', () {
    late LogEntry jan1;
    late LogEntry jan31;
    late LogEntry feb1;
    late LogEntry mar15;

    setUp(() async {
      jan1 = await add(
        date: const CalendarDate(2026, 1, 1),
        type: LogEntryType.maintenance,
        description: 'Cambio olio e filtro',
      );
      jan31 = await add(
        date: const CalendarDate(2026, 1, 31),
        type: LogEntryType.refuel,
        description: 'Gasolina en Málaga',
      );
      feb1 = await add(
        date: const CalendarDate(2026, 2, 1),
        type: LogEntryType.legalDue,
        km: null,
        description: 'BOLLO AUTO',
      );
      mar15 = await add(
        date: const CalendarDate(2026, 3, 15),
        type: LogEntryType.note,
        km: null,
      );
    });

    test('no filter lists everything', () async {
      expect(await ids(), [mar15.id, feb1.id, jan31.id, jan1.id]);
    });

    test('date range is inclusive on both ends', () async {
      final filter = const LogEntryFilter(
        from: CalendarDate(2026, 1, 31),
        to: CalendarDate(2026, 2, 1),
      );
      expect(await ids(filter), [feb1.id, jan31.id]);
    });

    test('a single-day range finds that day', () async {
      const day = CalendarDate(2026, 1, 1);
      expect(await ids(const LogEntryFilter(from: day, to: day)), [jan1.id]);
    });

    test('an open-ended range has one bound only', () async {
      expect(
        await ids(const LogEntryFilter(from: CalendarDate(2026, 2, 1))),
        [mar15.id, feb1.id],
      );
      expect(
        await ids(const LogEntryFilter(to: CalendarDate(2026, 1, 31))),
        [jan31.id, jan1.id],
      );
    });

    test('one type', () async {
      expect(
        await ids(const LogEntryFilter(types: {LogEntryType.refuel})),
        [jan31.id],
      );
    });

    test('several types', () async {
      expect(
        await ids(
          const LogEntryFilter(
            types: {LogEntryType.maintenance, LogEntryType.note},
          ),
        ),
        [mar15.id, jan1.id],
      );
    });

    test('text is a substring, case-insensitive', () async {
      expect(await ids(const LogEntryFilter(text: 'olio')), [jan1.id]);
      expect(await ids(const LogEntryFilter(text: 'bollo')), [feb1.id]);
      expect(await ids(const LogEntryFilter(text: 'FILTR')), [jan1.id]);
    });

    test('text ignores accents both ways', () async {
      expect(await ids(const LogEntryFilter(text: 'malaga')), [jan31.id]);
      expect(await ids(const LogEntryFilter(text: 'MÁLAGA')), [jan31.id]);
      expect(await ids(const LogEntryFilter(text: 'cámbio')), [jan1.id]);
    });

    test('text never matches an entry without description', () async {
      expect(await ids(const LogEntryFilter(text: 'a')), [
        feb1.id,
        jan31.id,
        jan1.id,
      ]);
    });

    test('blank text is no filter', () async {
      expect(await ids(const LogEntryFilter(text: '   ')), hasLength(4));
    });

    test('criteria combine with AND', () async {
      final filter = const LogEntryFilter(
        from: CalendarDate(2026, 1, 15),
        to: CalendarDate(2026, 3, 31),
        types: {LogEntryType.refuel, LogEntryType.note},
        text: 'gasolina',
      );
      expect(await ids(filter), [jan31.id]);
      expect(await ids(filter.withText('')), [mar15.id, jan31.id]);
      expect(
        await ids(filter.withTypes(const {LogEntryType.maintenance})),
        isEmpty,
      );
    });

    test('the Dart reference agrees with the repository', () async {
      final all = await entries.watchByVehicle(punto.id).first;
      for (final filter in [
        const LogEntryFilter(types: {LogEntryType.legalDue}),
        const LogEntryFilter(text: 'málaga'),
        const LogEntryFilter(
          from: CalendarDate(2026, 1, 31),
          to: CalendarDate(2026, 1, 31),
        ),
      ]) {
        expect(
          await ids(filter),
          [
            for (final e in all)
              if (filter.matches(e)) e.id,
          ],
          reason: '$filter',
        );
      }
    });
  });

  group('audit log', () {
    test('records create, update, delete and restore in order', () async {
      final entry = await add();
      clock.advance();
      await entries.update(
        entry.id,
        date: entry.date,
        km: 1,
        type: entry.type,
      );
      clock.advance();
      await entries.delete(entry.id);
      clock.advance();
      await entries.restore(entry.id);

      final log = await audit.getForEntity(AuditEntityType.logEntry, entry.id);
      expect([
        for (final e in log) e.operation,
      ], [
        AuditOperation.create,
        AuditOperation.update,
        AuditOperation.delete,
        AuditOperation.restore,
      ]);
      expect(log.last.at, clock());
    });

    test('a refused write records nothing', () async {
      await expectLater(
        add(type: LogEntryType.repair, km: null),
        throwsA(isA<InvalidFieldException>()),
      );
      final count = await db
          .customSelect(
            "SELECT COUNT(*) AS c FROM audit_log WHERE entity_type = 'logEntry'",
          )
          .getSingle();
      expect(count.read<int>('c'), 0);
    });
  });

  group('future dates per type (E1)', () {
    /// The day after the fake clock's day.
    const tomorrow = CalendarDate(2026, 11, 3);

    for (final type in LogEntryType.values) {
      if (type.allowsFutureDate) {
        test('${type.name} accepts a future date', () async {
          final entry = await add(type: type, date: tomorrow);
          expect(entry.date, tomorrow);
        });
      } else {
        test('${type.name} refuses a future date, on create and update',
            () async {
          expect(
            () => add(type: type, date: tomorrow),
            throwsA(
              isA<InvalidFieldException>()
                  .having((e) => e.field, 'field', 'date')
                  .having(
                    (e) => e.reason,
                    'reason',
                    InvalidFieldException.inFuture,
                  ),
            ),
          );
          final today =
              await add(type: type, date: const CalendarDate(2026, 11, 2));
          expect(
            () => entries.update(
              today.id,
              date: tomorrow,
              km: today.km,
              type: type,
            ),
            throwsA(isA<InvalidFieldException>()),
          );
        });
      }
    }

    test('only legal deadlines, expenses and notes allow future dates', () {
      expect(
        {
          for (final t in LogEntryType.values)
            if (t.allowsFutureDate) t,
        },
        {LogEntryType.legalDue, LogEntryType.expense, LogEntryType.note},
      );
    });
  });
}
