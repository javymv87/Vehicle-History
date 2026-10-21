import '../models/attachment.dart';
import '../repositories/repository_support.dart';
import 'attachment_picker.dart';
import 'attachment_store.dart';

/// Copies picked files into a form session's staging directory
/// (`attachments_tmp/<session>/`), where they wait until the form is saved
/// (the repository moves them into `attachments/`) or cancelled
/// ([discard]). Whatever is left there is wiped at the next app start.
class AttachmentStaging {
  /// Creates the staging service on [_store].
  const AttachmentStaging(this._store);

  /// The files on disk.
  final AttachmentStore _store;

  /// A new, unique form session id.
  String newSession() => newId();

  /// Copies [file] into the staging directory of [sessionId].
  ///
  /// The MIME type is the one the platform reported or, without one, the
  /// one of the file's extension. Throws `AttachmentTooLargeException`
  /// above [maxAttachmentBytes], leaving nothing behind.
  Future<StagedFile> stage(String sessionId, PickedFile file) => _store.stage(
        sessionId,
        content: file.openRead(),
        fileName: file.name,
        mimeType: file.mimeType ?? mimeTypeForFileName(file.name),
      );

  /// Deletes what is left in the staging directory of [sessionId].
  Future<void> discard(String sessionId) => _store.discardStaging(sessionId);
}
