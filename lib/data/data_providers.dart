import 'package:flutter_riverpod/flutter_riverpod.dart';

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
