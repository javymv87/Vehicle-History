import '../db/daos/attachments_dao.dart';
import '../db/vehicle_state.dart';
import '../models/attachment.dart';
import '../models/audit_entry.dart';
import 'attachment_repository.dart';
import 'attachment_writer.dart';
import 'repository_exceptions.dart';
import 'repository_support.dart';

/// [AttachmentRepository] backed by the local Drift database and the
/// attachment store.
class DriftAttachmentRepository implements AttachmentRepository {
  /// Creates the repository on [_attachments], writing through [_writer].
  ///
  /// [clock] must return UTC; it defaults to the system clock.
  DriftAttachmentRepository(
    this._attachments,
    this._writer, {
    UtcClock clock = systemUtcClock,
  }) : _clock = clock;

  /// Attachment queries.
  final AttachmentsDao _attachments;

  /// Inserts, deletes and audits attachments; owns the file store.
  final AttachmentWriter _writer;

  /// Source of `created_at`, `updated_at` and audit timestamps.
  final UtcClock _clock;

  @override
  Stream<List<Attachment>> watchByTarget(AttachmentTarget target) =>
      _attachments.watchLiveOf(target);

  @override
  Future<List<Attachment>> getByTarget(AttachmentTarget target) =>
      _attachments.getLiveOf(target);

  @override
  Stream<Attachment?> watchById(String id) => _attachments.watchLiveById(id);

  @override
  Stream<Map<String, int>> watchEntryCounts(String vehicleId) =>
      _attachments.watchLiveCountsOfEntries(vehicleId);

  @override
  Stream<AttachmentTotals> watchTotals() => _attachments.watchTotals();

  @override
  Future<Attachment> create(AttachmentTarget target, StagedFile file) async {
    final now = utcNow(_clock);
    AttachmentWriter.checkSize(file);
    return _writer.runWithMovedFiles(
      (moved) => _attachments.transaction(() async {
        await _requireActiveTarget(target);
        final added = await _writer.addStaged(target, [file], now, moved);
        return added.single;
      }),
    );
  }

  @override
  Future<Attachment> updateCaption(String id, String? caption) async {
    final now = utcNow(_clock);
    return _attachments.transaction(() async {
      final current = await _requireLive(id);
      await _requireActiveTarget(current.target);
      final trimmed = trimToNull(caption);
      await _attachments.updateCaption(id, trimmed, now);
      await _writer.record(id, AuditOperation.update, now);
      return current.copyWith(caption: trimmed, updatedAt: now);
    });
  }

  @override
  Future<void> reorder(AttachmentTarget target, List<String> orderedIds) {
    final now = utcNow(_clock);
    return _attachments.transaction(() async {
      await _requireActiveTarget(target);
      final current = await _attachments.getLiveOf(target);
      final currentIds = {for (final a in current) a.id};
      final ordered = orderedIds.toSet();
      if (orderedIds.length != currentIds.length ||
          ordered.length != orderedIds.length ||
          !currentIds.containsAll(ordered)) {
        throw const InvalidFieldException(
          'order',
          'must name every attachment exactly once',
        );
      }
      final byId = {for (final a in current) a.id: a};
      for (final (index, id) in orderedIds.indexed) {
        if (byId[id]!.sortOrder == index) continue;
        await _attachments.updateSortOrder(id, index, now);
        await _writer.record(id, AuditOperation.update, now);
      }
    });
  }

  @override
  Future<void> delete(String id) => deleteMany([id]);

  @override
  Future<Attachment> restore(String id) async =>
      (await restoreMany([id])).single;

  @override
  Future<void> deleteMany(List<String> ids) {
    final now = utcNow(_clock);
    return _attachments.transaction(() async {
      for (final id in ids.toSet()) {
        final current = await _requireLive(id);
        await _requireActiveTarget(current.target);
        await _writer.softDelete(current.target, id, now);
      }
    });
  }

  @override
  Future<List<Attachment>> restoreMany(List<String> ids) {
    final now = utcNow(_clock);
    return _attachments.transaction(() async {
      final restored = <Attachment>[];
      for (final id in ids.toSet()) {
        final deleted = await _attachments.getDeletedById(id);
        if (deleted == null) {
          throw EntityNotFoundException(AuditEntityType.attachment, id);
        }
        // What it belongs to may have been deleted or archived since: the
        // attachment would come back invisible or read-only, so the undo is
        // refused instead.
        await _requireActiveTarget(deleted.target);
        await _attachments.restoreDeleted(id, now);
        await _writer.record(id, AuditOperation.restore, now);
        restored.add(deleted.copyWith(updatedAt: now));
      }
      return restored;
    });
  }

  @override
  String filePathOf(Attachment attachment) =>
      _writer.store.absolutePath(attachment.relativePath);

  @override
  Future<bool> fileExists(Attachment attachment) =>
      _writer.store.exists(attachment.relativePath);

  /// Throws `EntityNotFoundException` for the entity unless [target] is
  /// live, and `VehicleArchivedException` when the vehicle it belongs to is
  /// archived: its attachments are read-only then.
  Future<void> _requireActiveTarget(AttachmentTarget target) async {
    switch (await _attachments.targetStateOf(target)) {
      case VehicleState.active:
        return;
      case VehicleState.archived:
        throw VehicleArchivedException(
          auditEntityTypeOf(target.entityType),
          target.entityId,
        );
      case VehicleState.absent:
        throw EntityNotFoundException(
          auditEntityTypeOf(target.entityType),
          target.entityId,
        );
    }
  }

  /// Returns the live attachment [id] or throws `EntityNotFoundException`.
  Future<Attachment> _requireLive(String id) async {
    final attachment = await _attachments.getLiveById(id);
    if (attachment == null) {
      throw EntityNotFoundException(AuditEntityType.attachment, id);
    }
    return attachment;
  }
}

/// The audit entity type naming the same kind of entity as [type].
AuditEntityType auditEntityTypeOf(AttachmentEntityType type) => switch (type) {
      AttachmentEntityType.logEntry => AuditEntityType.logEntry,
      AttachmentEntityType.vehicle => AuditEntityType.vehicle,
      AttachmentEntityType.owner => AuditEntityType.owner,
    };
