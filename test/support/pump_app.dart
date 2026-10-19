import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/app.dart';
import 'package:vehicle_history/app/router/app_router.dart';
import 'package:vehicle_history/data/data_providers.dart';

import 'catalog_fixtures.dart';
import 'fake_repositories.dart';

/// Provider overrides that run the app on [store] instead of a database.
List<Override> fakeDataOverrides(FakeStore store) => [
      databaseReadyProvider.overrideWith((ref) async {}),
      ownerRepositoryProvider.overrideWithValue(FakeOwnerRepository(store)),
      vehicleRepositoryProvider.overrideWithValue(FakeVehicleRepository(store)),
      logEntryRepositoryProvider
          .overrideWithValue(FakeLogEntryRepository(store)),
      vehicleCatalogProvider
          .overrideWith((ref) async => vehicleCatalogFixture()),
      countryNamesProvider.overrideWith((ref) async => countryNamesFixture()),
    ];

/// Pumps the whole app on [store], starting at [location], in English.
///
/// Returns the [ProviderContainer] so tests can inspect the router.
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  FakeStore store, {
  String location = '/vehicles',
  Locale locale = const Locale('en'),
}) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final container = ProviderContainer(
    overrides: [
      ...fakeDataOverrides(store),
      routerProvider.overrideWith((ref) {
        final router = buildAppRouter(initialLocation: location);
        ref.onDispose(router.dispose);
        return router;
      }),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const VehicleHistoryApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
