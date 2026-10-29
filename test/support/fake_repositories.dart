import 'dart:async';

import 'package:vehicle_history/data/models/archive_reason.dart';
import 'package:vehicle_history/data/models/attachment.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/models/calendar_date.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry.dart';
import 'package:vehicle_history/data/models/log_entry_filter.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/mileage_reading.dart';
import 'package:vehicle_history/data/models/owner.dart';
import 'package:vehicle_history/data/models/trashed_vehicle.dart';
import 'package:vehicle_history/data/models/vehicle.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';
import 'package:vehicle_history/data/repositories/attachment_repository.dart';
import 'package:vehicle_history/data/repositories/log_entry_repository.dart';
import 'package:vehicle_history/data/repositories/mileage_reading_repository.dart';
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

  /// When each soft-deleted vehicle was deleted, by id. Set to the real
  /// current time, so the Trash shows the full 30 days left.
  final Map<String, DateTime> vehicleDeletedAt = {};

  /// Live and deleted history entries, by id.
  final Map<String, LogEntry> entries = {};

  /// Ids of soft-deleted entries.
  final Set<String> deletedEntries = {};

  /// Live and deleted odometer readings, by id.
  final Map<String, MileageReading> readings = {};

  /// Ids of soft-deleted readings.
  final Set<String> deletedReadings = {};

  /// Live and deleted attachments, by id.
  final Map<String, Attachment> attachments = {};

  /// Ids of soft-deleted attachments.
  final Set<String> deletedAttachments = {};

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

  /// Live vehicles (active and archived) ordered by plate, like the real
  /// DAO.
  List<Vehicle> get liveVehicles => [
        for (final v in vehicles.values)
          if (!deletedVehicles.contains(v.id)) v,
      ]..sort((a, b) => a.plate.compareTo(b.plate));

  /// Active vehicles (live and not archived) ordered by plate.
  List<Vehicle> get activeVehicles =>
      liveVehicles.where((v) => !v.isArchived).toList();

  /// Archived vehicles not in the Trash, most recently archived first,
  /// then by plate, like the real DAO.
  List<Vehicle> get archivedVehicles =>
      liveVehicles.where((v) => v.isArchived).toList()
        ..sort((a, b) {
          final byDate = b.archivedAt!.compareTo(a.archivedAt!);
          return byDate != 0 ? byDate : a.plate.compareTo(b.plate);
        });

  /// Throws `VehicleArchivedException` when the vehicle [vehicleId] is
  /// archived: its entries, readings and attachments are read-only.
  void requireActiveVehicle(String vehicleId) {
    if (vehicles[vehicleId]?.isArchived ?? false) {
      throw VehicleArchivedException(AuditEntityType.vehicle, vehicleId);
    }
  }

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

  /// Live entries and readings of the vehicle [vehicleId], whatever its
  /// state.
  VehicleContents contentsOf(String vehicleId) => VehicleContents(
        entryCount: entries.values
            .where(
              (e) => e.vehicleId == vehicleId && !deletedEntries.contains(e.id),
            )
            .length,
        readingCount: readings.values
            .where(
              (r) =>
                  r.vehicleId == vehicleId && !deletedReadings.contains(r.id),
            )
            .length,
        attachmentCount: liveAttachments
            .where(
              (a) =>
                  a.target == AttachmentTarget.vehicle(vehicleId) ||
                  (a.target.entityType == AttachmentEntityType.logEntry &&
                      entries[a.target.entityId]?.vehicleId == vehicleId &&
                      !deletedEntries.contains(a.target.entityId)),
            )
            .length,
      );

  /// Live attachments, in display order.
  List<Attachment> get liveAttachments => [
        for (final a in attachments.values)
          if (!deletedAttachments.contains(a.id)) a,
      ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Adds a live attachment of [target] for the staged [file], last in
  /// its order, without checks or notification.
  Attachment addAttachment(AttachmentTarget target, StagedFile file) {
    final id = newId('attachment');
    final order = attachments.values.where((a) => a.target == target).length;
    final attachment = Attachment(
      id: id,
      target: target,
      kind: file.kind,
      fileName: file.fileName,
      mimeType: file.mimeType,
      relativePath: attachmentRelativePath(id, file.fileName),
      sizeBytes: file.sizeBytes,
      sortOrder: order,
      createdAt: now,
      updatedAt: now,
    );
    attachments[id] = attachment;
    return attachment;
  }

  /// Vehicles in the Trash, most recently deleted first, like the real DAO.
  List<TrashedVehicle> get trashedVehicles => [
        for (final id in deletedVehicles)
          TrashedVehicle(
            vehicle: vehicles[id]!,
            owner: owners[vehicles[id]!.ownerId]!,
            deletedAt: vehicleDeletedAt[id]!,
            contents: contentsOf(id),
          ),
      ]..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));

  /// Removes the vehicle [id] and all its entries and readings for good.
  void purgeVehicle(String id) {
    vehicles.remove(id);
    deletedVehicles.remove(id);
    vehicleDeletedAt.remove(id);
    entries.removeWhere((_, e) => e.vehicleId == id);
    readings.removeWhere((_, r) => r.vehicleId == id);
  }

  /// Live readings of the live vehicle [vehicleId], newest first, like the
  /// real DAO.
  List<MileageReading> liveReadingsOf(String vehicleId) {
    if (deletedVehicles.contains(vehicleId)) return [];
    return [
      for (final r in readings.values)
        if (r.vehicleId == vehicleId && !deletedReadings.contains(r.id)) r,
    ]..sort((a, b) => b.isAfter(a) ? 1 : (a.isAfter(b) ? -1 : 0));
  }

  /// Adds a live reading and moves the vehicle's odometer to it, without
  /// checks or notification. Each reading is created one minute after the
  /// previous one, so readings of the same day keep their order.
  MileageReading insertReading(
    String vehicleId,
    CalendarDate date,
    double km,
  ) {
    final created = _now.add(Duration(minutes: readings.length));
    final reading = MileageReading(
      id: newId('reading'),
      vehicleId: vehicleId,
      date: date,
      km: km,
      createdAt: created,
      updatedAt: created,
    );
    readings[reading.id] = reading;
    setOdometer(vehicleId, km);
    return reading;
  }

  /// Writes the odometer cache of the vehicle [vehicleId].
  void setOdometer(String vehicleId, double km) {
    vehicles[vehicleId] = vehicles[vehicleId]!.copyWith(currentOdometerKm: km);
  }

  /// Adds a live reading directly, for test setup.
  MileageReading addReading(
    String vehicleId, {
    required CalendarDate date,
    required double km,
  }) {
    final reading = insertReading(vehicleId, date, km);
    _changes.add(null);
    return reading;
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
    double? km = 1000,
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
    double km = 1000,
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
    // Like the real repository: every vehicle starts with its initial
    // reading.
    insertReading(
      vehicle.id,
      CalendarDate(_now.year, _now.month, _now.day),
      km,
    );
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
        final trashed =
            store.trashedVehicles.where((t) => t.vehicle.ownerId == id).length;
        if (trashed > 0) throw OwnerHasTrashedVehiclesException(id, trashed);
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
  Stream<List<Vehicle>> watchActive() =>
      store.watch(() => store.activeVehicles);

  @override
  Future<List<Vehicle>> getActive() async => store.activeVehicles;

  @override
  Stream<List<Vehicle>> watchArchived() =>
      store.watch(() => store.archivedVehicles);

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
  Stream<Vehicle?> watchById(String id) => store.watch(
        () => store.deletedVehicles.contains(id) ? null : store.vehicles[id],
      );

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
    required double currentOdometerKm,
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
        store.insertReading(vehicle.id, _today(), currentOdometerKm);
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
        store.requireActiveVehicle(id);
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
  Future<Vehicle> archive(
    String id, {
    required ArchiveReason reason,
    required CalendarDate date,
    double? km,
    String? note,
  }) async {
    final current = store.vehicles[id];
    if (current == null || store.deletedVehicles.contains(id)) {
      throw EntityNotFoundException(AuditEntityType.vehicle, id);
    }
    store.requireActiveVehicle(id);
    if (date.isAfter(_today())) {
      throw const InvalidFieldException('date', InvalidFieldException.inFuture);
    }
    // The final reading, under the reading rules, as the real repository.
    if (km != null) {
      await FakeMileageReadingRepository(store)
          .create(vehicleId: id, date: date, km: km);
    }
    return store.write(() {
      final archived = store.vehicles[id]!.copyWith(
        archivedAt: date,
        archiveReason: reason,
        archiveNote: _clean(note),
        archivedKm: km,
        updatedAt: store.now,
      );
      store.vehicles[id] = archived;
      return archived;
    });
  }

  @override
  Future<Vehicle> reactivate(String id) => store.write(() {
        final current = store.vehicles[id];
        if (current == null || store.deletedVehicles.contains(id)) {
          throw EntityNotFoundException(AuditEntityType.vehicle, id);
        }
        if (!current.isArchived) {
          throw const InvalidFieldException('archivedAt', 'is not archived');
        }
        final active = current.copyWith(
          archivedAt: null,
          archiveReason: null,
          archiveNote: null,
          archivedKm: null,
          updatedAt: store.now,
        );
        store.vehicles[id] = active;
        return active;
      });

  @override
  Future<void> delete(String id) => store.write(() {
        if (!store.vehicles.containsKey(id) ||
            store.deletedVehicles.contains(id)) {
          throw EntityNotFoundException(AuditEntityType.vehicle, id);
        }
        store.deletedVehicles.add(id);
        store.vehicleDeletedAt[id] = DateTime.now().toUtc();
      });

  @override
  Future<Vehicle> restore(String id) => store.write(() {
        if (!store.deletedVehicles.contains(id)) {
          throw EntityNotFoundException(AuditEntityType.vehicle, id);
        }
        final vehicle = store.vehicles[id]!;
        _check(vehicle);
        store.deletedVehicles.remove(id);
        store.vehicleDeletedAt.remove(id);
        return vehicle;
      });

  @override
  Future<VehicleContents> countContents(String id) async {
    if (!store.vehicles.containsKey(id) || store.deletedVehicles.contains(id)) {
      throw EntityNotFoundException(AuditEntityType.vehicle, id);
    }
    return store.contentsOf(id);
  }

  @override
  Stream<List<TrashedVehicle>> watchTrashed() =>
      store.watch(() => store.trashedVehicles);

  @override
  Future<void> purge(String id) => store.write(() {
        if (!store.deletedVehicles.contains(id)) {
          throw EntityNotFoundException(AuditEntityType.vehicle, id);
        }
        store.purgeVehicle(id);
      });

  @override
  Future<int> purgeAllTrashed() => store.write(() {
        final ids = store.deletedVehicles.toList();
        ids.forEach(store.purgeVehicle);
        return ids.length;
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
    double? km,
    required LogEntryType type,
    String? description,
    int? costCents,
    List<StagedFile> attachments = const [],
  }) =>
      store.write(() {
        _check(type, km, date);
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
        for (final file in attachments) {
          store.addAttachment(AttachmentTarget.logEntry(entry.id), file);
        }
        return entry;
      });

  @override
  Future<LogEntry> update(
    String id, {
    required CalendarDate date,
    double? km,
    required LogEntryType type,
    String? description,
    int? costCents,
    List<StagedFile> addedAttachments = const [],
    Set<String> removedAttachmentIds = const {},
  }) =>
      store.write(() {
        _check(type, km, date);
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
        store.deletedAttachments.addAll(removedAttachmentIds);
        for (final file in addedAttachments) {
          store.addAttachment(AttachmentTarget.logEntry(id), file);
        }
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

  /// Refuses a missing km for a type that requires it, and a future date
  /// for a type that does not allow one.
  void _check(LogEntryType type, double? km, CalendarDate date) {
    if (km == null && type.requiresKm) {
      throw const InvalidFieldException('km', 'required');
    }
    if (!type.allowsFutureDate && date.isAfter(_today())) {
      throw const InvalidFieldException('date', InvalidFieldException.inFuture);
    }
  }
}

/// [MileageReadingRepository] on a [FakeStore], with the series rules of
/// the real repository and the real "today".
class FakeMileageReadingRepository implements MileageReadingRepository {
  /// Creates the repository on [store].
  FakeMileageReadingRepository(this.store);

  /// The shared data.
  final FakeStore store;

  @override
  Stream<List<MileageReading>> watchByVehicle(String vehicleId) =>
      store.watch(() => store.liveReadingsOf(vehicleId));

  @override
  Future<List<MileageReading>> getByVehicle(String vehicleId) async =>
      store.liveReadingsOf(vehicleId);

  @override
  Future<MileageReading?> getLast(String vehicleId) async =>
      store.liveReadingsOf(vehicleId).firstOrNull;

  @override
  Future<MileageReading> create({
    required String vehicleId,
    required CalendarDate date,
    required double km,
  }) =>
      store.write(() {
        _requireLiveVehicle(vehicleId);
        store.requireActiveVehicle(vehicleId);
        final last = store.liveReadingsOf(vehicleId).firstOrNull;
        if (date.isAfter(_today())) {
          throw const InvalidFieldException(
            'date',
            InvalidFieldException.inFuture,
          );
        }
        if (last != null && date.isBefore(last.date)) {
          throw const InvalidFieldException(
            'date',
            InvalidFieldException.beforeLastReading,
          );
        }
        if (last != null && km < last.km) {
          throw const InvalidFieldException(
            'km',
            InvalidFieldException.belowLastReading,
          );
        }
        return store.insertReading(vehicleId, date, km);
      });

  @override
  Future<MileageReading> updateInitial(
    String id, {
    required CalendarDate date,
    required double km,
  }) =>
      store.write(() {
        final current = _live(id);
        if (store.liveReadingsOf(current.vehicleId).length != 1) {
          throw MileageReadingRuleException(
            id,
            MileageReadingRule.notSoleReading,
          );
        }
        final updated = current.copyWith(date: date, km: km);
        store.readings[id] = updated;
        store.setOdometer(current.vehicleId, km);
        return updated;
      });

  @override
  Future<void> deleteLast(String id) => store.write(() {
        final reading = _live(id);
        final all = store.liveReadingsOf(reading.vehicleId);
        if (all.first.id != id) {
          throw MileageReadingRuleException(id, MileageReadingRule.notLast);
        }
        if (all.length == 1) {
          throw MileageReadingRuleException(id, MileageReadingRule.initial);
        }
        store.deletedReadings.add(id);
        store.setOdometer(reading.vehicleId, all[1].km);
      });

  @override
  Future<MileageReading> restore(String id) => store.write(() {
        if (!store.deletedReadings.contains(id)) {
          throw EntityNotFoundException(AuditEntityType.mileageReading, id);
        }
        final reading = store.readings[id]!;
        _requireLiveVehicle(reading.vehicleId);
        final last = store.liveReadingsOf(reading.vehicleId).firstOrNull;
        if (last != null && !reading.isAfter(last)) {
          throw MileageReadingRuleException(
            id,
            MileageReadingRule.newerReadingExists,
          );
        }
        store.deletedReadings.remove(id);
        store.setOdometer(reading.vehicleId, reading.km);
        return reading;
      });

  /// The live reading with [id] of a live vehicle, or throws.
  MileageReading _live(String id) {
    final reading = store.readings[id];
    if (reading == null ||
        store.deletedReadings.contains(id) ||
        store.deletedVehicles.contains(reading.vehicleId)) {
      throw EntityNotFoundException(AuditEntityType.mileageReading, id);
    }
    return reading;
  }

  /// Throws unless the vehicle with [vehicleId] is live.
  void _requireLiveVehicle(String vehicleId) {
    if (!store.liveVehicles.any((v) => v.id == vehicleId)) {
      throw EntityNotFoundException(AuditEntityType.vehicle, vehicleId);
    }
  }
}

/// Today's calendar day on the machine running the tests, like the real
/// repositories' default clock.
CalendarDate _today() => CalendarDate.localDayOf(DateTime.now());

/// Trims [value] and turns blank into `null`, like the real repositories.
String? _clean(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// [AttachmentRepository] on a [FakeStore]. File paths are fake: images
/// show the "File not found" placeholder in widget tests.
class FakeAttachmentRepository implements AttachmentRepository {
  /// Creates the repository on [store].
  FakeAttachmentRepository(this.store);

  /// The shared in-memory data.
  final FakeStore store;

  /// Whether the target is live in the store.
  bool _isLive(AttachmentTarget target) => switch (target.entityType) {
        AttachmentEntityType.owner =>
          store.liveOwners.any((o) => o.id == target.entityId),
        AttachmentEntityType.vehicle =>
          store.liveVehicles.any((v) => v.id == target.entityId),
        AttachmentEntityType.logEntry =>
          store.entries.containsKey(target.entityId) &&
              !store.deletedEntries.contains(target.entityId),
      };

  /// The live attachment [id], or `null`.
  Attachment? _live(String id) =>
      store.deletedAttachments.contains(id) ? null : store.attachments[id];

  @override
  Stream<List<Attachment>> watchByTarget(AttachmentTarget target) =>
      store.watch(
        () => [
          for (final a in store.liveAttachments)
            if (a.target == target) a,
        ],
      );

  @override
  Future<List<Attachment>> getByTarget(AttachmentTarget target) async => [
        for (final a in store.liveAttachments)
          if (a.target == target) a,
      ];

  @override
  Stream<Attachment?> watchById(String id) => store.watch(() => _live(id));

  @override
  Stream<Map<String, int>> watchEntryCounts(String vehicleId) =>
      store.watch(() {
        final counts = <String, int>{};
        for (final a in store.liveAttachments) {
          final entry = store.entries[a.target.entityId];
          if (a.target.entityType == AttachmentEntityType.logEntry &&
              entry?.vehicleId == vehicleId &&
              !store.deletedEntries.contains(entry!.id)) {
            counts[entry.id] = (counts[entry.id] ?? 0) + 1;
          }
        }
        return counts;
      });

  @override
  Stream<AttachmentTotals> watchTotals() => store.watch(
        () => AttachmentTotals(
          count: store.attachments.length,
          bytes:
              store.attachments.values.fold(0, (sum, a) => sum + a.sizeBytes),
        ),
      );

  @override
  Future<Attachment> create(AttachmentTarget target, StagedFile file) =>
      store.write(() {
        if (!_isLive(target)) {
          throw EntityNotFoundException(
            AuditEntityType.vehicle,
            target.entityId,
          );
        }
        return store.addAttachment(target, file);
      });

  @override
  Future<Attachment> updateCaption(String id, String? caption) =>
      store.write(() {
        final current = _live(id);
        if (current == null) {
          throw EntityNotFoundException(AuditEntityType.attachment, id);
        }
        final trimmed = caption?.trim();
        final updated = current.copyWith(
          caption: trimmed == null || trimmed.isEmpty ? null : trimmed,
        );
        store.attachments[id] = updated;
        return updated;
      });

  @override
  Future<void> reorder(AttachmentTarget target, List<String> orderedIds) =>
      store.write(() {
        for (final (index, id) in orderedIds.indexed) {
          store.attachments[id] =
              store.attachments[id]!.copyWith(sortOrder: index);
        }
      });

  @override
  Future<void> delete(String id) => store.write(() {
        if (_live(id) == null) {
          throw EntityNotFoundException(AuditEntityType.attachment, id);
        }
        store.deletedAttachments.add(id);
      });

  @override
  Future<Attachment> restore(String id) => store.write(() {
        if (!store.deletedAttachments.contains(id)) {
          throw EntityNotFoundException(AuditEntityType.attachment, id);
        }
        store.deletedAttachments.remove(id);
        return store.attachments[id]!;
      });

  @override
  Future<void> deleteMany(List<String> ids) => store.write(() {
        if (ids.any((id) => _live(id) == null)) {
          throw EntityNotFoundException(AuditEntityType.attachment, ids.first);
        }
        store.deletedAttachments.addAll(ids);
      });

  @override
  Future<List<Attachment>> restoreMany(List<String> ids) => store.write(() {
        if (!ids.every(store.deletedAttachments.contains)) {
          throw EntityNotFoundException(AuditEntityType.attachment, ids.first);
        }
        store.deletedAttachments.removeAll(ids);
        return [for (final id in ids) store.attachments[id]!];
      });

  @override
  String filePathOf(Attachment attachment) =>
      '/fake/${attachment.relativePath}';

  @override
  Future<bool> fileExists(Attachment attachment) async => true;
}
