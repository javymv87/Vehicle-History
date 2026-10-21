import 'package:drift/drift.dart';

import '../../models/attachment.dart';
import '../../models/trashed_vehicle.dart';
import '../app_database.dart';
import '../attachments_table.dart';
import '../converters.dart';
import '../log_entries_table.dart';
import '../mileage_readings_table.dart';
import '../owners_table.dart';
import '../row_mappers.dart';
import '../vehicles_table.dart';

part 'trash_dao.g.dart';

/// A soft-deleted row and the instant it was deleted, as read by the
/// cleanup before deciding whether it is old enough to remove.
typedef DeletedRow = ({String id, DateTime deletedAt});

/// What a physical delete removed: the number of rows of the table it
/// targets, and the relative paths of the attachment files whose rows went
/// with them. The files are still on disk: the caller deletes them once the
/// transaction has committed.
typedef PurgedRows = ({int rows, List<String> files});

/// Queries on soft-deleted rows: the Trash and the physical deletes.
///
/// The only place that removes rows from disk. Every other DAO only flags
/// rows as deleted. Accepts and returns domain models only.
@DriftAccessor(
  tables: [Vehicles, Owners, LogEntries, MileageReadings, Attachments],
)
class TrashDao extends DatabaseAccessor<AppDatabase> with _$TrashDaoMixin {
  /// Creates the DAO on [db]. Obtain it through `AppDatabase.trashDao`.
  TrashDao(super.db);

  /// Number of live entries of the vehicle in the current row of the outer
  /// query, as a correlated subquery.
  Expression<int> get _liveEntryCount {
    final count = logEntries.id.count();
    return subqueryExpression<int>(
      selectOnly(logEntries)
        ..addColumns([count])
        ..where(
          logEntries.vehicleId.equalsExp(vehicles.id) &
              logEntries.deleted.equals(false),
        ),
    );
  }

  /// Number of live readings of the vehicle in the current row of the outer
  /// query, as a correlated subquery.
  Expression<int> get _liveReadingCount {
    final count = mileageReadings.id.count();
    return subqueryExpression<int>(
      selectOnly(mileageReadings)
        ..addColumns([count])
        ..where(
          mileageReadings.vehicleId.equalsExp(vehicles.id) &
              mileageReadings.deleted.equals(false),
        ),
    );
  }

  /// Storage code of [type] in `attachments.entity_type`.
  static String _code(AttachmentEntityType type) =>
      const AttachmentEntityTypeConverter().toSql(type);

  /// Condition on `attachments`: the row belongs to the vehicle whose id is
  /// [vehicleId] (its own documents) or to one of that vehicle's entries
  /// that passes [entryFilter] (all of them when `null`).
  Expression<bool> _ofVehicle(
    Expression<String> vehicleId, {
    Expression<bool> Function()? entryFilter,
  }) {
    final entryIds = selectOnly(logEntries)
      ..addColumns([logEntries.id])
      ..where(
        logEntries.vehicleId.equalsExp(vehicleId) &
            (entryFilter?.call() ?? const Constant(true)),
      );
    return (attachments.entityType.equals(_code(AttachmentEntityType.vehicle)) &
            attachments.entityId.equalsExp(vehicleId)) |
        (attachments.entityType.equals(_code(AttachmentEntityType.logEntry)) &
            attachments.entityId.isInQuery(entryIds));
  }

  /// Number of live attachments carried by the vehicle whose id is
  /// [vehicleId]: its own, plus those of its live entries.
  Expression<int> _liveAttachmentCount(Expression<String> vehicleId) {
    final count = attachments.id.count();
    return subqueryExpression<int>(
      selectOnly(attachments)
        ..addColumns([count])
        ..where(
          attachments.deleted.equals(false) &
              _ofVehicle(
                vehicleId,
                entryFilter: () => logEntries.deleted.equals(false),
              ),
        ),
    );
  }

