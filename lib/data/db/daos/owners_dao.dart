import 'package:drift/drift.dart';

import '../../models/owner.dart';
import '../app_database.dart';
import '../owners_table.dart';
import '../row_mappers.dart';
import '../vehicles_table.dart';

part 'owners_dao.g.dart';

/// Queries on the `owners` table.
///
/// Accepts and returns domain models only. Every read is limited to live rows
/// (`deleted = 0`), and writes that target an existing row match live rows
/// only, so a deleted owner cannot be changed by accident.
@DriftAccessor(tables: [Owners, Vehicles])
class OwnersDao extends DatabaseAccessor<AppDatabase> with _$OwnersDaoMixin {
  /// Creates the DAO on [db]. Obtain it through `AppDatabase.ownersDao`.
  OwnersDao(super.db);

  /// Select of live owners, ordered by first and last name.
  SimpleSelectStatement<$OwnersTable, OwnerRow> _live() {
    return select(owners)
      ..where((o) => o.deleted.equals(false))
      ..orderBy([
        (o) => OrderingTerm(expression: o.firstName),
        (o) => OrderingTerm(expression: o.lastName),
      ]);
  }

  /// Converts a list of rows into domain models.
  static List<Owner> _toModels(List<OwnerRow> rows) =>
      [for (final r in rows) r.toModel()];

  /// Emits the live owners now and after every change.
  Stream<List<Owner>> watchLive() => _live().watch().map(_toModels);

  /// Returns the live owners once.
  Future<List<Owner>> getLive() => _live().get().then(_toModels);

  /// Returns the live owner with [id], or `null` if missing or deleted.
  Future<Owner?> getLiveById(String id) async {
    final row = await (select(owners)
          ..where((o) => o.id.equals(id) & o.deleted.equals(false)))
        .getSingleOrNull();
    return row?.toModel();
  }

  /// Inserts [owner] as a new live row.
  Future<void> insertOwner(Owner owner) =>
      into(owners).insert(owner.toInsertCompanion());

  /// Overwrites the editable fields and `updated_at` of the live owner with
  /// `owner.id`.
  ///
  /// Returns the number of rows changed: 0 when the owner is missing or
  /// already deleted.
  Future<int> updateLive(Owner owner) =>
      _whereLive(owner.id).write(owner.toUpdateCompanion());

  /// Marks the live owner with [id] as deleted at [at].
  ///
  /// Returns the number of rows changed: 0 when the owner is missing or
  /// already deleted.
  Future<int> softDeleteLive(String id, DateTime at) => _whereLive(id).write(
        OwnersCompanion(deleted: const Value(true), updatedAt: Value(at)),
      );

  /// Brings the soft-deleted owner with [id] back to life at [at].
  ///
  /// Returns the number of rows changed: 0 when the owner is missing or not
  /// deleted.
  Future<int> restoreDeleted(String id, DateTime at) =>
      (update(owners)..where((o) => o.id.equals(id) & o.deleted.equals(true)))
          .write(
        OwnersCompanion(deleted: const Value(false), updatedAt: Value(at)),
      );

  /// Update statement restricted to the live owner with [id].
  UpdateStatement<$OwnersTable, OwnerRow> _whereLive(String id) =>
      update(owners)..where((o) => o.id.equals(id) & o.deleted.equals(false));

  /// Counts the live vehicles that belong to the owner with [ownerId].
  Future<int> countLiveVehicles(String ownerId) async {
    final count = vehicles.id.count();
    final query = selectOnly(vehicles)
      ..addColumns([count])
      ..where(
        vehicles.ownerId.equals(ownerId) & vehicles.deleted.equals(false),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }
}
