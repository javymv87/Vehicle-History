import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/owner.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/features/owners/controllers/owner_deletion_controller.dart';
import 'package:vehicle_history/features/owners/controllers/owner_detail_controller.dart';
import 'package:vehicle_history/features/owners/controllers/owner_form_controller.dart';
import 'package:vehicle_history/features/vehicles/controllers/vehicle_deletion_controller.dart';
import 'package:vehicle_history/features/vehicles/controllers/vehicle_detail_controller.dart';
import 'package:vehicle_history/features/vehicles/controllers/vehicle_form_controller.dart';
import 'package:vehicle_history/features/vehicles/controllers/vehicle_list_controller.dart';
import 'package:vehicle_history/shared/utils/action_result.dart';

import '../support/catalog_fixtures.dart';
import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

void main() {
  late FakeStore store;
  late ProviderContainer container;

  setUp(() {
    store = FakeStore();
    container = ProviderContainer(overrides: fakeDataOverrides(store));
  });

  tearDown(() => container.dispose());

  /// Reads [provider] once its value is available, keeping it alive.
  Future<T> readAsync<T>(ProviderListenable<AsyncValue<T>> provider) async {
    final sub = container.listen(provider, (_, __) {});
    addTearDown(sub.close);
    while (!container.read(provider).hasValue &&
        !container.read(provider).hasError) {
      await Future<void>.delayed(Duration.zero);
    }
    return container.read(provider).requireValue;
  }

  group('OwnerFormController', () {
    test('creates an owner from a draft', () async {
      final form = ownerFormControllerProvider(null);
      expect(await readAsync(form), isNull);

      final result = await container.read(form.notifier).save(
            const OwnerDraft(
              firstName: ' Mario ',
              lastName: 'Rossi',
              birthDate: CalendarDate(1980, 2, 29),
              phone: '  ',
            ),
          );

      final owner = (result as ActionSuccess<Owner>).value;
      expect(owner.firstName, 'Mario');
      expect(owner.birthDate, const CalendarDate(1980, 2, 29));
      expect(owner.phone, isNull);
      expect(store.liveOwners, [owner]);
    });

    test('loads the owner being edited and updates it', () async {
      final existing = store.addOwner('Mario');
      final form = ownerFormControllerProvider(existing.id);
      expect(await readAsync(form), existing);

      final result = await container
          .read(form.notifier)
          .save(const OwnerDraft(firstName: 'Luigi', email: 'l@example.com'));

      expect(result, isA<ActionSuccess<Owner>>());
      expect(store.owners[existing.id]!.firstName, 'Luigi');
      expect(store.owners[existing.id]!.email, 'l@example.com');
    });

    test('loads null for an unknown id', () async {
      expect(await readAsync(ownerFormControllerProvider('missing')), isNull);
    });

    test('maps a failed write to unexpected', () async {
      store.failWritesWith = Exception('disk full');
      final form = ownerFormControllerProvider(null);
      await readAsync(form);

      final result = await container
          .read(form.notifier)
          .save(const OwnerDraft(firstName: 'Mario'));

      expect(
        result,
        isA<ActionFailure<Owner>>()
            .having((f) => f.error, 'error', ActionError.unexpected),
      );
    });
  });

  group('OwnerDeletionController', () {
    test('deletes, remembers the id and undoes', () async {
      final owner = store.addOwner('Mario');
      final deletion = container.read(ownerDeletionControllerProvider.notifier);

      expect(await deletion.delete(owner.id), isA<ActionSuccess<void>>());
      expect(container.read(ownerDeletionControllerProvider), owner.id);
      expect(store.liveOwners, isEmpty);

      expect(await deletion.undo(owner.id), isA<ActionSuccess<Owner>>());
      expect(container.read(ownerDeletionControllerProvider), isNull);
      expect(store.liveOwners, [owner]);
    });

    test('refuses an owner with vehicles and deletes nothing', () async {
      final owner = store.addOwner('Mario');
      store.addVehicle('AB123CD', ownerId: owner.id);

      final result = await container
          .read(ownerDeletionControllerProvider.notifier)
          .delete(owner.id);

      expect(
        result,
        isA<ActionFailure<void>>()
            .having((f) => f.error, 'error', ActionError.ownerHasVehicles),
      );
      expect(container.read(ownerDeletionControllerProvider), isNull);
      expect(store.liveOwners, [owner]);
    });
  });

  group('ownerDetailProvider', () {
    test('combines the owner with their vehicles', () async {
      final owner = store.addOwner('Mario');
      final vehicle = store.addVehicle('AB123CD', ownerId: owner.id);
      store.addVehicle('ZZ999ZZ', ownerId: store.addOwner('Other').id);

      final detail = await readAsync(ownerDetailProvider(owner.id));

      expect(detail!.owner, owner);
      expect(detail.vehicles, [vehicle]);
    });

    test('is null for an unknown id', () async {
      expect(await readAsync(ownerDetailProvider('missing')), isNull);
    });
  });

  group('VehicleFormController', () {
    late Owner owner;

    setUp(() => owner = store.addOwner('Mario'));

    VehicleDraft draft(
      String plate, {
      double? km = 1000,
      VehicleIdentity identity = const VehicleIdentity(
        kind: VehicleKind.car,
        make: 'Fiat',
        makeSlug: 'fiat',
        model: 'Punto',
        modelSlug: 'punto',
      ),
    }) =>
        VehicleDraft(
          plate: plate,
          identity: identity,
          ownerId: owner.id,
          fuelType: FuelType.diesel,
          currentOdometerKm: km,
        );

    test('creates a vehicle with its km', () async {
      final form = vehicleFormControllerProvider(null);
      await readAsync(form);

      final result =
          await container.read(form.notifier).save(draft('ab 123', km: 0));

      final vehicle = (result as ActionSuccess<Vehicle>).value;
      expect(vehicle.plate, 'AB 123');
      expect(vehicle.currentOdometerKm, 0);
    });

    test('saves catalogue names with their slugs', () async {
      final form = vehicleFormControllerProvider(null);
      await readAsync(form);
      final catalog = vehicleCatalogFixture();
      final identity = VehicleIdentity.of(null)
          .withKind(VehicleKind.motorcycle)
          .withCatalogMake(catalog.make(VehicleKind.motorcycle, 'honda')!)
          .withCatalogModel(
            catalog.models(VehicleKind.motorcycle, 'honda').first,
          );

      final result = await container
          .read(form.notifier)
          .save(draft('AB12345', identity: identity));

      final vehicle = (result as ActionSuccess<Vehicle>).value;
      expect(vehicle.kind, VehicleKind.motorcycle);
      expect((vehicle.make, vehicle.makeSlug), ('Honda', 'honda'));
      expect((vehicle.model, vehicle.modelSlug), ('CB500', 'cb500'));
    });

    test('saves a custom make and model without slugs', () async {
      final form = vehicleFormControllerProvider(null);
      await readAsync(form);
      final identity = VehicleIdentity.of(null)
          .withCustomMake(' Zastava ')
          .withCustomModel('Yugo 45 ');

      final result = await container
          .read(form.notifier)
          .save(draft('AB123CD', identity: identity));

      final vehicle = (result as ActionSuccess<Vehicle>).value;
      expect((vehicle.make, vehicle.makeSlug), ('Zastava', null));
      expect((vehicle.model, vehicle.modelSlug), ('Yugo 45', null));
    });

    test('saves a custom model of a catalogue make', () async {
      final form = vehicleFormControllerProvider(null);
      await readAsync(form);
      final fiat = vehicleCatalogFixture().make(VehicleKind.car, 'fiat')!;
      final identity = VehicleIdentity.of(null)
          .withCatalogMake(fiat)
          .withCustomModel('Ritmo');

      final result = await container
          .read(form.notifier)
          .save(draft('AB123CD', identity: identity));

      final vehicle = (result as ActionSuccess<Vehicle>).value;
      expect((vehicle.make, vehicle.makeSlug), ('Fiat', 'fiat'));
      expect((vehicle.model, vehicle.modelSlug), ('Ritmo', null));
    });

    test('maps a duplicate plate', () async {
      store.addVehicle('AB123CD', ownerId: owner.id);
      final form = vehicleFormControllerProvider(null);
      await readAsync(form);

      final result = await container.read(form.notifier).save(draft('ab123cd'));

      expect(
        result,
        isA<ActionFailure<Vehicle>>()
            .having((f) => f.error, 'error', ActionError.duplicatePlate),
      );
      expect(store.liveVehicles, hasLength(1));
    });

    test('updates without touching the km', () async {
      final existing = store.addVehicle('AB123CD', ownerId: owner.id, km: 500);
      final form = vehicleFormControllerProvider(existing.id);
      expect(await readAsync(form), existing);

      final result =
          await container.read(form.notifier).save(draft('XY987ZW', km: null));

      final updated = (result as ActionSuccess<Vehicle>).value;
      expect(updated.plate, 'XY987ZW');
      expect(updated.currentOdometerKm, 500);
    });

    test('maps a deleted owner', () async {
      final form = vehicleFormControllerProvider(null);
      await readAsync(form);
      store.deletedOwners.add(owner.id);

      final result = await container.read(form.notifier).save(draft('AB1'));

      expect(
        result,
        isA<ActionFailure<Vehicle>>()
            .having((f) => f.error, 'error', ActionError.ownerNotFound),
      );
    });
  });

  group('VehicleDeletionController', () {
    test('deletes and undoes', () async {
      final owner = store.addOwner('Mario');
      final vehicle = store.addVehicle('AB123CD', ownerId: owner.id);
      final deletion =
          container.read(vehicleDeletionControllerProvider.notifier);

      expect(await deletion.delete(vehicle.id), isA<ActionSuccess<void>>());
      expect(container.read(vehicleDeletionControllerProvider), vehicle.id);
      expect(store.liveVehicles, isEmpty);

      expect(await deletion.undo(vehicle.id), isA<ActionSuccess<Vehicle>>());
      expect(container.read(vehicleDeletionControllerProvider), isNull);
      expect(store.liveVehicles, [vehicle]);
    });

    test('undo reports a plate reused meanwhile', () async {
      final owner = store.addOwner('Mario');
      final vehicle = store.addVehicle('AB123CD', ownerId: owner.id);
      final deletion =
          container.read(vehicleDeletionControllerProvider.notifier);
      await deletion.delete(vehicle.id);
      store.addVehicle('AB123CD', ownerId: owner.id);

      final result = await deletion.undo(vehicle.id);

      expect(
        result,
        isA<ActionFailure<Vehicle>>()
            .having((f) => f.error, 'error', ActionError.duplicatePlate),
      );
    });
  });

  group('vehicle list and detail', () {
    test('pairs each vehicle with its owner, ordered by plate', () async {
      final mario = store.addOwner('Mario');
      final anna = store.addOwner('Anna');
      store.addVehicle('ZZ1', ownerId: mario.id);
      store.addVehicle('AA1', ownerId: anna.id);

      final items = await readAsync(vehicleListProvider);

      expect([for (final i in items) i.vehicle.plate], ['AA1', 'ZZ1']);
      expect([for (final i in items) i.owner], [anna, mario]);
    });

    test('detail is null for an unknown id', () async {
      expect(await readAsync(vehicleDetailProvider('missing')), isNull);
    });
  });

  group('VehicleIdentity', () {
    final catalog = vehicleCatalogFixture();
    final fiat = catalog.make(VehicleKind.car, 'fiat')!;
    final honda = catalog.make(VehicleKind.car, 'honda')!;
    final punto = catalog.models(VehicleKind.car, 'fiat').first;

    test('starts as an empty car when creating', () {
      expect(
        VehicleIdentity.of(null),
        const VehicleIdentity(kind: VehicleKind.car),
      );
    });

    test('changing the kind clears make and model', () {
      final chosen = VehicleIdentity.of(null)
          .withCatalogMake(fiat)
          .withCatalogModel(punto);
      expect(chosen.withKind(VehicleKind.car), chosen);
      expect(
        chosen.withKind(VehicleKind.van),
        const VehicleIdentity(kind: VehicleKind.van),
      );
    });

    test('changing the make clears the model; the same make keeps it', () {
      final chosen = VehicleIdentity.of(null)
          .withCatalogMake(fiat)
          .withCatalogModel(punto);
      expect(chosen.withCatalogMake(fiat), chosen);
      final other = chosen.withCatalogMake(honda);
      expect((other.make, other.makeSlug), ('Honda', 'honda'));
      expect((other.model, other.modelSlug), (null, null));
      final custom = chosen.withCustomMake('Zastava');
      expect((custom.make, custom.makeSlug), ('Zastava', null));
      expect(custom.model, isNull);
      expect(custom.hasCatalogMake, isFalse);
    });

    test('a typed model drops the catalogue slug; blank clears it', () {
      final chosen = VehicleIdentity.of(null)
          .withCatalogMake(fiat)
          .withCatalogModel(punto);
      final typed = chosen.withCustomModel(' Ritmo ');
      expect((typed.model, typed.modelSlug), ('Ritmo', null));
      expect(typed.makeSlug, 'fiat');
      expect(typed.withCustomModel('  ').model, isNull);
    });

    test('reads the identity of a stored vehicle', () {
      final vehicle = FakeStore().addVehicle(
        'AB123CD',
        ownerId: 'owner',
        kind: VehicleKind.moped,
        make: 'Piaggio',
        makeSlug: 'piaggio',
        model: 'Liberty',
        modelSlug: 'liberty',
      );
      expect(
        VehicleIdentity.of(vehicle),
        const VehicleIdentity(
          kind: VehicleKind.moped,
          make: 'Piaggio',
          makeSlug: 'piaggio',
          model: 'Liberty',
          modelSlug: 'liberty',
        ),
      );
    });
  });
}
