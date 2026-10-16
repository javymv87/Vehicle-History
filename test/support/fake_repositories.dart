import 'dart:async';

import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/owner.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/owner_repository.dart';
import 'package:vehicle_history/data/repositories/repository_exceptions.dart';
import 'package:vehicle_history/data/repositories/vehicle_repository.dart';

/// In-memory data shared by [FakeOwnerRepository] and
/// [FakeVehicleRepository], so that rules spanning both (an owner with
/// vehicles cannot be deleted) behave as with the real database.
///
/// Mirrors the repository contracts closely enough for controller and widget
/// tests; the real rules are tested against Drift in `test/unit/data/`.
class FakeStore {
  /// Live and deleted owners, by id.
  final Map<String, Owner> owners = {};

  /// Ids of soft-deleted owners.
  final Set<String> deletedOwners = {};

  /// Live and deleted vehicles, by id.
  final Map<String, Vehicle> vehicles = {};

  /// Ids of soft-deleted vehicles.
  final Set<String> deletedVehicles = {};

  /// When set, every write throws it instead of writing.
  Exception? failWritesWith;

  final StreamController<void> _changes = StreamController.broadcast();
  int _nextId = 1;
  final DateTime _now = DateTime.utc(2024, 3, 4, 10, 30);

  /// A new, readable, unique id.
  String newId(String prefix) => '$prefix-${_nextId++}';

  /// Live owners ordered by name, like the real DAO.
  List<Owner> get liveOwners => [
        for (final o in owners.values)
          if (!deletedOwners.contains(o.id)) o,
      ]..sort((a, b) => a.fullName.compareTo(b.fullName));

  /// Live vehicles ordered by plate, like the real DAO.
  List<Vehicle> get liveVehicles => [
        for (final v in vehicles.values)
          if (!deletedVehicles.contains(v.id)) v,
      ]..sort((a, b) => a.plate.compareTo(b.plate));

  /// Emits [read] now and after every change.
  Stream<T> watch<T>(T Function() read) => Stream.multi((controller) {
        controller.add(read());
        final sub = _changes.stream.listen((_) => controller.add(read()));
        controller.onCancel = sub.cancel;
      });

  /// Runs a write, failing first if [failWritesWith] is set, then notifies
  /// the watchers.
  Future<T> write<T>(T Function() body) async {
    final failure = failWritesWith;
    if (failure != null) throw failure;
    final result = body();
    _changes.add(null);
    return result;
  }

  /// The fixed instant used for every timestamp.
  DateTime get now => _now;

  /// Adds a live owner directly, for test setup.
  Owner addOwner(String firstName, {String? lastName, String? nationality}) {
    final owner = Owner(
      id: newId('owner'),
      firstName: firstName,
      lastName: lastName,
      nationality: nationality,
      createdAt: _now,
      updatedAt: _now,
    );
    owners[owner.id] = owner;
    _changes.add(null);
    return owner;
  }

  /// Adds a live vehicle directly, for test setup.
  Vehicle addVehicle(
    String plate, {
    required String ownerId,
    int km = 1000,
    FuelType fuelType = FuelType.petrol,
    String? nickname,
    VehicleKind kind = VehicleKind.car,
    String? make,
    String? makeSlug,
    String? model,
    String? modelSlug,
  }) {
    final vehicle = Vehicle(
      id: newId('vehicle'),
      plate: plate,
      kind: kind,
      make: make,
      makeSlug: makeSlug,
      model: model,
      modelSlug: modelSlug,
      nickname: nickname,
      ownerId: ownerId,
      currentOdometerKm: km,
      fuelType: fuelType,
      createdAt: _now,
      updatedAt: _now,
    );
    vehicles[vehicle.id] = vehicle;
    _changes.add(null);
    return vehicle;
  }
}

/// [OwnerRepository] on a [FakeStore].
class FakeOwnerRepository implements OwnerRepository {
  /// Creates the repository on [store].
  FakeOwnerRepository(this.store);

  /// The shared data.
  final FakeStore store;

  @override
  Stream<List<Owner>> watchAll() => store.watch(() => store.liveOwners);

  @override
  Future<List<Owner>> getAll() async => store.liveOwners;

  @override
  Future<Owner?> getById(String id) async =>
      store.deletedOwners.contains(id) ? null : store.owners[id];

  @override
  Future<Owner> create({
    required String firstName,
    String? lastName,
    CalendarDate? birthDate,
    String? nationality,
    String? phone,
    String? email,
    String? notes,
    String? photoPath,
  }) =>
      store.write(() {
        if (firstName.trim().isEmpty) {
          throw const InvalidFieldException('firstName', 'must not be blank');
        }
        final owner = Owner(
          id: store.newId('owner'),
          firstName: firstName.trim(),
          lastName: _clean(lastName),
          birthDate: birthDate,
          nationality: _clean(nationality),
          phone: _clean(phone),
          email: _clean(email),
          notes: _clean(notes),
          photoPath: photoPath,
          createdAt: store.now,
          updatedAt: store.now,
        );
        store.owners[owner.id] = owner;
        return owner;
      });

  @override
  Future<Owner> update(
    String id, {
    required String firstName,
    String? lastName,
    CalendarDate? birthDate,
    String? nationality,
    String? phone,
    String? email,
    String? notes,
    String? photoPath,
  }) =>
      store.write(() {
        final current = store.owners[id];
        if (current == null || store.deletedOwners.contains(id)) {
          throw EntityNotFoundException(AuditEntityType.owner, id);
        }
        final updated = current.copyWith(
          firstName: firstName.trim(),
          lastName: _clean(lastName),
          birthDate: birthDate,
          nationality: _clean(nationality),
          phone: _clean(phone),
          email: _clean(email),
          notes: _clean(notes),
          photoPath: photoPath,
        );
        store.owners[id] = updated;
        return updated;
      });

