import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/attachments/attachment_picker.dart';
import '../../../data/attachments/file_opener.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/attachment.dart';
import '../../../data/platform/native_files.dart';
import '../../../data/repositories/repository_exceptions.dart';
import '../../../shared/utils/action_result.dart';

/// Stages the files picked from [source] into a new session of the staging
/// directory and returns them; files above 25 MB are left out and counted.
///
/// Shared by the attachment actions and the entry form. Deletes the copy
/// each picker leaves in the cache ([PickedFile.deleteSource]). Throws what
/// the picker throws ([AttachmentPickException]).
Future<({List<StagedFile> staged, int tooLarge})> pickAndStage(
  Ref ref,
  AttachmentSource source,
  String sessionId,
) async {
  final picked = await ref.read(attachmentPickerProvider).pick(source);
  final staging = ref.read(attachmentStagingProvider);
  final staged = <StagedFile>[];
  var tooLarge = 0;
  for (final file in picked) {
    try {
      staged.add(await staging.stage(sessionId, file));
    } on AttachmentTooLargeException {
      tooLarge++;
    } finally {
      // The staged copy is ours; the picker's own copy in the cache is
      // not needed any more, staged or refused.
      await file.deleteSource?.call();
    }
  }
  return (staged: staged, tooLarge: tooLarge);
}

