import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'catalog/country_names.dart';
import 'catalog/vehicle_catalog.dart';
import 'db/app_database.dart';
import 'repositories/drift_owner_repository.dart';
import 'repositories/drift_vehicle_repository.dart';
import 'repositories/owner_repository.dart';
import 'repositories/vehicle_repository.dart';

/// The single [AppDatabase] of the app, opened once and closed when the
/// [ProviderScope] is disposed.
///
/// Tests override it with an in-memory database, or override the repository
/// providers below with fakes.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Completes once the database is open and any pending migration has run.
///
/// Fails with the error that stopped it, such as
/// `DatabaseNewerThanAppException`; the app then shows the startup error
/// screen instead of the router. Never retried automatically: a refused or
/// failed upgrade does not fix itself, and retrying would only repeat it.
final databaseReadyProvider = FutureProvider<void>(
  (ref) => ref.watch(appDatabaseProvider).open(),
  retry: (retryCount, error) => null,
);

/// The [OwnerRepository] on the app database.
final ownerRepositoryProvider = Provider<OwnerRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DriftOwnerRepository(db.ownersDao, db.auditLogDao);
});

/// The [VehicleRepository] on the app database.
final vehicleRepositoryProvider = Provider<VehicleRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DriftVehicleRepository(db.vehiclesDao, db.auditLogDao);
});

/// Asset holding the make / model catalogue (see `tool/`).
const String vehicleCatalogAsset = 'assets/catalog/vehicle_catalog.json';

/// Asset holding the country names (see `tool/`).
const String countryNamesAsset = 'assets/countries/country_names.json';

/// The bundled make / model catalogue, loaded once on first use and kept
/// for the life of the app. Tests override it with a small fixture.
final vehicleCatalogProvider = FutureProvider<VehicleCatalog>(
  (ref) async =>
      VehicleCatalog.fromJson(await rootBundle.loadString(vehicleCatalogAsset)),
);

/// The bundled country names, loaded once on first use and kept for the
/// life of the app. Tests override it with a small fixture.
final countryNamesProvider = FutureProvider<CountryNames>(
  (ref) async =>
      CountryNames.fromJson(await rootBundle.loadString(countryNamesAsset)),
);
