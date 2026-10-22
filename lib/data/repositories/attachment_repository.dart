import '../models/attachment.dart';

/// The only access path to the persisted attachments: their rows and,
/// through the attachment store, their files.
///
/// Reads return live attachments only. Every write is recorded in the audit
/// log (entity `attachment`) in the same transaction. A delete is a soft
/// delete: the file stays on disk until the 30-day cleanup or the purge of
/// what it belongs to. Errors are `RepositoryException` subtypes.
abstract interface class AttachmentRepository {
  /// Emits the live attachments of [target] in display order, now and
  /// after every change.
  Stream<List<Attachment>> watchByTarget(AttachmentTarget target);

  /// Returns the live attachments of [target] once, in display order.
  Future<List<Attachment>> getByTarget(AttachmentTarget target);

  /// Emits the live attachment with [id], or `null`, now and after every
  /// change.
  Stream<Attachment?> watchById(String id);

  /// Emits how many live attachments each live entry of the vehicle
  /// [vehicleId] has; entries without attachments are not in the map.
  Stream<Map<String, int>> watchEntryCounts(String vehicleId);

  /// Emits the number and total size of every attachment row, live or
  /// deleted: what a backup package carries.
  Stream<AttachmentTotals> watchTotals();

  /// Turns the staged [file] into a new attachment of [target], last in its
  /// order, and returns it.
  ///
  /// The file is moved from the staging directory into `attachments/` and
  /// the row inserted in one transaction; if the transaction fails the moved
  /// file is removed again. Throws `EntityNotFoundException` when [target]
  /// is missing or not live, and `AttachmentTooLargeException` above
  /// [maxAttachmentBytes].
  Future<Attachment> create(AttachmentTarget target, StagedFile file);

  /// Sets the caption of the attachment [id] (trimmed; blank clears it)
  /// and returns the updated attachment.
  ///
  /// Throws `EntityNotFoundException` when the attachment is missing or
  /// deleted.
  Future<Attachment> updateCaption(String id, String? caption);

  /// Puts the live attachments of [target] in the order of [orderedIds].
  ///
  /// [orderedIds] must name each live attachment of [target] exactly once;
  /// otherwise `InvalidFieldException` is thrown and nothing changes. Only
  /// the attachments whose position changes get an `update` audit row.
  Future<void> reorder(AttachmentTarget target, List<String> orderedIds);

  /// Soft-deletes the attachment [id]; its file stays on disk.
  ///
  /// Throws `EntityNotFoundException` when it is missing or already deleted.
  Future<void> delete(String id);

  /// Brings back the soft-deleted attachment [id], as "Undo" after
  /// [delete], and returns it.
  ///
  /// Throws `EntityNotFoundException` for the attachment if no deleted one
  /// has that id, and for its entity if that is no longer live.
  Future<Attachment> restore(String id);

  /// Soft-deletes the attachments [ids] (a selection) in one transaction,
  /// one audit row each; their files stay on disk.
  ///
  /// Throws `EntityNotFoundException` and deletes nothing when one of them
  /// is missing or already deleted.
  Future<void> deleteMany(List<String> ids);

  /// Brings back the soft-deleted attachments [ids] in one transaction, as
  /// the "Undo" of [deleteMany], and returns them.
  ///
  /// Throws like [restore] and restores nothing when one of them cannot
  /// come back.
  Future<List<Attachment>> restoreMany(List<String> ids);

  /// The absolute path of the file of [attachment].
  String filePathOf(Attachment attachment);

  /// Whether the file of [attachment] is on disk. A row whose file is
  /// missing is kept and shown with a "File not found" placeholder.
  Future<bool> fileExists(Attachment attachment);
}