  /// Emits the soft-deleted vehicles, most recently deleted first, each with
  /// its owner and the counts of its live entries, readings and
  /// attachments.
  ///
  /// The owner is joined whatever its own state. A deleted vehicle without
  /// `deleted_at` cannot exist from schema v5 on; it would sort last and
  /// show the epoch as its deletion instant rather than vanish.
  Stream<List<TrashedVehicle>> watchTrashedVehicles() {
    final entryCount = _liveEntryCount;
    final readingCount = _liveReadingCount;
    final attachmentCount = _liveAttachmentCount(vehicles.id);
    final query = select(vehicles).join([
      innerJoin(owners, owners.id.equalsExp(vehicles.ownerId)),
    ])
      ..addColumns([entryCount, readingCount, attachmentCount])
      ..where(vehicles.deleted.equals(true))
      ..orderBy([
        OrderingTerm.desc(vehicles.deletedAt),
        OrderingTerm.asc(vehicles.plate),
      ]);
    return query.watch().map(
          (rows) => [
            for (final row in rows)
              TrashedVehicle(
                vehicle: row.readTable(vehicles).toModel(),
                owner: row.readTable(owners).toModel(),
                deletedAt: row.readTable(vehicles).deletedAt?.toUtc() ??
                    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
                contents: VehicleContents(
                  entryCount: row.read(entryCount) ?? 0,
                  readingCount: row.read(readingCount) ?? 0,
                  attachmentCount: row.read(attachmentCount) ?? 0,
                ),
              ),
          ],
        );
  }

  /// Counts the live entries, readings and attachments (its own and its
  /// live entries') of the vehicle [vehicleId], whatever the state of the
  /// vehicle.
  Future<VehicleContents> countLiveContents(String vehicleId) async {
    final entries = logEntries.id.count();
    final readings = mileageReadings.id.count();
    final entryRow = await (selectOnly(logEntries)
          ..addColumns([entries])
          ..where(
            logEntries.vehicleId.equals(vehicleId) &
                logEntries.deleted.equals(false),
          ))
        .getSingle();
    final readingRow = await (selectOnly(mileageReadings)
          ..addColumns([readings])
          ..where(
            mileageReadings.vehicleId.equals(vehicleId) &
                mileageReadings.deleted.equals(false),
          ))
        .getSingle();
    final attachmentCount = _liveAttachmentCount(Variable(vehicleId));
    final attachmentRow = await (selectOnly(vehicles)
          ..addColumns([attachmentCount])
          ..limit(1))
        .getSingleOrNull();
    return VehicleContents(
      entryCount: entryRow.read(entries) ?? 0,
      readingCount: readingRow.read(readings) ?? 0,
      attachmentCount: attachmentRow?.read(attachmentCount) ?? 0,
    );
  }

  /// Ids of every soft-deleted vehicle, with or without `deleted_at`.
  Future<List<String>> getTrashedVehicleIds() async {
    final rows = await (selectOnly(vehicles)
          ..addColumns([vehicles.id])
          ..where(vehicles.deleted.equals(true)))
        .get();
    return [for (final r in rows) r.read(vehicles.id)!];
  }

  /// Returns the soft-deleted vehicles with their deletion instant.
  ///
  /// Rows without `deleted_at` are left out: without a date they are never
  /// old enough to be removed by the cleanup.
  Future<List<DeletedRow>> getTrashedVehicles() async {
    final rows = await (select(vehicles)
          ..where((v) => v.deleted.equals(true) & v.deletedAt.isNotNull()))
        .get();
    return [for (final r in rows) (id: r.id, deletedAt: r.deletedAt!.toUtc())];
  }

  /// Returns the soft-deleted entries whose vehicle is live, with their
  /// deletion instant. Rows without `deleted_at` are left out.
  Future<List<DeletedRow>> getDeletedEntriesOfLiveVehicles() async {
    final rows = await (select(logEntries)
          ..where(
            (e) =>
                e.deleted.equals(true) &
                e.deletedAt.isNotNull() &
                e.vehicleId.isInQuery(_liveVehicleIds()),
          ))
        .get();
    return [for (final r in rows) (id: r.id, deletedAt: r.deletedAt!.toUtc())];
  }

