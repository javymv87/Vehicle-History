import 'dart:io';

import 'package:flutter/foundation.dart';

/// Empties the app's cache, the directory [directory] resolves to
/// (`getTemporaryDirectory`), and returns how many entries were deleted, or
/// `null` when it failed.
///
/// Only copies live there: what the camera, gallery and file pickers leave
/// behind (the app keeps its own copy under `attachments/`) and the files
/// prepared for sharing. Run at app start, before the database opens, so
/// no copy of a photo outlives the session that picked it. The directory
/// itself is kept: SQLite and the plugins create their files in it.
///
/// Like the other startup housekeeping it never stops the start: a failure
/// is logged and swallowed, and what could not be deleted is tried again at
/// the next start.
Future<int?> wipeTemporaryDirectorySafely(
  Future<Directory> Function() directory,
) async {
  try {
    final cache = await directory();
    if (!await cache.exists()) return 0;
    var deleted = 0;
    await for (final entity in cache.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
        deleted++;
      } on FileSystemException catch (error) {
        debugPrint('Cache entry not deleted: $error');
      }
    }
    return deleted;
    // Deliberately catches everything (a missing plugin in tests, a file
    // system error): nothing here may block the start.
    // ignore: avoid_catches_without_on_clauses
  } catch (error, stackTrace) {
    debugPrint('Cache wipe failed: $error\n$stackTrace');
    return null;
  }
}
