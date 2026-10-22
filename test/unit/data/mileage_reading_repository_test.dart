import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/mileage_reading.dart';
import 'package:vehicle_history/data/models/odometer_checks.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/audit_log_repository.dart';
import 'package:vehicle_history/data/repositories/drift_log_entry_repository.dart';
import 'package:vehicle_history/data/repositories/drift_mileage_reading_repository.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';
import 'package:vehicle_history/data/repositories/repository_exceptions.dart';

import 'test_support.dart';

/// Day of the fake clock, "today" for every rule below.
const CalendarDate _today = CalendarDate(2026, 10, 19);

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late DriftVehicleRepository vehicles;
  late DriftMileageReadingRepository readings;
  late DriftAuditLogRepository audit;
  late Vehicle punto;

  setUp(() async {
    db = openTestDatabase();
    // Noon UTC: the same local day in any timezone within ±11 hours.
    clock = FakeClock(DateTime.utc(2026, 10, 19, 12));
    final owners =
        DriftOwnerRepository(db.ownersDao, db.auditLogDao, clock: clock.call);
    vehicles = DriftVehicleRepository(
      db.vehiclesDao,
      db.mileageReadingsDao,
      db.trashDao,
      db.auditLogDao,
      attachmentFiles: MemoryAttachmentStore(),
      clock: clock.call,
    );
    readings = DriftMileageReadingRepository(
      db.mileageReadingsDao,
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
  });

  tearDown(() => db.close());

  /// Readings of the Punto, newest first.
  Future<List<MileageReading>> series() =>
      readings.watchByVehicle(punto.id).first;

  /// The Punto's cached odometer.
  Future<int> odometer() async =>
      (await vehicles.getById(punto.id))!.currentOdometerKm;

  /// Adds a reading to the Punto, advancing the clock first so readings of
  /// the same day keep their order.
  Future<MileageReading> add(int km, {CalendarDate date = _today}) {
    clock.advance();
    return readings.create(vehicleId: punto.id, date: date, km: km);
  }

  /// Matches an [InvalidFieldException] for [field] with [reason].
  Matcher invalid(String field, String reason) => throwsA(
        isA<InvalidFieldException>()
            .having((e) => e.field, 'field', field)
            .having((e) => e.reason, 'reason', reason),
      );

  /// Matches a [MileageReadingRuleException] for [rule].
  Matcher refusedBy(MileageReadingRule rule) => throwsA(
        isA<MileageReadingRuleException>().having((e) => e.rule, 'rule', rule),
      );

  group('initial reading', () {
    test('creating a vehicle adds one reading, today, with its km', () async {
      final list = await series();
      expect(list, hasLength(1));
      expect(list.single.km, 85000);
      expect(list.single.date, _today);
      expect(list.single.createdAt, punto.createdAt);
      expect((await readings.getLast(punto.id))?.id, list.single.id);
    });

    test('is audited as a reading create next to the vehicle create', () async {
      final reading = (await series()).single;
      final entries =
          await audit.getForEntity(AuditEntityType.mileageReading, reading.id);
      expect([for (final e in entries) e.operation], [AuditOperation.create]);
      expect(entries.single.at, punto.createdAt);
    });
  });

  group('create', () {
    test('adds the reading and moves the odometer', () async {
      final reading = await add(86250);
      expect((await series()).first, reading);
      expect(await odometer(), 86250);
      final entries =
          await audit.getForEntity(AuditEntityType.mileageReading, reading.id);
      expect([for (final e in entries) e.operation], [AuditOperation.create]);
    });

    test('accepts the same km as the last reading', () async {
      await add(85000);
      expect(await odometer(), 85000);
      expect(await series(), hasLength(2));
    });

    test('refuses km below the last reading', () async {
      await add(90000);
      expect(
        () => add(89999),
        invalid('km', InvalidFieldException.belowLastReading),
      );
      expect(await odometer(), 90000);
      expect(await series(), hasLength(2));
    });

    test('refuses a date before the last reading', () async {
      expect(
        () => add(90000, date: const CalendarDate(2026, 10, 18)),
        invalid('date', InvalidFieldException.beforeLastReading),
      );
      expect(await series(), hasLength(1));
    });

    test('refuses a date after today', () async {
      expect(
        () => add(90000, date: const CalendarDate(2026, 10, 20)),
        invalid('date', InvalidFieldException.inFuture),
      );
      expect(await odometer(), 85000);
    });

    test('accepts several readings on the same day, the newest last', () async {
      final first = await add(85100);
      final second = await add(85200);
      expect([for (final r in await series()) r.id].take(2), [
        second.id,
        first.id,
      ]);
      expect(await odometer(), 85200);
    });

    test('refuses a negative km', () async {
      expect(
        () => add(-1),
        throwsA(isA<InvalidFieldException>()),
      );
    });

    test('accepts a big jump: the form asks, the repository does not',
        () async {
      await add(85000 + bigOdometerJumpKm + 10000);
      expect(await odometer(), 145000);
    });

    test('refuses a deleted vehicle', () async {
      await vehicles.delete(punto.id);
      expect(
        () => add(90000),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });

  group('deleteLast', () {
    test('deletes the last reading and falls back to the previous km',
        () async {
      await add(86000);
      final last = await add(87000);
      await readings.deleteLast(last.id);
      expect([for (final r in await series()) r.km], [86000, 85000]);
      expect(await odometer(), 86000);
      final entries =
          await audit.getForEntity(AuditEntityType.mileageReading, last.id);
      expect(
        [for (final e in entries) e.operation],
        [AuditOperation.create, AuditOperation.delete],
      );
    });

    test('refuses a reading that is not the last', () async {
      final middle = await add(86000);
      await add(87000);
      expect(
        () => readings.deleteLast(middle.id),
        refusedBy(MileageReadingRule.notLast),
      );
      expect(await series(), hasLength(3));
      expect(await odometer(), 87000);
    });

    test('refuses the initial reading, even when it is the only one', () async {
      final initial = (await series()).single;
      expect(
        () => readings.deleteLast(initial.id),
        refusedBy(MileageReadingRule.initial),
      );
      await add(86000);
      expect(
        () => readings.deleteLast(initial.id),
        refusedBy(MileageReadingRule.notLast),
      );
    });

    test('lets the series be undone backwards down to the initial one',
        () async {
      final a = await add(86000);
      final b = await add(87000);
      await readings.deleteLast(b.id);
      await readings.deleteLast(a.id);
      expect([for (final r in await series()) r.km], [85000]);
      expect(await odometer(), 85000);
    });
  });

  group('restore', () {
    test('brings back the deleted last reading and its km', () async {
      final last = await add(86000);
      await readings.deleteLast(last.id);
      final restored = await readings.restore(last.id);
      expect(restored.km, 86000);
      expect((await series()).first.id, last.id);
      expect(await odometer(), 86000);
      final entries =
          await audit.getForEntity(AuditEntityType.mileageReading, last.id);
      expect(entries.last.operation, AuditOperation.restore);
    });

    test('is refused when a newer reading was added meanwhile', () async {
      final last = await add(86000);
      await readings.deleteLast(last.id);
      await add(86500);
      expect(
        () => readings.restore(last.id),
        refusedBy(MileageReadingRule.newerReadingExists),
      );
      expect([for (final r in await series()) r.km], [86500, 85000]);
      expect(await odometer(), 86500);
    });

    test('is refused when the vehicle was deleted meanwhile', () async {
      final last = await add(86000);
      await readings.deleteLast(last.id);
      await vehicles.delete(punto.id);
      expect(
        () => readings.restore(last.id),
        throwsA(
          isA<EntityNotFoundException>()
              .having((e) => e.entityType, 'type', AuditEntityType.vehicle),
        ),
      );
    });

    test('is refused for a reading that is not deleted', () async {
      final last = await add(86000);
      expect(
        () => readings.restore(last.id),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });

  group('updateInitial', () {
    test('corrects the sole reading and the odometer', () async {
      final initial = (await series()).single;
      clock.advance();
      final updated = await readings.updateInitial(
        initial.id,
        date: const CalendarDate(2026, 9, 1),
        km: 84000,
      );
      expect(updated.km, 84000);
      expect(updated.date, const CalendarDate(2026, 9, 1));
      expect((await series()).single, updated);
      expect(await odometer(), 84000);
      final entries =
          await audit.getForEntity(AuditEntityType.mileageReading, initial.id);
      expect(entries.last.operation, AuditOperation.update);
    });

    test('is refused once the vehicle has a second reading', () async {
      final initial = (await series()).single;
      await add(86000);
      expect(
        () => readings.updateInitial(initial.id, date: _today, km: 1),
        refusedBy(MileageReadingRule.notSoleReading),
      );
      expect(await odometer(), 86000);
    });

    test('refuses a future date', () async {
      final initial = (await series()).single;
      expect(
        () => readings.updateInitial(
          initial.id,
          date: const CalendarDate(2026, 10, 20),
          km: 1,
        ),
        invalid('date', InvalidFieldException.inFuture),
      );
    });
  });

  group('deleted vehicle', () {
    test('hides its readings and keeps them for a restore', () async {
      await add(86000);
      await vehicles.delete(punto.id);
      expect(await series(), isEmpty);
      expect(await readings.getLast(punto.id), isNull);
      await vehicles.restore(punto.id);
      expect([for (final r in await series()) r.km], [86000, 85000]);
    });
  });

  group('odometer cache', () {
    test('always equals the km of the last reading', () async {
      Future<void> expectInvariant() async {
        expect(await odometer(), (await series()).first.km);
      }

      await expectInvariant();
      final a = await add(86000);
      await expectInvariant();
      final b = await add(90000);
      await expectInvariant();
      await readings.deleteLast(b.id);
      await expectInvariant();
      await readings.restore(b.id);
      await expectInvariant();
      await readings.deleteLast(b.id);
      await readings.deleteLast(a.id);
      await expectInvariant();
      final initial = (await series()).single;
      await readings.updateInitial(initial.id, date: _today, km: 70000);
      await expectInvariant();
    });

    test('is not touched by a history entry with a higher km', () async {
      final entries = DriftLogEntryRepository(
        db.logEntriesDao,
        db.auditLogDao,
        attachments: attachmentWriterOf(db),
        clock: clock.call,
      );
      await entries.create(
        vehicleId: punto.id,
        date: _today,
        km: 99000,
        type: LogEntryType.maintenance,
      );
      expect(await odometer(), 85000);
      expect(await series(), hasLength(1));
    });
  });
}
