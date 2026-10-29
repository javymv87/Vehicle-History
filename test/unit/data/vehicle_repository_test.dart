import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/owner.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/drift_owner_repository.dart';
import 'package:vehicle_history/data/repositories/drift_mileage_reading_repository.dart';
import 'package:vehicle_history/data/repositories/drift_vehicle_repository.dart';
import 'package:vehicle_history/data/repositories/repository_exceptions.dart';

import 'test_support.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late DriftOwnerRepository owners;
  late DriftVehicleRepository vehicles;
  late Owner mario;

  setUp(() async {
    db = openTestDatabase();
    clock = FakeClock();
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
      attachmentFiles: MemoryAttachmentStore(),
      clock: clock.call,
    );
    mario = await owners.create(firstName: 'Mario');
  });

  tearDown(() => db.close());

  /// Creates a vehicle for [mario] with sensible defaults.
  Future<Vehicle> createVehicle({
    String plate = 'AB123CD',
    String? ownerId,
    double km = 85000,
  }) {
    return vehicles.create(
      plate: plate,
      kind: VehicleKind.car,
      ownerId: ownerId ?? mario.id,
      currentOdometerKm: km,
      fuelType: FuelType.petrolLpg,
    );
  }

  group('create', () {
    test('stores the plate trimmed and upper-case', () async {
      final vehicle = await vehicles.create(
        plate: '  ab 123 cd ',
        kind: VehicleKind.car,
        nickname: ' Punto ',
        ownerId: mario.id,
        currentOdometerKm: 85000,
        fuelType: FuelType.petrolLpg,
        recommendedEngineOil: '',
      );

      expect(vehicle.plate, 'AB 123 CD');
      expect(vehicle.nickname, 'Punto');
      expect(vehicle.recommendedEngineOil, isNull);
      expect(vehicle.createdAt, clock());
      expect(await vehicles.getById(vehicle.id), vehicle);
    });

    test('round-trips every fuel type', () async {
      for (final (i, type) in FuelType.values.indexed) {
        final v = await vehicles.create(
          plate: 'P$i',
          kind: VehicleKind.car,
          ownerId: mario.id,
          currentOdometerKm: 0,
          fuelType: type,
        );
        expect((await vehicles.getById(v.id))!.fuelType, type);
      }
    });

    test('refuses a blank plate', () async {
      await expectLater(
        createVehicle(plate: '  '),
        throwsA(isA<InvalidFieldException>()),
      );
    });

    test('refuses a negative odometer', () async {
      await expectLater(
        createVehicle(km: -1),
        throwsA(
          isA<InvalidFieldException>()
              .having((e) => e.field, 'field', 'currentOdometerKm'),
        ),
      );
      expect(await vehicles.getActive(), isEmpty);
    });

    test('refuses a plate already used by a live vehicle', () async {
      await createVehicle(plate: 'AB123CD');
      await expectLater(
        createVehicle(plate: ' ab123cd'),
        throwsA(
          isA<DuplicatePlateException>()
              .having((e) => e.plate, 'plate', 'AB123CD'),
        ),
      );
      expect(await vehicles.getActive(), hasLength(1));
    });

    test('allows reusing the plate of a deleted vehicle', () async {
      final old = await createVehicle(plate: 'AB123CD');
      await vehicles.delete(old.id);

      final reused = await createVehicle(plate: 'AB123CD');
      expect(reused.plate, 'AB123CD');
    });

    test('refuses an unknown owner', () async {
      await expectLater(
        createVehicle(ownerId: 'missing'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('refuses a deleted owner', () async {
      final luigi = await owners.create(firstName: 'Luigi');
      await owners.delete(luigi.id);
      await expectLater(
        createVehicle(ownerId: luigi.id),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });

  group('update', () {
    test('replaces editable fields but never the odometer', () async {
      final created = await vehicles.create(
        plate: 'AB123CD',
        kind: VehicleKind.car,
        nickname: 'Punto',
        ownerId: mario.id,
        currentOdometerKm: 85000,
        fuelType: FuelType.petrol,
      );
      clock.advance();

      final updated = await vehicles.update(
        created.id,
        plate: 'zz999zz',
        kind: VehicleKind.car,
        ownerId: mario.id,
        fuelType: FuelType.diesel,
      );

      expect(updated.plate, 'ZZ999ZZ');
      expect(updated.nickname, isNull);
      expect(updated.fuelType, FuelType.diesel);
      expect(updated.currentOdometerKm, 85000);
      expect(updated.createdAt, created.createdAt);
      expect(updated.updatedAt, clock());
      expect(await vehicles.getById(created.id), updated);
    });

    test('keeping its own plate is not a duplicate', () async {
      final v = await createVehicle(plate: 'AB123CD');
      final updated = await vehicles.update(
        v.id,
        plate: 'ab123cd',
        kind: VehicleKind.car,
        ownerId: mario.id,
        fuelType: FuelType.petrol,
      );
      expect(updated.plate, 'AB123CD');
    });

    test('taking another live vehicle\'s plate is refused', () async {
      await createVehicle(plate: 'AB123CD');
      final other = await createVehicle(plate: 'XY987ZW');
      await expectLater(
        vehicles.update(
          other.id,
          plate: 'AB123CD',
          kind: VehicleKind.car,
          ownerId: mario.id,
          fuelType: FuelType.petrol,
        ),
        throwsA(isA<DuplicatePlateException>()),
      );
    });

    test('can move the vehicle to another owner', () async {
      final luigi = await owners.create(firstName: 'Luigi');
      final v = await createVehicle();
      await vehicles.update(
        v.id,
        plate: 'AB123CD',
        kind: VehicleKind.car,
        ownerId: luigi.id,
        fuelType: FuelType.petrol,
      );
      expect(await vehicles.getByOwner(mario.id), isEmpty);
      expect(await vehicles.getByOwner(luigi.id), hasLength(1));
    });

    test('a missing or deleted vehicle throws EntityNotFoundException',
        () async {
      final v = await createVehicle();
      await vehicles.delete(v.id);
      for (final id in ['missing', v.id]) {
        await expectLater(
          vehicles.update(
            id,
            plate: 'AB123CD',
            kind: VehicleKind.car,
            ownerId: mario.id,
            fuelType: FuelType.petrol,
          ),
          throwsA(isA<EntityNotFoundException>()),
        );
      }
    });
  });

  group('delete', () {
    test('hides the vehicle from every read', () async {
      final v = await createVehicle();
      await vehicles.delete(v.id);

      expect(await vehicles.getById(v.id), isNull);
      expect(await vehicles.getActive(), isEmpty);
      expect(await vehicles.getByOwner(mario.id), isEmpty);
    });

    test('a missing or already deleted vehicle throws', () async {
      final v = await createVehicle();
      await vehicles.delete(v.id);
      await expectLater(
        vehicles.delete(v.id),
        throwsA(isA<EntityNotFoundException>()),
      );
      await expectLater(
        vehicles.delete('missing'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });
  });

  group('reads', () {
    test('getAll is ordered by plate; getByOwner filters by owner', () async {
      final luigi = await owners.create(firstName: 'Luigi');
      await createVehicle(plate: 'ZZ000AA');
      await createVehicle(plate: 'AA000AA');
      await createVehicle(plate: 'MM000AA', ownerId: luigi.id);

      expect(
        [for (final v in await vehicles.getActive()) v.plate],
        ['AA000AA', 'MM000AA', 'ZZ000AA'],
      );
      expect(
        [for (final v in await vehicles.getByOwner(mario.id)) v.plate],
        ['AA000AA', 'ZZ000AA'],
      );
    });

    test('watchByOwner emits on create and delete', () async {
      final plates = vehicles
          .watchByOwner(mario.id)
          .map((list) => [for (final v in list) v.plate]);
      final expectation = expectLater(
        plates,
        emitsInOrder([
          <String>[],
          ['AB123CD'],
          <String>[],
        ]),
      );

      await pumpEventQueue();
      final v = await createVehicle();
      await pumpEventQueue();
      await vehicles.delete(v.id);

      await expectation;
    });
  });

  group('kind, make and model', () {
    test('create stores names, slugs, year and version, trimmed', () async {
      final vehicle = await vehicles.create(
        plate: 'AB123CD',
        kind: VehicleKind.motorcycle,
        make: ' Honda ',
        makeSlug: 'honda',
        model: ' SH125 ',
        modelSlug: 'sh125',
        modelYear: 2019,
        version: ' ABS ',
        ownerId: mario.id,
        currentOdometerKm: 0,
        fuelType: FuelType.petrol,
      );

      expect(vehicle.kind, VehicleKind.motorcycle);
      expect(vehicle.make, 'Honda');
      expect(vehicle.makeSlug, 'honda');
      expect(vehicle.model, 'SH125');
      expect(vehicle.modelSlug, 'sh125');
      expect(vehicle.modelYear, 2019);
      expect(vehicle.version, 'ABS');
      expect(vehicle.makeAndModel, 'Honda SH125');
      expect(await vehicles.getById(vehicle.id), vehicle);

      final raw = await db.customSelect(
        'SELECT kind FROM vehicles WHERE id = ?',
        variables: [Variable.withString(vehicle.id)],
      ).getSingle();
      expect(raw.read<String>('kind'), 'motorcycle');
    });

    test('a make and model typed by hand have no slug', () async {
      final vehicle = await vehicles.create(
        plate: 'AB123CD',
        kind: VehicleKind.car,
        make: 'Zastava',
        model: 'Yugo 45',
        version: '   ',
        ownerId: mario.id,
        currentOdometerKm: 0,
        fuelType: FuelType.petrol,
      );
      final stored = await vehicles.getById(vehicle.id);
      expect(stored!.make, 'Zastava');
      expect(stored.makeSlug, isNull);
      expect(stored.model, 'Yugo 45');
      expect(stored.modelSlug, isNull);
      expect(stored.version, isNull);
    });

    test('update replaces kind, make and model, and can clear them', () async {
      final v = await vehicles.create(
        plate: 'AB123CD',
        kind: VehicleKind.car,
        make: 'Fiat',
        makeSlug: 'fiat',
        model: 'Punto',
        modelSlug: 'punto',
        modelYear: 2012,
        ownerId: mario.id,
        currentOdometerKm: 0,
        fuelType: FuelType.petrol,
      );
      final updated = await vehicles.update(
        v.id,
        plate: 'AB123CD',
        kind: VehicleKind.van,
        make: 'Fiat',
        makeSlug: 'fiat',
        model: 'Ducato',
        modelSlug: 'ducato',
        ownerId: mario.id,
        fuelType: FuelType.diesel,
      );
      expect(updated.kind, VehicleKind.van);
      expect(updated.modelSlug, 'ducato');
      expect(updated.modelYear, isNull);
      expect(await vehicles.getById(v.id), updated);
    });

    test('refuses a model year outside 1886 to 2100', () async {
      for (final year in [1885, 2101]) {
        await expectLater(
          vehicles.create(
            plate: 'AB123CD',
            kind: VehicleKind.car,
            modelYear: year,
            ownerId: mario.id,
            currentOdometerKm: 0,
            fuelType: FuelType.petrol,
          ),
          throwsA(
            isA<InvalidFieldException>()
                .having((e) => e.field, 'field', 'modelYear'),
          ),
        );
      }
      expect(await vehicles.getActive(), isEmpty);
    });

    test('refuses a slug without its name', () async {
      await expectLater(
        vehicles.create(
          plate: 'AB123CD',
          kind: VehicleKind.car,
          makeSlug: 'fiat',
          ownerId: mario.id,
          currentOdometerKm: 0,
          fuelType: FuelType.petrol,
        ),
        throwsA(
          isA<InvalidFieldException>()
              .having((e) => e.field, 'field', 'makeSlug'),
        ),
      );
    });
  });
}
