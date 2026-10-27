import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/navigation.dart';
import '../../../app/router/app_routes.dart';
import '../../../data/models/attachment.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../controllers/attachment_actions_controller.dart';
import '../controllers/attachment_list_controller.dart';
import '../widgets/attachment_actions.dart';
import '../widgets/attachment_thumbnail.dart';

/// The full-screen image viewer (U22–U26): the image [attachmentId] with
/// pinch zoom, the other images of the same entry, vehicle or owner a swipe
/// away, the caption (tap to edit) and the actions "Share", "Save to…"
/// and "Delete". The id comes from the path; an unknown or deleted id shows a
/// not-found page.
class AttachmentViewerPage extends ConsumerStatefulWidget {
  /// Creates the viewer opened on the image [attachmentId].
  const AttachmentViewerPage({super.key, required this.attachmentId});

  /// Id of the image shown first, from the path.
  final String attachmentId;

  @override
  ConsumerState<AttachmentViewerPage> createState() =>
      _AttachmentViewerPageState();
}

class _AttachmentViewerPageState extends ConsumerState<AttachmentViewerPage> {
  /// The entity of the first image, kept once found: the viewer goes on
  /// showing the other images of that entity after the first is deleted.
  AttachmentTarget? _target;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = _target;
    if (target == null) {
      final first = ref.watch(attachmentProvider(widget.attachmentId));
      return first.when(
        skipLoadingOnReload: true,
        loading: () => const _LoadingPage(),
        error: (error, stackTrace) => Scaffold(
          appBar: AppBar(),
          body: MessageView(icon: Icons.error_outline, message: l10n.loadError),
        ),
        data: (attachment) {
          if (attachment == null) {
            return NotFoundPage(message: l10n.errorAttachmentNotFound);
          }
          _target = attachment.target;
          return _imagesOf(attachment.target);
        },
      );
    }
    return _imagesOf(target);
  }

  /// The pager over the live images of [target], opened on the first one.
  Widget _imagesOf(AttachmentTarget target) {
    final l10n = AppLocalizations.of(context);
    final all = ref.watch(attachmentsProvider(target)).value;
    if (all == null) return const _LoadingPage();
    final images = [
      for (final a in all)
        if (a.isImage) a,
    ];
    if (images.isEmpty) {
      return NotFoundPage(message: l10n.errorAttachmentNotFound);
    }
    final first = images.indexWhere((a) => a.id == widget.attachmentId);
    return _Viewer(images: images, initialIndex: first < 0 ? 0 : first);
  }
}

/// A blank page with a progress indicator, while the images load.
class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
}

/// The pager over [images], holding the page shown.
class _Viewer extends ConsumerStatefulWidget {
  const _Viewer({required this.images, required this.initialIndex});

  final List<Attachment> images;
  final int initialIndex;

  @override
  ConsumerState<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends ConsumerState<_Viewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);

  /// Index of the image shown.
  late int _index = widget.initialIndex;

  @override
  void didUpdateWidget(covariant _Viewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An image was deleted or added: stay on a valid page.
    if (_index >= widget.images.length) {
      _index = widget.images.length - 1;
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final images = widget.images;
    final current = images[_index.clamp(0, images.length - 1)];
    final busy = ref.watch(attachmentActionsControllerProvider);
    // An archived vehicle: the picture can be shared and saved, not changed.
    final readOnly =
        ref.watch(attachmentTargetReadOnlyProvider(current.target));
    // White on black whatever the theme: a photo reads best on black.
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(
            l10n.attachmentViewerPosition(_index + 1, images.length),
          ),
          actions: [
            IconButton(
              tooltip: l10n.actionShare,
              icon: const Icon(Icons.share),
              onPressed:
                  busy ? null : () => shareAttachments(context, ref, [current]),
            ),
            IconButton(
              tooltip: l10n.actionSaveTo,
              icon: const Icon(Icons.save_alt),
              onPressed:
                  busy ? null : () => saveAttachmentTo(context, ref, current),
            ),
            if (!readOnly)
              IconButton(
                tooltip: l10n.actionDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => deleteAttachment(
                  context,
                  ref,
                  current,
                  // The last image gone: nothing left to show.
                  onDeleted: images.length == 1
                      ? () => context.popOrGo(AppRoutes.vehicles)
                      : null,
                ),
              ),
          ],
          bottom: busy
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(4),
                  child: LinearProgressIndicator(),
                )
              : null,
        ),
        body: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: images.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) =>
                    _ZoomableImage(attachment: images[index]),
              ),
            ),
            _Caption(attachment: current, readOnly: readOnly),
          ],
        ),
      ),
    );
  }
}

/// One image, at full width, with pinch zoom.
class _ZoomableImage extends ConsumerWidget {
  const _ZoomableImage({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(attachmentFilePathProvider(attachment));
    return InteractiveViewer(
      maxScale: 6,
      child: Center(
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          semanticLabel: attachment.caption ?? attachment.fileName,
          errorBuilder: (context, error, stackTrace) =>
              const AttachmentMissingPlaceholder(),
        ),
      ),
    );
  }
}

/// The caption under the image, or "Add a caption"; tapping it edits it.
/// When [readOnly], only the caption, if any, with nothing to tap.
class _Caption extends ConsumerWidget {
  const _Caption({required this.attachment, required this.readOnly});

  final Attachment attachment;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final caption = attachment.caption;
    if (readOnly && caption == null) {
      return const SafeArea(top: false, child: SizedBox.shrink());
    }
    return SafeArea(
      top: false,
      child: InkWell(
        onTap: readOnly
            ? null
            : () => editAttachmentCaption(context, ref, attachment),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    caption ?? l10n.addCaption,
                    style: caption == null
                        ? const TextStyle(fontStyle: FontStyle.italic)
                        : null,
                  ),
                ),
                if (!readOnly) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.edit, semanticLabel: l10n.actionEditCaption),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
