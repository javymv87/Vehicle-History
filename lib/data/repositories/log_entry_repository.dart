import '../models/attachment.dart';
import '../models/calendar_date.dart';
import '../models/log_entry.dart';
import '../models/log_entry_filter.dart';
import '../models/log_entry_type.dart';

/// The only access path to persisted history entries.
///
/// Reads return live entries of live vehicles only: the entries of a deleted
/// vehicle are kept as they are and come back when the vehicle is restored.
/// Every write is recorded in the audit log in the same transaction. Errors
/// are reported as `RepositoryException` subtypes (see
/// `repository_exceptions.dart`).
abstract interface class LogEntryRepository {
  /// Emits the entries of the vehicle with [vehicleId] that pass [filter],
  /// now and after every change.
  ///
  /// Newest first: by day, then by creation instant within the same day.
  /// Emits an empty list for a vehicle that is missing or deleted.
  Stream<List<LogEntry>> watchByVehicle(
    String vehicleId, {
    LogEntryFilter filter = LogEntryFilter.none,
  });

  /// Returns the live entry with [id], or `null` if it is missing, deleted
  /// or belongs to a deleted vehicle.
  Future<LogEntry?> getById(String id);

  /// Emits what [getById] returns, now and after every change.
  Stream<LogEntry?> watchById(String id);

  /// Creates an entry for the vehicle with [vehicleId] and returns it with
  /// its id and timestamps set.
  ///
  /// [description] is trimmed and stored as `null` when blank. [km] is
  /// required when [LogEntryType.requiresKm] is true for [type], and stays
  /// inside the entry: it never changes the vehicle's odometer.
  ///
  /// Throws `InvalidFieldException` when [km] is missing for [type] or
  /// negative, [costCents] is negative, or [date] is after today for a type
  /// whose [LogEntryType.allowsFutureDate] is false, and
  /// `EntityNotFoundException`
  /// when the vehicle is missing or deleted.
  ///
  /// [attachments] are the files staged by the entry form: they become the
  /// entry's attachments in the same transaction, their files moved out of
  /// the staging directory (and removed again if the transaction fails).
  /// Throws `AttachmentTooLargeException` for a file above 25 MB.
  Future<LogEntry> create({
    required String vehicleId,
    required CalendarDate date,
    double? km,
    required LogEntryType type,
    String? description,
    int? costCents,
    List<StagedFile> attachments = const [],
  });

  /// Replaces every user-editable field of the entry with [id] and returns
  /// the updated entry. Passing `null` clears an optional field. The vehicle
  /// of an entry never changes.
  ///
  /// Throws the same `InvalidFieldException`s as [create], and
  /// `EntityNotFoundException` when the entry is missing, deleted or belongs
  /// to a deleted vehicle.
  ///
  /// In the same transaction, [addedAttachments] (staged by the form)
  /// become new attachments of the entry, and the live attachments of the
  /// entry with [removedAttachmentIds] are soft-deleted, like a delete from
  /// the detail page.
  Future<LogEntry> update(
    String id, {
    required CalendarDate date,
    double? km,
    required LogEntryType type,
    String? description,
    int? costCents,
    List<StagedFile> addedAttachments = const [],
    Set<String> removedAttachmentIds = const {},
  });

  /// Soft-deletes the entry with [id].
  ///
  /// Throws `EntityNotFoundException` if the entry is missing, already
  /// deleted, or belongs to a deleted vehicle.
  Future<void> delete(String id);

  /// Brings back the soft-deleted entry with [id], as "Undo" after
  /// [delete], and returns it.
  ///
  /// Recorded in the audit log as a `restore`. Throws
  /// `EntityNotFoundException` for the entry if no deleted entry has that
  /// id, and for the vehicle if the vehicle has been deleted in the
  /// meantime; nothing is written then.
  Future<LogEntry> restore(String id);
}
