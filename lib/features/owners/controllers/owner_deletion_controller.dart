import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/owner.dart';
import '../../../shared/utils/action_result.dart';

/// Deletes owners and undoes those deletions.
///
/// The state is the id of the last owner deleted, which the "Undo" snackbar
/// can still restore, or `null`. The provider is kept alive (not
/// auto-disposed) because the snackbar outlives the detail page that started
/// the deletion.
class OwnerDeletionController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Soft-deletes the owner with [id].
  ///
  /// Fails with [ActionError.ownerHasVehicles], writing nothing, while the
  /// owner still has live vehicles.
  Future<ActionResult<void>> delete(String id) async {
    final result =
        await runAction(() => ref.read(ownerRepositoryProvider).delete(id));
    if (result is ActionSuccess) state = id;
    return result;
  }

  /// Restores the owner with [id] deleted by [delete].
  Future<ActionResult<Owner>> undo(String id) async {
    final result =
        await runAction(() => ref.read(ownerRepositoryProvider).restore(id));
    if (state == id) state = null;
    return result;
  }
}

/// The app-wide [OwnerDeletionController].
final ownerDeletionControllerProvider =
    NotifierProvider<OwnerDeletionController, String?>(
  OwnerDeletionController.new,
);
