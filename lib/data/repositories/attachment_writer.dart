import '../attachments/attachment_store.dart';
import '../db/daos/attachments_dao.dart';
import '../db/daos/audit_log_dao.dart';
import '../models/attachment.dart';
import '../models/audit_entry.dart';
import 'repository_exceptions.dart';
import 'repository_support.dart';

/// The attachment writes shared by the attachment repository and the
/// history entry repository, which saves an entry together with the files
/// picked in its form.
///
/// Every method must run inside a transaction opened by the caller, so the
/// rows and their audit entries commit or roll back with the rest of the
/// change. Files moved into place are reported to the caller, which removes
/// them if the transaction fails ([runWithMovedFiles]).
class AttachmentWriter {
  /// Creates the writer on [_attachments], auditing through [_audit] and
  /// moving files with [_store].
  const AttachmentWriter(this._attachments, this._audit, this._store);

  /// Attachment queries.
  final AttachmentsDao _attachments;

  /// Audit log writes.
  final AuditLogDao _audit;

  /// The files on disk.
  final AttachmentStore _store;

  /// The file store, for callers that need the paths.
  AttachmentStore get store => _store;

  /// Throws `AttachmentTooLargeException` for a staged file above
  /// [maxAttachmentBytes]. Checked before any transaction starts.
  static void checkSize(StagedFile file) {
    if (file.sizeBytes > maxAttachmentBytes || file.sizeBytes < 0) {
      throw AttachmentTooLargeException(file.sizeBytes);
    }
  }

  /// Inserts one attachment of [target] per staged file in [files], after
  /// the existing ones and in the given order, and moves each file into
  /// place, adding its relative path to [moved] once it is there.
  ///
  /// The target is not checked here: the caller has just created or
  /// checked it in the same transaction.
  Future<List<Attachment>> addStaged(
    AttachmentTarget target,
    List<StagedFile> files,
    DateTime now,
    List<String> moved,
  ) async {
    if (files.isEmpty) return const [];
    final first = await _attachments.nextSortOrder(target);
    final added = <Attachment>[];
    for (final (index, file) in files.indexed) {
      checkSize(file);
      final id = newId();
      final attachment = Attachment(
        id: id,
        target: target,
        kind: file.kind,
        fileName: file.fileName,
        mimeType: file.mimeType,
        relativePath: attachmentRelativePath(id, file.fileName),
        sizeBytes: file.sizeBytes,
        sortOrder: first + index,
        createdAt: now,
        updatedAt: now,
      );
      await _attachments.insertAttachment(attachment);
      await record(id, AuditOperation.create, now);
      await _store.moveIntoPlace(file.path, attachment.relativePath);
      moved.add(attachment.relativePath);
      added.add(attachment);
    }
    return added;
  }

  /// Soft-deletes the live attachment [id] of [target] at [now].
  ///
  /// Throws `EntityNotFoundException` when no live attachment of [target]
  /// has that id: a form can only remove what it shows.
  Future<void> softDelete(
    AttachmentTarget target,
    String id,
    DateTime now,
  ) async {
    final current = await _attachments.getLiveById(id);
    if (current == null || current.target != target) {
      throw EntityNotFoundException(AuditEntityType.attachment, id);
    }
    await _attachments.softDeleteLive(id, now);
    await record(id, AuditOperation.delete, now);
  }

  /// Appends the audit entry for [operation] on the attachment [id].
  Future<void> record(String id, AuditOperation operation, DateTime at) {
    return _audit.insertEntry(
      AuditEntry(
        id: newId(),
        entityType: AuditEntityType.attachment,
        entityId: id,
        operation: operation,
        at: at,
      ),
    );
  }

  /// Runs [body] with a list where it records the files it moved into
  /// place; if [body] throws (the transaction inside it rolled back), those
  /// files are deleted again before the error is rethrown, so no file is
  /// left without its row.
  Future<T> runWithMovedFiles<T>(
    Future<T> Function(List<String> moved) body,
  ) async {
    final moved = <String>[];
    try {
      return await body(moved);
    } on Object {
      await deleteFilesQuietly(_store, moved);
      rethrow;
    }
  }
}
