import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/log_entry.dart';
import '../../../shared/utils/action_result.dart';

/// Deletes history entries and undoes those deletions.
///
/// The state is the id of the last entry deleted, which the "Undo" snackbar
/// can still restore, or `null`. The provider is kept alive (not
/// auto-disposed) because the snackbar outlives the detail page that started
/// the deletion.
class LogEntryDeletionController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Soft-deletes the entry with [id].
  Future<ActionResult<void>> delete(String id) async {
    final result =
        await runAction(() => ref.read(logEntryRepositoryProvider).delete(id));
    if (result is ActionSuccess) state = id;
    return result;
  }

  /// Restores the entry with [id] deleted by [delete].
  ///
  /// Fails with [ActionError.vehicleNotFound] if its vehicle was deleted in
  /// the meantime.
  Future<ActionResult<LogEntry>> undo(String id) async {
    final result =
        await runAction(() => ref.read(logEntryRepositoryProvider).restore(id));
    if (state == id) state = null;
    return result;
  }
}

/// The app-wide [LogEntryDeletionController].
final logEntryDeletionControllerProvider =
    NotifierProvider<LogEntryDeletionController, String?>(
  LogEntryDeletionController.new,
);
