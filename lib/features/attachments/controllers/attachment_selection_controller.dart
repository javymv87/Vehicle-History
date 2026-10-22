import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/attachment.dart';

/// The attachments selected in the list of one entry, vehicle or owner
/// (U29): empty outside the selection mode, which a long press starts.
///
/// Screen-scoped state that is not in the database, so a `Notifier` family
/// keyed by the target and auto-disposed with the page, like the history
/// filters.
class AttachmentSelectionController extends Notifier<Set<String>> {
  /// Creates the selection of the attachments of [target].
  AttachmentSelectionController(this.target);

  /// The entry, vehicle or owner whose attachments are selected.
  final AttachmentTarget target;

  @override
  Set<String> build() => const {};

  /// Whether the selection mode is on.
  bool get isActive => state.isNotEmpty;

  /// Selects [id] if it is not selected, unselects it otherwise; the mode
  /// ends with the last one unselected.
  void toggle(String id) =>
      state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};

  /// Selects every attachment in [ids].
  void selectAll(Iterable<String> ids) => state = {...ids};

  /// Ends the selection mode.
  void clear() => state = const {};

  /// Drops from the selection what is no longer in [liveIds] (deleted
  /// meanwhile, here or from the viewer).
  void keepOnly(Set<String> liveIds) {
    if (state.every(liveIds.contains)) return;
    state = state.where(liveIds.contains).toSet();
  }
}

/// The selected attachments of a target, by target.
final attachmentSelectionProvider = NotifierProvider.autoDispose
    .family<AttachmentSelectionController, Set<String>, AttachmentTarget>(
  AttachmentSelectionController.new,
);
