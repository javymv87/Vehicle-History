import 'dart:io';
import 'dart:typed_data';

import 'package:vehicle_history/data/attachments/attachment_store.dart';
import 'package:vehicle_history/data/models/attachment.dart';
import 'package:vehicle_history/data/repositories/repository_exceptions.dart';

/// In-memory [AttachmentStore]: the files are byte lists, by path.
///
/// Mirrors [IoAttachmentStore] closely enough for the repository and
/// cleanup tests; the real file operations are tested on a temporary
/// directory.
class MemoryAttachmentStore implements AttachmentStore {
  /// The stored files, by relative path (`attachments/<id>.<ext>`).
  final Map<String, Uint8List> stored = {};

  /// The staged files, by absolute path, with their session.
  final Map<String, ({String session, Uint8List bytes})> staged = {};

  /// When set, moving the staged file at this path fails.
  String? failMoveOf;

  /// Counter for unique staged names.
  int _next = 1;

  /// Root of the fake paths.
  static const String root = '/memory';

  @override
  String absolutePath(String relativePath) => '$root/$relativePath';

  @override
  Future<bool> exists(String relativePath) async =>
      stored.containsKey(relativePath);

  @override
  Future<StagedFile> stage(
    String sessionId, {
    required Stream<List<int>> content,
    required String fileName,
    required String mimeType,
  }) async {
    final builder = BytesBuilder();
    await for (final chunk in content) {
      builder.add(chunk);
      if (builder.length > maxAttachmentBytes) {
        throw AttachmentTooLargeException(builder.length);
      }
    }
    final path = '$root/$attachmentsStagingDirName/$sessionId/'
        '${_next++}.${storedExtensionFor(fileName)}';
    final bytes = builder.takeBytes();
    staged[path] = (session: sessionId, bytes: bytes);
    return StagedFile(
      path: path,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: bytes.length,
    );
  }

  /// Stages [bytes] directly, as if picked, in [sessionId].
  Future<StagedFile> stageBytes(
    List<int> bytes, {
    String sessionId = 'session',
    String fileName = 'photo.jpg',
    String mimeType = 'image/jpeg',
  }) =>
      stage(
        sessionId,
        content: Stream.value(bytes),
        fileName: fileName,
        mimeType: mimeType,
      );

  @override
  Future<void> moveIntoPlace(String stagedPath, String relativePath) async {
    final file = staged[stagedPath];
    if (file == null || stagedPath == failMoveOf) {
      throw FileSystemException('cannot move', stagedPath);
    }
    staged.remove(stagedPath);
    stored[relativePath] = file.bytes;
  }

  @override
  Future<void> delete(String relativePath) async {
    stored.remove(relativePath);
  }

  @override
  Future<void> discardStaging(String sessionId) async {
    staged.removeWhere((_, file) => file.session == sessionId);
  }

  @override
  Future<void> wipeStaging() async => staged.clear();

  @override
  Future<Set<String>> listStored() async => stored.keys.toSet();
}
