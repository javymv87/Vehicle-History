import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/attachment.dart';

/// The live attachments of an entry, a vehicle or an owner, in display
/// order. Refreshes after every change.
final attachmentsProvider =
    StreamProvider.autoDispose.family<List<Attachment>, AttachmentTarget>(
  (ref, target) =>
      ref.watch(attachmentRepositoryProvider).watchByTarget(target),
);

/// The live attachment with the id from the viewer's path, or `null`.
final attachmentProvider =
    StreamProvider.autoDispose.family<Attachment?, String>(
  (ref, id) => ref.watch(attachmentRepositoryProvider).watchById(id),
);

/// How many live attachments each live entry of a vehicle has (the
/// paperclip of U24); entries without attachments are not in the map.
final entryAttachmentCountsProvider =
    StreamProvider.autoDispose.family<Map<String, int>, String>(
  (ref, vehicleId) =>
      ref.watch(attachmentRepositoryProvider).watchEntryCounts(vehicleId),
);

/// The absolute path of the file of an attachment.
final attachmentFilePathProvider =
    Provider.autoDispose.family<String, Attachment>(
  (ref, attachment) =>
      ref.watch(attachmentRepositoryProvider).filePathOf(attachment),
);

/// Whether the file of an attachment is on disk; a missing one is shown
/// with the "File not found" placeholder.
final attachmentFileExistsProvider =
    FutureProvider.autoDispose.family<bool, Attachment>(
  (ref, attachment) =>
      ref.watch(attachmentRepositoryProvider).fileExists(attachment),
);
