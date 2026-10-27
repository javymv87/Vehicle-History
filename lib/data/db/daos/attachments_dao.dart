import 'package:drift/drift.dart';

import '../../models/attachment.dart';
import '../app_database.dart';
import '../attachments_table.dart';
import '../converters.dart';
import '../log_entries_table.dart';
import '../owners_table.dart';
import '../row_mappers.dart';
import '../vehicle_state.dart';
import '../vehicles_table.dart';

part 'attachments_dao.g.dart';

/// Queries on the `attachments` table.
///
/// Accepts and returns domain models only. Reads are limited to live
/// attachments (`deleted = 0`); the state of the entity they belong to is
/// checked by the repository on writes, since the table has no foreign key.
/// The physical deletes are in `TrashDao`.
@DriftAccessor(tables: [Attachments, LogEntries, Vehicles, Owners])
class AttachmentsDao extends DatabaseAccessor<AppDatabase>
    with _$AttachmentsDaoMixin {
  /// Creates the DAO on [db]. Obtain it through `AppDatabase.attachmentsDao`.
  AttachmentsDao(super.db);

  /// Converter used to compare `entity_type` with plain codes.
  static const AttachmentEntityTypeConverter _entityCodes =
      AttachmentEntityTypeConverter();

  /// Storage code of [type].
  static String _code(AttachmentEntityType type) => _entityCodes.toSql(type);

  /// Condition: the row belongs to [target].
  Expression<bool> _ofTarget($AttachmentsTable a, AttachmentTarget target) =>
      a.entityType.equals(_code(target.entityType)) &
      a.entityId.equals(target.entityId);

  /// Select of the live attachments of [target], in their display order:
  /// by `sort_order`, then by creation instant, then by id so the order is
  /// always stable.
  SimpleSelectStatement<$AttachmentsTable, AttachmentRow> _liveOf(
    AttachmentTarget target,
  ) =>
      select(attachments)
        ..where((a) => _ofTarget(a, target) & a.deleted.equals(false))
        ..orderBy([
          (a) => OrderingTerm.asc(a.sortOrder),
          (a) => OrderingTerm.asc(a.createdAt),
          (a) => OrderingTerm.asc(a.id),
        ]);

  /// Converts a list of rows into domain models.
  static List<Attachment> _toModels(List<AttachmentRow> rows) =>
      [for (final r in rows) r.toModel()];

  /// Emits the live attachments of [target] now and after every change.
  Stream<List<Attachment>> watchLiveOf(AttachmentTarget target) =>
      _liveOf(target).watch().map(_toModels);

  /// Returns the live attachments of [target] once.
  Future<List<Attachment>> getLiveOf(AttachmentTarget target) =>
      _liveOf(target).get().then(_toModels);

  /// Select of the live attachment with [id].
  SimpleSelectStatement<$AttachmentsTable, AttachmentRow> _liveById(
    String id,
  ) =>
      select(attachments)
        ..where((a) => a.id.equals(id) & a.deleted.equals(false));

  /// Returns the live attachment with [id], or `null`.
  Future<Attachment?> getLiveById(String id) async =>
      (await _liveById(id).getSingleOrNull())?.toModel();

  /// Emits what [getLiveById] returns, now and after every change.
  Stream<Attachment?> watchLiveById(String id) =>
      _liveById(id).watchSingleOrNull().map((row) => row?.toModel());

  /// Returns the soft-deleted attachment with [id], or `null` if it is
  /// missing or still live.
  Future<Attachment?> getDeletedById(String id) async {
    final row = await (select(attachments)
          ..where((a) => a.id.equals(id) & a.deleted.equals(true)))
        .getSingleOrNull();
    return row?.toModel();
  }

  /// The `sort_order` a new attachment of [target] gets: one more than the
  /// highest of its rows, deleted ones included (so an undone delete never
  /// collides), or 0 for the first.
  Future<int> nextSortOrder(AttachmentTarget target) async {
    final highest = attachments.sortOrder.max();
    final row = await (selectOnly(attachments)
          ..addColumns([highest])
          ..where(_ofTarget(attachments, target)))
        .getSingle();
    final value = row.read(highest);
    return value == null ? 0 : value + 1;
  }

  /// Whether [target] exists and can be written to: a live owner, or the
  /// [VehicleState] of the vehicle a live vehicle target or a live entry
  /// target belongs to.
  ///
  /// There is no foreign key (the table is polymorphic), so this is the only
  /// check that an attachment is written for something the user can see,
  /// and not for an archived vehicle, which is read-only.
  Future<VehicleState> targetStateOf(AttachmentTarget target) async {
    final id = target.entityId;
    switch (target.entityType) {
      case AttachmentEntityType.owner:
        final rows = await (select(owners)
              ..where((o) => o.id.equals(id) & o.deleted.equals(false))
              ..limit(1))
            .get();
        return rows.isEmpty ? VehicleState.absent : VehicleState.active;
      case AttachmentEntityType.vehicle:
        return vehicleStateOf(id);
      case AttachmentEntityType.logEntry:
        final query = selectOnly(logEntries).join([
          innerJoin(vehicles, vehicles.id.equalsExp(logEntries.vehicleId)),
        ])
          ..addColumns([vehicles.archivedAt])
          ..where(
            logEntries.id.equals(id) &
                logEntries.deleted.equals(false) &
                vehicles.deleted.equals(false),
          )
          ..limit(1);
        final row = await query.getSingleOrNull();
        if (row == null) return VehicleState.absent;
        return row.read(vehicles.archivedAt) == null
            ? VehicleState.active
            : VehicleState.archived;
    }
  }

  /// Emits, for the live entries of the vehicle [vehicleId], how many live
  /// attachments each has; entries without attachments are left out.
  Stream<Map<String, int>> watchLiveCountsOfEntries(String vehicleId) {
    final count = attachments.id.count();
    final query = selectOnly(attachments).join([
      innerJoin(
        logEntries,
        logEntries.id.equalsExp(attachments.entityId),
        useColumns: false,
      ),
    ])
      ..addColumns([attachments.entityId, count])
      ..where(
        attachments.entityType.equals(_code(AttachmentEntityType.logEntry)) &
            attachments.deleted.equals(false) &
            logEntries.vehicleId.equals(vehicleId) &
            logEntries.deleted.equals(false),
      )
      ..groupBy([attachments.entityId]);
    return query.watch().map(
          (rows) => {
            for (final row in rows)
              row.read(attachments.entityId)!: row.read(count) ?? 0,
          },
        );
  }

  /// Select of the number and total size of **every** attachment row, live
  /// or deleted: the files a backup package carries.
  JoinedSelectStatement<$AttachmentsTable, AttachmentRow> _totals(
    Expression<int> count,
    Expression<int> bytes,
  ) =>
      selectOnly(attachments)..addColumns([count, bytes]);

  /// Emits the number and total size of every attachment row, live or
  /// deleted, now and after every change.
  Stream<AttachmentTotals> watchTotals() {
    final count = attachments.id.count();
    final bytes = attachments.sizeBytes.sum();
    return _totals(count, bytes).watchSingle().map(
          (row) => AttachmentTotals(
            count: row.read(count) ?? 0,
            bytes: row.read(bytes) ?? 0,
          ),
        );
  }

  /// The relative paths of the files of every attachment row, live or
  /// deleted: the files that must exist under `attachments/`.
  Future<Set<String>> allRelativePaths() async {
    final rows = await (selectOnly(attachments)
          ..addColumns([attachments.relativePath]))
        .get();
    return {for (final r in rows) r.read(attachments.relativePath)!};
  }

  /// Inserts [attachment] as a new live row.
  Future<void> insertAttachment(Attachment attachment) =>
      into(attachments).insert(attachment.toInsertCompanion());

  /// Sets the caption of the live attachment [id] (`null` clears it) and
  /// its `updated_at`. Returns the number of rows changed.
  Future<int> updateCaption(String id, String? caption, DateTime at) =>
      _whereLive(id).write(
        AttachmentsCompanion(caption: Value(caption), updatedAt: Value(at)),
      );

  /// Sets the `sort_order` of the live attachment [id] and its
  /// `updated_at`. Returns the number of rows changed.
  Future<int> updateSortOrder(String id, int sortOrder, DateTime at) =>
      _whereLive(id).write(
        AttachmentsCompanion(
          sortOrder: Value(sortOrder),
          updatedAt: Value(at),
        ),
      );

  /// Marks the live attachment [id] as deleted at [at], setting `deleted`
  /// and `deleted_at` together. The file stays on disk. Returns the number
  /// of rows changed.
  Future<int> softDeleteLive(String id, DateTime at) => _whereLive(id).write(
        AttachmentsCompanion(
          deleted: const Value(true),
          updatedAt: Value(at),
          deletedAt: Value(at),
        ),
      );

  /// Brings the soft-deleted attachment [id] back at [at], clearing
  /// `deleted` and `deleted_at` together. Returns the number of rows
  /// changed.
  Future<int> restoreDeleted(String id, DateTime at) => (update(attachments)
            ..where((a) => a.id.equals(id) & a.deleted.equals(true)))
          .write(
        AttachmentsCompanion(
          deleted: const Value(false),
          updatedAt: Value(at),
          deletedAt: const Value(null),
        ),
      );

  /// Update statement restricted to the live attachment with [id].
  UpdateStatement<$AttachmentsTable, AttachmentRow> _whereLive(String id) =>
      update(attachments)
        ..where((a) => a.id.equals(id) & a.deleted.equals(false));
}
