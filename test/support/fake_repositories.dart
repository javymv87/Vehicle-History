import 'dart:async';

import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry.dart';
import 'package:vehicle_history/data/models/log_entry_filter.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/owner.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/log_entry_repository.dart';
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

  /// Live and deleted history entries, by id.
  final Map<String, LogEntry> entries = {};

  /// Ids of soft-deleted entries.
  final Set<String> deletedEntries = {};

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

  /// Live entries of the live vehicle [vehicleId], newest first, like the
  /// real DAO.
  List<LogEntry> liveEntriesOf(String vehicleId) {
    if (deletedVehicles.contains(vehicleId)) return [];
    return [
      for (final e in entries.values)
        if (e.vehicleId == vehicleId && !deletedEntries.contains(e.id)) e,
    ]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        final byCreation = b.createdAt.compareTo(a.createdAt);
        return byCreation != 0 ? byCreation : b.id.compareTo(a.id);
      });
  }

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

  /// Adds a live history entry directly, for test setup.
  ///
  /// Each entry is created one minute after the previous one, so entries of
  /// the same day keep their insertion order (newest first).
  LogEntry addEntry(
    String vehicleId, {
    required CalendarDate date,
    LogEntryType type = LogEntryType.maintenance,
    int? km = 1000,
    String? description,
    int? costCents,
  }) {
    final created = _now.add(Duration(minutes: entries.length));
    final entry = LogEntry(
      id: newId('entry'),
      vehicleId: vehicleId,
      date: date,
      km: km,
      type: type,
      description: description,
      costCents: costCents,
      createdAt: created,
      updatedAt: created,
    );
    entries[entry.id] = entry;
    _changes.add(null);
    return entry;
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

/// [LogEntryRepository] on a [FakeStore].
///
/// Applies the filter with `LogEntryFilter.matches`, the reference the Drift
/// repository is tested against.
class FakeLogEntryRepository implements LogEntryRepository {
  /// Creates the repository on [store].
  FakeLogEntryRepository(this.store);

  /// The shared data.
  final FakeStore store;

  @override
  Stream<List<LogEntry>> watchByVehicle(
    String vehicleId, {
    LogEntryFilter filter = LogEntryFilter.none,
  }) =>
      store.watch(
        () => store.liveEntriesOf(vehicleId).where(filter.matches).toList(),
      );

  @override
  Future<LogEntry?> getById(String id) async => _live(id);

  @override
  Stream<LogEntry?> watchById(String id) => store.watch(() => _live(id));

  /// The live entry with [id] of a live vehicle, or `null`.
  LogEntry? _live(String id) {
    final entry = store.entries[id];
    if (entry == null ||
        store.deletedEntries.contains(id) ||
        store.deletedVehicles.contains(entry.vehicleId)) {
      return null;
    }
    return entry;
  }

  @override
  Future<LogEntry> create({
    required String vehicleId,
    required CalendarDate date,
    int? km,
    required LogEntryType type,
    String? description,
    int? costCents,
  }) =>
      store.write(() {
        _check(type, km);
        if (!store.liveVehicles.any((v) => v.id == vehicleId)) {
          throw EntityNotFoundException(AuditEntityType.vehicle, vehicleId);
        }
        final created = store.now.add(Duration(minutes: store.entries.length));
        final entry = LogEntry(
          id: store.newId('entry'),
          vehicleId: vehicleId,
          date: date,
          km: km,
          type: type,
          description: _clean(description),
          costCents: costCents,
          createdAt: created,
          updatedAt: created,
        );
        store.entries[entry.id] = entry;
        return entry;
      });

  @override
  Future<LogEntry> update(
    String id, {
    required CalendarDate date,
    int? km,
    required LogEntryType type,
    String? description,
    int? costCents,
  }) =>
      store.write(() {
        _check(type, km);
        final current = _live(id);
        if (current == null) {
          throw EntityNotFoundException(AuditEntityType.logEntry, id);
        }
        final updated = current.copyWith(
          date: date,
          km: km,
          type: type,
          description: _clean(description),
          costCents: costCents,
        );
        store.entries[id] = updated;
        return updated;
      });

  @override
  Future<void> delete(String id) => store.write(() {
        if (_live(id) == null) {
          throw EntityNotFoundException(AuditEntityType.logEntry, id);
        }
        store.deletedEntries.add(id);
      });

  @override
  Future<LogEntry> restore(String id) => store.write(() {
        if (!store.deletedEntries.contains(id)) {
          throw EntityNotFoundException(AuditEntityType.logEntry, id);
        }
        final entry = store.entries[id]!;
        if (store.deletedVehicles.contains(entry.vehicleId)) {
          throw EntityNotFoundException(
            AuditEntityType.vehicle,
            entry.vehicleId,
          );
        }
        store.deletedEntries.remove(id);
        return entry;
      });

  /// Refuses a missing km for a type that requires it.
  void _check(LogEntryType type, int? km) {
    if (km == null && type.requiresKm) {
      throw const InvalidFieldException('km', 'required');
    }
  }
}

/// Trims [value] and turns blank into `null`, like the real repositories.
String? _clean(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
