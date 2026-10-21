import 'dart:async';
import 'dart:io';

import '../models/attachment.dart';
import '../repositories/repository_exceptions.dart';
import '../repositories/repository_support.dart';

/// The attachment files on disk (`Docs/02_data_model.md`, "Adjuntos").
///
/// Every file lives under `<root>/attachments/`, named
/// `<attachment id>.<ext>`, one file per `attachments` row; picked files
/// wait in `<root>/attachments_tmp/<session>/` until their form is saved or
/// cancelled. `<root>` is the application support directory, never the
/// gallery or public storage. Paths in the database are relative to it.
///
/// Injected so the repositories are tested on an in-memory fake; the app
/// uses [IoAttachmentStore].
abstract interface class AttachmentStore {
  /// The absolute path of the file at [relativePath] (as stored in
  /// `attachments.relative_path`).
  String absolutePath(String relativePath);

  /// Whether the file at [relativePath] exists.
  Future<bool> exists(String relativePath);

  /// Copies [content] into the staging directory of the form session
  /// [sessionId] and describes the copy.
  ///
  /// Throws [AttachmentTooLargeException], leaving nothing behind, as soon
  /// as the copy grows beyond [maxAttachmentBytes].
  Future<StagedFile> stage(
    String sessionId, {
    required Stream<List<int>> content,
    required String fileName,
    required String mimeType,
  });

  /// Moves the staged file at [stagedPath] to [relativePath], replacing a
  /// file already there.
  Future<void> moveIntoPlace(String stagedPath, String relativePath);

  /// Deletes the file at [relativePath] if it exists.
  Future<void> delete(String relativePath);

  /// Deletes the staging directory of the form session [sessionId] and
  /// whatever is still in it.
  Future<void> discardStaging(String sessionId);

  /// Deletes the whole staging directory: nothing in it survives an app
  /// start, since no form is open then.
  Future<void> wipeStaging();

  /// The relative paths of the files under `attachments/`.
  Future<Set<String>> listStored();
}

/// Deletes every file under `attachments/` that [referenced] does not name
/// (an orphan: its row is gone, or never committed) and returns how many
/// were deleted.
///
/// Rows whose file is missing are left alone: the row is kept and the UI
/// shows "File not found" for it.
Future<int> deleteOrphanFiles(
  AttachmentStore store,
  Set<String> referenced,
) async {
  var deleted = 0;
  for (final path in await store.listStored()) {
    if (!referenced.contains(path)) {
      await store.delete(path);
      deleted++;
    }
  }
  return deleted;
}

/// Deletes the files at [relativePaths] once their rows are gone, without
/// ever failing: a file that cannot be deleted now is an orphan, and the
/// sweep at the next app start removes it.
Future<void> deleteFilesQuietly(
  AttachmentStore store,
  Iterable<String> relativePaths,
) async {
  for (final path in relativePaths) {
    try {
      await store.delete(path);
    } on FileSystemException {
      // Left for the orphan sweep.
    }
  }
}

/// [AttachmentStore] on the real file system, under [root].
class IoAttachmentStore implements AttachmentStore {
  /// Creates the store under [root], normally the application support
  /// directory.
  IoAttachmentStore(this.root);

  /// The directory holding `attachments/` and `attachments_tmp/`.
  final String root;

  /// Platform path separator.
  static final String _sep = Platform.pathSeparator;

  /// The directory of the stored files.
  Directory get _storedDir => Directory('$root$_sep$attachmentsDirName');

  /// The directory of the staged files.
  Directory get _stagingDir =>
      Directory('$root$_sep$attachmentsStagingDirName');

  @override
  String absolutePath(String relativePath) =>
      '$root$_sep${relativePath.replaceAll('/', _sep)}';

  @override
  Future<bool> exists(String relativePath) =>
      File(absolutePath(relativePath)).exists();

  @override
  Future<StagedFile> stage(
    String sessionId, {
    required Stream<List<int>> content,
    required String fileName,
    required String mimeType,
  }) async {
    final dir = Directory('${_stagingDir.path}$_sep$sessionId');
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}$_sep${newId()}.${storedExtensionFor(fileName)}',
    );
    final sink = file.openWrite();
    var size = 0;
    try {
      await for (final chunk in content) {
        size += chunk.length;
        if (size > maxAttachmentBytes) {
          throw AttachmentTooLargeException(size);
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } on Object {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
    return StagedFile(
      path: file.path,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: size,
    );
  }

  @override
  Future<void> moveIntoPlace(String stagedPath, String relativePath) async {
    await _storedDir.create(recursive: true);
    final target = absolutePath(relativePath);
    try {
      // Staging and storage are in the same directory tree, so this is a
      // rename of the directory entry, not a copy.
      await File(stagedPath).rename(target);
    } on FileSystemException {
      await File(stagedPath).copy(target);
      await File(stagedPath).delete();
    }
  }

  @override
  Future<void> delete(String relativePath) async {
    final file = File(absolutePath(relativePath));
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> discardStaging(String sessionId) async {
    final dir = Directory('${_stagingDir.path}$_sep$sessionId');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<void> wipeStaging() async {
    if (await _stagingDir.exists()) await _stagingDir.delete(recursive: true);
  }

  @override
  Future<Set<String>> listStored() async {
    if (!await _storedDir.exists()) return {};
    return {
      await for (final entity in _storedDir.list(followLinks: false))
        if (entity is File)
          '$attachmentsDirName/${entity.uri.pathSegments.last}',
    };
  }
}