  /// Returns the soft-deleted readings whose vehicle is live, with their
  /// deletion instant. Rows without `deleted_at` are left out.
  Future<List<DeletedRow>> getDeletedReadingsOfLiveVehicles() async {
    final rows = await (select(mileageReadings)
          ..where(
            (r) =>
                r.deleted.equals(true) &
                r.deletedAt.isNotNull() &
                r.vehicleId.isInQuery(_liveVehicleIds()),
          ))
        .get();
    return [for (final r in rows) (id: r.id, deletedAt: r.deletedAt!.toUtc())];
  }

  /// Returns the soft-deleted owners that no vehicle row references, live
  /// or deleted, with their deletion instant. Rows without `deleted_at` are
  /// left out.
  Future<List<DeletedRow>> getDeletedOwnersWithoutVehicles() async {
    final referenced = selectOnly(vehicles)..addColumns([vehicles.ownerId]);
    final rows = await (select(owners)
          ..where(
            (o) =>
                o.deleted.equals(true) &
                o.deletedAt.isNotNull() &
                o.id.isNotInQuery(referenced),
          ))
        .get();
    return [for (final r in rows) (id: r.id, deletedAt: r.deletedAt!.toUtc())];
  }

  /// Ids of the live vehicles, as a subquery.
  JoinedSelectStatement<$VehiclesTable, VehicleRow> _liveVehicleIds() =>
      selectOnly(vehicles)
        ..addColumns([vehicles.id])
        ..where(vehicles.deleted.equals(false));

  /// Removes from disk the soft-deleted vehicle [vehicleId] and **every**
  /// entry, reading and attachment row that belongs to it (its own
  /// attachments and its entries'), whatever their own flags.
  ///
  /// Children go first: the foreign keys of entries and readings are
  /// `ON DELETE RESTRICT`. Returns the relative paths of the attachment
  /// files whose rows were removed, or `null`, with nothing removed at all,
  /// when the vehicle is missing or still live. Call it inside a transaction
  /// together with its audit row, and delete the files after the commit.
  Future<List<String>?> purgeVehicle(String vehicleId) async {
    final isTrashed = await (select(vehicles)
          ..where((v) => v.id.equals(vehicleId) & v.deleted.equals(true)))
        .getSingleOrNull();
    if (isTrashed == null) return null;
    final files = await _deleteAttachmentsWhere(
      _ofVehicle(Variable(vehicleId)),
    );
    await (delete(mileageReadings)..where((r) => r.vehicleId.equals(vehicleId)))
        .go();
    await (delete(logEntries)..where((e) => e.vehicleId.equals(vehicleId)))
        .go();
    await (delete(vehicles)
          ..where((v) => v.id.equals(vehicleId) & v.deleted.equals(true)))
        .go();
    return files;
  }

  /// Deletes the attachment rows matching [condition] and returns the
  /// relative paths of their files.
  Future<List<String>> _deleteAttachmentsWhere(
    Expression<bool> condition,
  ) async {
    final rows = await (selectOnly(attachments)
          ..addColumns([attachments.relativePath])
          ..where(condition))
        .get();
    await (delete(attachments)..where((_) => condition)).go();
    return [for (final r in rows) r.read(attachments.relativePath)!];
  }

  /// Condition on `attachments`: the row belongs to an entity of [type]
  /// whose id is in [ids].
  Expression<bool> _ofEntities(
    AttachmentEntityType type,
    Iterable<String> ids,
  ) =>
      attachments.entityType.equals(_code(type)) &
      attachments.entityId.isIn(ids);