  @override
  Future<void> delete(String id) => store.write(() {
        if (!store.owners.containsKey(id) || store.deletedOwners.contains(id)) {
          throw EntityNotFoundException(AuditEntityType.owner, id);
        }
        final count = store.liveVehicles.where((v) => v.ownerId == id).length;
        if (count > 0) throw OwnerHasVehiclesException(id, count);
        store.deletedOwners.add(id);
      });

  @override
  Future<Owner> restore(String id) => store.write(() {
        if (!store.deletedOwners.remove(id)) {
          throw EntityNotFoundException(AuditEntityType.owner, id);
        }
        return store.owners[id]!;
      });
}

/// [VehicleRepository] on a [FakeStore].
class FakeVehicleRepository implements VehicleRepository {
  /// Creates the repository on [store].
  FakeVehicleRepository(this.store);

  /// The shared data.
  final FakeStore store;

  @override
  Stream<List<Vehicle>> watchAll() => store.watch(() => store.liveVehicles);

  @override
  Future<List<Vehicle>> getAll() async => store.liveVehicles;

  @override
  Stream<List<Vehicle>> watchByOwner(String ownerId) => store.watch(
        () => store.liveVehicles.where((v) => v.ownerId == ownerId).toList(),
      );

  @override
  Future<List<Vehicle>> getByOwner(String ownerId) async =>
      store.liveVehicles.where((v) => v.ownerId == ownerId).toList();

  @override
  Future<Vehicle?> getById(String id) async =>
      store.deletedVehicles.contains(id) ? null : store.vehicles[id];

  @override
  Future<Vehicle> create({
    required String plate,
    required VehicleKind kind,
    String? make,
    String? makeSlug,
    String? model,
    String? modelSlug,
    int? modelYear,
    String? version,
    String? nickname,
    required String ownerId,
    required int currentOdometerKm,
    required FuelType fuelType,
    String? recommendedEngineOil,
    String? manufacturerNotes,
    String? photoPath,
  }) =>
      store.write(() {
        final vehicle = Vehicle(
          id: store.newId('vehicle'),
          plate: plate.trim().toUpperCase(),
          kind: kind,
          make: _clean(make),
          makeSlug: makeSlug,
          model: _clean(model),
          modelSlug: modelSlug,
          modelYear: modelYear,
          version: _clean(version),
          nickname: _clean(nickname),
          ownerId: ownerId,
          currentOdometerKm: currentOdometerKm,
          fuelType: fuelType,
          recommendedEngineOil: _clean(recommendedEngineOil),
          manufacturerNotes: _clean(manufacturerNotes),
          photoPath: photoPath,
          createdAt: store.now,
          updatedAt: store.now,
        );
        _check(vehicle);
        store.vehicles[vehicle.id] = vehicle;
        return vehicle;
      });

  @override
  Future<Vehicle> update(
    String id, {
    required String plate,
    required VehicleKind kind,
    String? make,
    String? makeSlug,
    String? model,
    String? modelSlug,
    int? modelYear,
    String? version,
    String? nickname,
    required String ownerId,
    required FuelType fuelType,
    String? recommendedEngineOil,
    String? manufacturerNotes,
    String? photoPath,
  }) =>
      store.write(() {
        final current = store.vehicles[id];
        if (current == null || store.deletedVehicles.contains(id)) {
          throw EntityNotFoundException(AuditEntityType.vehicle, id);
        }
        final updated = current.copyWith(
          plate: plate.trim().toUpperCase(),
          kind: kind,
          make: _clean(make),
          makeSlug: makeSlug,
          model: _clean(model),
          modelSlug: modelSlug,
          modelYear: modelYear,
          version: _clean(version),
          nickname: _clean(nickname),
          ownerId: ownerId,
          fuelType: fuelType,
          recommendedEngineOil: _clean(recommendedEngineOil),
          manufacturerNotes: _clean(manufacturerNotes),
          photoPath: photoPath,
        );
        _check(updated);
        store.vehicles[id] = updated;
        return updated;
      });

  @override
  Future<void> delete(String id) => store.write(() {
        if (!store.vehicles.containsKey(id) ||
            store.deletedVehicles.contains(id)) {
          throw EntityNotFoundException(AuditEntityType.vehicle, id);
        }
        store.deletedVehicles.add(id);
      });

  @override
  Future<Vehicle> restore(String id) => store.write(() {
        if (!store.deletedVehicles.contains(id)) {
          throw EntityNotFoundException(AuditEntityType.vehicle, id);
        }
        final vehicle = store.vehicles[id]!;
        _check(vehicle);
        store.deletedVehicles.remove(id);
        return vehicle;
      });

  /// Refuses [vehicle] when its owner is not live or its plate is taken.
  void _check(Vehicle vehicle) {
    if (!store.liveOwners.any((o) => o.id == vehicle.ownerId)) {
      throw EntityNotFoundException(AuditEntityType.owner, vehicle.ownerId);
    }
    if (store.liveVehicles
        .any((v) => v.plate == vehicle.plate && v.id != vehicle.id)) {
      throw DuplicatePlateException(vehicle.plate);
    }
  }
}

/// Trims [value] and turns blank into `null`, like the real repositories.
String? _clean(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
