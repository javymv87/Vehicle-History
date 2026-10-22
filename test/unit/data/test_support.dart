import 'package:drift/drift.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:drift/native.dart';
import 'package:vehicle_history/data/attachments/attachment_store.dart';
import 'package:vehicle_history/data/data_providers.dart';
import 'package:vehicle_history/data/db/app_database.dart';
import 'package:vehicle_history/data/repositories/attachment_writer.dart';

import '../../support/memory_attachment_store.dart';

export '../../support/memory_attachment_store.dart';

/// Opens a fresh, empty in-memory database.
///
/// Each test gets its own instance, so drift's warning about several open
/// databases does not apply here and is silenced.
AppDatabase openTestDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase.forExecutor(NativeDatabase.memory());
}

/// A controllable UTC clock for deterministic timestamps.
class FakeClock {
  /// Starts the clock at [start], which must be UTC.
  FakeClock([DateTime? start])
      : _now = start ?? DateTime.utc(2024, 3, 4, 10, 30);

  /// The instant the clock currently returns.
  DateTime _now;

  /// Returns the current fake instant. Pass this as the repository clock.
  DateTime call() => _now;

  /// Moves the clock forward by [step].
  void advance([Duration step = const Duration(minutes: 1)]) {
    _now = _now.add(step);
  }
}

/// The attachment writer on [db], moving files with [store] (a new
/// in-memory one by default).
AttachmentWriter attachmentWriterOf(AppDatabase db, [AttachmentStore? store]) =>
    AttachmentWriter(
      db.attachmentsDao,
      db.auditLogDao,
      store ?? MemoryAttachmentStore(),
    );

/// Overrides that keep the app's files in memory: the support directory
/// and the attachment store ([store], a new one by default), for tests that
/// read `databaseReadyProvider`.
List<Override> memoryFileOverrides([MemoryAttachmentStore? store]) => [
      appSupportDirectoryProvider
          .overrideWith((ref) async => MemoryAttachmentStore.root),
      attachmentStoreProvider
          .overrideWithValue(store ?? MemoryAttachmentStore()),
    ];