  /// Removes from disk the soft-deleted entries with [ids], with every
  /// attachment row of theirs whatever its flag. Live entries and their
  /// attachments are never touched. Returns the number of entries removed
  /// and the files of the attachment rows removed.
  Future<PurgedRows> purgeEntries(Iterable<String> ids) async {
    final deletedIds = [
      for (final r in await (selectOnly(logEntries)
            ..addColumns([logEntries.id])
            ..where(logEntries.id.isIn(ids) & logEntries.deleted.equals(true)))
          .get())
        r.read(logEntries.id)!,
    ];
    if (deletedIds.isEmpty) return (rows: 0, files: const <String>[]);
    final files = await _deleteAttachmentsWhere(
      _ofEntities(AttachmentEntityType.logEntry, deletedIds),
    );
    final rows = await (delete(logEntries)
          ..where((e) => e.id.isIn(deletedIds) & e.deleted.equals(true)))
        .go();
    return (rows: rows, files: files);
  }

  /// Removes from disk the soft-deleted readings with [ids]. Live readings
  /// are never touched. Returns the number of rows removed.
  Future<int> purgeReadings(Iterable<String> ids) => (delete(mileageReadings)
        ..where((r) => r.id.isIn(ids) & r.deleted.equals(true)))
      .go();

  /// Removes from disk the soft-deleted owner [ownerId], with every
  /// attachment row of theirs whatever its flag. Live owners are never
  /// touched; an owner still referenced by a vehicle row is refused by its
  /// foreign key. Returns the number of owners removed and the files of the
  /// attachment rows removed.
  Future<PurgedRows> purgeOwner(String ownerId) async {
    final isDeleted = await (select(owners)
          ..where((o) => o.id.equals(ownerId) & o.deleted.equals(true)))
        .getSingleOrNull();
    if (isDeleted == null) return (rows: 0, files: const <String>[]);
    final files = await _deleteAttachmentsWhere(
      _ofEntities(AttachmentEntityType.owner, [ownerId]),
    );
    final rows = await (delete(owners)
          ..where((o) => o.id.equals(ownerId) & o.deleted.equals(true)))
        .go();
    return (rows: rows, files: files);
  }

  /// Returns the soft-deleted attachments that do not travel with a
  /// vehicle in the Trash (neither the vehicle's own nor one of its
  /// entries'), with their deletion instant. Rows without `deleted_at` are
  /// left out.
  ///
  /// Those of a trashed vehicle stay as they are: they go with the vehicle,
  /// or come back with it.
  Future<List<DeletedRow>> getDeletedAttachmentsOutsideTrash() async {
    final trashedIds = selectOnly(vehicles)
      ..addColumns([vehicles.id])
      ..where(vehicles.deleted.equals(true));
    final entriesOfTrashed = selectOnly(logEntries)
      ..addColumns([logEntries.id])
      ..where(logEntries.vehicleId.isInQuery(trashedIds));
    final ofTrashedVehicle = (attachments.entityType
                .equals(_code(AttachmentEntityType.vehicle)) &
            attachments.entityId.isInQuery(trashedIds)) |
        (attachments.entityType.equals(_code(AttachmentEntityType.logEntry)) &
            attachments.entityId.isInQuery(entriesOfTrashed));
    final rows = await (select(attachments)
          ..where(
            (a) =>
                a.deleted.equals(true) &
                a.deletedAt.isNotNull() &
                ofTrashedVehicle.not(),
          ))
        .get();
    return [for (final r in rows) (id: r.id, deletedAt: r.deletedAt!.toUtc())];
  }

  /// Removes from disk the soft-deleted attachments with [ids]. Live
  /// attachments are never touched. Returns the number of rows removed and
  /// their files.
  Future<PurgedRows> purgeAttachments(Iterable<String> ids) async {
    final files = await _deleteAttachmentsWhere(
      attachments.id.isIn(ids) & attachments.deleted.equals(true),
    );
    return (rows: files.length, files: files);
  }
}
