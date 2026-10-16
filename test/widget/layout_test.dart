import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';

import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

/// Every screen must fit a 360 dp wide phone with very large system text,
/// in light and dark mode. A layout overflow fails the test.
void main() {
  late FakeStore store;
  late String ownerId;
  late String vehicleId;

  setUp(() {
    store = FakeStore();
    ownerId = store
        .addOwner('Maria Antonietta', lastName: 'Fernández de la Fuente')
        .id;
    vehicleId = store
        .addVehicle(
          'AB123CD',
          ownerId: ownerId,
          km: 1234567,
          fuelType: FuelType.pluginHybrid,
          nickname: 'The family car for long trips',
        )
        .id;
  });

  final locations = <String, String Function()>{
    'vehicle list': () => AppRoutes.vehicles,
    'vehicle detail': () => AppRoutes.vehicle(vehicleId),
    'vehicle form': () => AppRoutes.newVehicle,
    'vehicle edit': () => AppRoutes.editVehicle(vehicleId),
    'owner list': () => AppRoutes.owners,
    'owner detail': () => AppRoutes.owner(ownerId),
    'owner form': () => AppRoutes.newOwner,
  };

  for (final brightness in Brightness.values) {
    for (final MapEntry(key: name, value: location) in locations.entries) {
      testWidgets('$name fits 360 dp with 2x text (${brightness.name})',
          (tester) async {
        tester.view
          ..physicalSize = const Size(360, 720)
          ..devicePixelRatio = 1;
        tester.platformDispatcher
          ..textScaleFactorTestValue = 2
          ..platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);

        await pumpApp(
          tester,
          store,
          location: location(),
          locale: const Locale('it'),
        );

        expect(tester.takeException(), isNull);
      });
    }
  }
}
