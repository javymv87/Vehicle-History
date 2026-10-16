import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/owner.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/features/owners/controllers/owner_deletion_controller.dart';
import 'package:vehicle_history/features/owners/controllers/owner_detail_controller.dart';
import 'package:vehicle_history/features/owners/controllers/owner_form_controller.dart';
import 'package:vehicle_history/features/vehicles/controllers/vehicle_deletion_controller.dart';
import 'package:vehicle_history/features/vehicles/controllers/vehicle_detail_controller.dart';
import 'package:vehicle_history/features/vehicles/controllers/vehicle_form_controller.dart';
import 'package:vehicle_history/features/vehicles/controllers/vehicle_list_controller.dart';
import 'package:vehicle_history/shared/utils/action_result.dart';

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

    VehicleDraft draft(String plate, {int? km = 1000}) => VehicleDraft(
          plate: plate,
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
}
