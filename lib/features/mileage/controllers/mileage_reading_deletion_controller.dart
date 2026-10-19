import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/mileage_reading.dart';
import '../../../shared/utils/action_result.dart';

/// Deletes the last odometer reading of a vehicle and undoes that deletion
/// (`Docs/03_features.md`, U14).
///
/// The state is the id of the last reading deleted, which the "Undo"
/// snackbar can still restore, or `null`. Kept alive (not auto-disposed)
/// because the snackbar outlives the bottom sheet, and possibly the page,
/// that started the deletion.
class MileageReadingDeletionController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Soft-deletes the reading with [id], which must be the last one and not
  /// the initial one.
  Future<ActionResult<void>> delete(String id) async {
    final result = await runAction(
      () => ref.read(mileageReadingRepositoryProvider).deleteLast(id),
    );
    if (result is ActionSuccess) state = id;
    return result;
  }

  /// Restores the reading with [id] deleted by [delete].
  ///
  /// Fails with [ActionError.newerReadingExists] if a more recent reading
  /// was added in the meantime, and [ActionError.vehicleNotFound] if the
  /// vehicle was deleted.
  Future<ActionResult<MileageReading>> undo(String id) async {
    final result = await runAction(
      () => ref.read(mileageReadingRepositoryProvider).restore(id),
    );
    if (state == id) state = null;
    return result;
  }
}

/// The app-wide [MileageReadingDeletionController].
final mileageReadingDeletionControllerProvider =
    NotifierProvider<MileageReadingDeletionController, String?>(
  MileageReadingDeletionController.new,
);
