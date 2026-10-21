import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/attachments/attachment_picker.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/attachment.dart';
import '../../../data/repositories/repository_exceptions.dart';
import '../../../shared/utils/action_result.dart';
import '../../attachments/controllers/attachment_actions_controller.dart';
import 'log_entry_form_controller.dart';

/// The attachment changes of an entry form not saved yet (U22): files
/// picked and waiting in the staging directory, and the saved attachments
/// the user removed.
class LogEntryAttachmentsDraft {
  /// Creates the draft.
  const LogEntryAttachmentsDraft({
    this.staged = const [],
    this.removedIds = const {},
    this.busy = false,
  });

  /// Files picked in this form, in the order they were picked.
  final List<StagedFile> staged;

  /// Ids of the entry's saved attachments removed in this form; they are
  /// soft-deleted when the form is saved.
  final Set<String> removedIds;

  /// Whether files are being picked and copied.
  final bool busy;

  /// Returns a copy with the given fields replaced.
  LogEntryAttachmentsDraft copyWith({
    List<StagedFile>? staged,
    Set<String>? removedIds,
    bool? busy,
  }) =>
      LogEntryAttachmentsDraft(
        staged: staged ?? this.staged,
        removedIds: removedIds ?? this.removedIds,
        busy: busy ?? this.busy,
      );
}

/// Holds the attachment draft of one entry form, and its staging session.
///
/// Auto-disposed with the form: whatever is still staged then (the form was
/// cancelled, or saved, which moved the files away) is deleted with the
/// session. A session the app never closed (it was killed) is wiped at the
/// next start.
class LogEntryAttachmentsController extends Notifier<LogEntryAttachmentsDraft> {
  /// Creates the controller for the form identified by [key].
  LogEntryAttachmentsController(this.key);

  /// Vehicle of the form, and the entry edited (`null` when creating).
  final LogEntryFormKey key;

  /// The staging session of this form, opened by [build].
  late String sessionId;

  @override
  LogEntryAttachmentsDraft build() {
    final staging = ref.read(attachmentStagingProvider);
    sessionId = staging.newSession();
    ref.onDispose(() => staging.discard(sessionId));
    return const LogEntryAttachmentsDraft();
  }

  /// Lets the user pick files from [source] and stages them.
  ///
  /// Succeeds with the number of files staged. Fails with
  /// [ActionError.attachmentTooLarge] when every picked file was above
  /// 25 MB, or with the reason the picker failed.
  Future<ActionResult<int>> add(AttachmentSource source) async {
    state = state.copyWith(busy: true);
    try {
      final result = await runAction(() async {
        final picked = await pickAndStage(ref, source, sessionId);
        if (picked.staged.isEmpty && picked.tooLarge > 0) {
          throw const AttachmentTooLargeException(maxAttachmentBytes + 1);
        }
        return picked.staged;
      });
      if (result case ActionSuccess(value: final staged)) {
        state = state.copyWith(staged: [...state.staged, ...staged]);
        return ActionSuccess(staged.length);
      }
      return switch (result) {
        ActionFailure(:final error) => ActionFailure(error),
        ActionSuccess() => const ActionSuccess(0),
      };
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Takes the staged [file] out of the draft. Its copy is deleted with the
  /// session.
  void removeStaged(StagedFile file) {
    state = state.copyWith(
      staged: [
        for (final f in state.staged)
          if (f != file) f,
      ],
    );
  }

  /// Marks the saved attachment [id] as removed; it is soft-deleted when
  /// the form is saved.
  void removeSaved(String id) {
    state = state.copyWith(removedIds: {...state.removedIds, id});
  }
}

/// The [LogEntryAttachmentsController] of an entry form.
final logEntryAttachmentsControllerProvider = NotifierProvider.autoDispose
    .family<LogEntryAttachmentsController, LogEntryAttachmentsDraft,
        LogEntryFormKey>(
  LogEntryAttachmentsController.new,
);