/// The actions on saved attachments, from the entry detail, the vehicle's
/// Documents tab, the owner detail and the viewer: add, open, save to,
/// edit the caption, delete and undo.
///
/// Its state is whether an action that works on files is running (picking,
/// copying, saving), which shows a progress indicator. Kept alive like the
/// deletion controllers: the Undo snackbar outlives the page that deleted.
class AttachmentActionsController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Lets the user pick files from [source] and adds them to [target].
  ///
  /// Succeeds with the number of attachments added (0 when the user
  /// cancelled). Fails with [ActionError.attachmentTooLarge] when nothing
  /// could be added because every file was above 25 MB, or with the reason
  /// the picker or the save failed. The staging session is always
  /// discarded.
  Future<ActionResult<int>> addFrom(
    AttachmentTarget target,
    AttachmentSource source,
  ) async {
    state = true;
    final staging = ref.read(attachmentStagingProvider);
    final session = staging.newSession();
    try {
      return await runAction(() async {
        final picked = await pickAndStage(ref, source, session);
        if (picked.staged.isEmpty && picked.tooLarge > 0) {
          throw const AttachmentTooLargeException(maxAttachmentBytes + 1);
        }
        final repository = ref.read(attachmentRepositoryProvider);
        for (final file in picked.staged) {
          await repository.create(target, file);
        }
        return picked.staged.length;
      });
    } finally {
      await staging.discard(session);
      state = false;
    }
  }

  /// Opens [attachment] with the phone's own app.
  ///
  /// Fails with [ActionError.openNoApp] when no app handles it and with
  /// [ActionError.attachmentFileMissing] when its file is missing.
  Future<ActionResult<void>> open(Attachment attachment) async {
    final repository = ref.read(attachmentRepositoryProvider);
    final outcome = await ref
        .read(fileOpenerProvider)
        .open(repository.filePathOf(attachment), attachment.mimeType);
    return switch (outcome) {
      OpenFileOutcome.opened => const ActionSuccess(null),
      OpenFileOutcome.noApp => const ActionFailure(ActionError.openNoApp),
      OpenFileOutcome.notFound =>
        const ActionFailure(ActionError.attachmentFileMissing),
      OpenFileOutcome.failed => const ActionFailure(ActionError.unexpected),
    };
  }

  /// Copies the file of [attachment] where the user chooses, under its
  /// original name, through the native "save as".
  ///
  /// Succeeds with `true` once saved and `false` if the user cancelled.
  Future<ActionResult<bool>> saveTo(Attachment attachment) async {
    final repository = ref.read(attachmentRepositoryProvider);
    if (!await repository.fileExists(attachment)) {
      return const ActionFailure(ActionError.attachmentFileMissing);
    }
    state = true;
    try {
      return await runAction(
        () async =>
            await ref.read(nativeFilesProvider).saveFile(
                  sourcePath: repository.filePathOf(attachment),
                  suggestedName: attachment.fileName,
                  mimeType: attachment.mimeType,
                ) ==
            SaveFileOutcome.saved,
      );
    } finally {
      state = false;
    }
  }

  /// Copies the files of [attachments] (a selection) where the user
  /// chooses, under their original names: the "save as" dialog for one, a
  /// folder for several.
  ///
  /// Succeeds with the number of files saved, 0 when the user cancelled.
  /// Fails with [ActionError.attachmentFileMissing], saving nothing, when a
  /// file is missing on the phone.
  Future<ActionResult<int>> saveManyTo(List<Attachment> attachments) async {
    if (attachments.length == 1) {
      return switch (await saveTo(attachments.single)) {
        ActionSuccess(:final value) => ActionSuccess(value ? 1 : 0),
        ActionFailure(:final error) => ActionFailure(error),
      };
    }
    final files = await _nativeFilesOf(attachments);
    if (files == null) {
      return const ActionFailure(ActionError.attachmentFileMissing);
    }
    state = true;
    try {
      return await runAction(
        () async =>
            await ref.read(nativeFilesProvider).saveFilesToFolder(files) ?? 0,
      );
    } finally {
      state = false;
    }
  }

  /// Offers the files of [attachments] (one or a selection) to another app
  /// through the system share sheet, under their original names.
  ///
  /// Fails with [ActionError.attachmentFileMissing], sharing nothing, when a
  /// file is missing on the phone, and with [ActionError.shareFailed] when
  /// the system could not share them.
  Future<ActionResult<void>> share(List<Attachment> attachments) async {
    final files = await _nativeFilesOf(attachments);
    if (files == null) {
      return const ActionFailure(ActionError.attachmentFileMissing);
    }
    state = true;
    try {
      await ref.read(nativeFilesProvider).shareFiles(files);
      return const ActionSuccess(null);
    } on PlatformException {
      return const ActionFailure(ActionError.shareFailed);
    } finally {
      state = false;
    }
  }

  /// The files of [attachments] for the native side, or `null` when one of
  /// them is missing on the phone.
  Future<List<NativeFile>?> _nativeFilesOf(
    List<Attachment> attachments,
  ) async {
    final repository = ref.read(attachmentRepositoryProvider);
    final files = <NativeFile>[];
    for (final attachment in attachments) {
      if (!await repository.fileExists(attachment)) return null;
      files.add(
        NativeFile(
          path: repository.filePathOf(attachment),
          name: attachment.fileName,
          mimeType: attachment.mimeType,
        ),
      );
    }
    return files;
  }

  /// Sets the caption of the attachment [id]; blank clears it.
  Future<ActionResult<Attachment>> updateCaption(String id, String? caption) =>
      runAction(
        () => ref.read(attachmentRepositoryProvider).updateCaption(id, caption),
      );

  /// Soft-deletes the attachment [id].
  Future<ActionResult<void>> delete(String id) =>
      runAction(() => ref.read(attachmentRepositoryProvider).delete(id));

  /// Brings back the attachment [id] deleted by [delete].
  Future<ActionResult<Attachment>> undo(String id) =>
      runAction(() => ref.read(attachmentRepositoryProvider).restore(id));

  /// Soft-deletes the attachments [ids] (a selection) together.
  Future<ActionResult<void>> deleteMany(List<String> ids) =>
      runAction(() => ref.read(attachmentRepositoryProvider).deleteMany(ids));

  /// Brings back together the attachments [ids] deleted by [deleteMany].
  Future<ActionResult<List<Attachment>>> undoMany(List<String> ids) =>
      runAction(() => ref.read(attachmentRepositoryProvider).restoreMany(ids));
}

/// The app-wide [AttachmentActionsController].
final attachmentActionsControllerProvider =
    NotifierProvider<AttachmentActionsController, bool>(
  AttachmentActionsController.new,
);
