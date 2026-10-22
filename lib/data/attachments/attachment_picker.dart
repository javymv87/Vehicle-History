import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

/// Where the user takes a new attachment from (U22–U26 bottom sheet).
enum AttachmentSource {
  /// A new photo from the camera.
  camera,

  /// One or more photos from the gallery (Android 13+ photo picker).
  gallery,

  /// Any file, through the system file picker.
  file,
}

/// A file the user picked, not yet copied anywhere.
class PickedFile {
  /// Creates the description of a picked file.
  const PickedFile({
    required this.name,
    required this.openRead,
    this.mimeType,
    this.deleteSource,
  });

  /// The file name, shown to the user and kept as the attachment's name.
  final String name;

  /// The MIME type reported by the platform, if any.
  final String? mimeType;

  /// Opens the content as a stream of bytes, read once while staging.
  final Stream<List<int>> Function() openRead;

  /// Deletes the copy the platform picker left in the app's cache, once the
  /// file is staged (or refused); `null` when the picker leaves none.
  ///
  /// Never throws: a copy that cannot be deleted now goes with the cache,
  /// which is emptied at the next app start.
  final Future<void> Function()? deleteSource;
}

/// The name given to the [index]-th photo (0-based) of a pick made at the
/// local time [takenAt]: `IMG_yyyyMMdd_HHmmss.<ext>`, like the Android
/// camera, with `_2`, `_3`, … from the second photo of the same pick. The
/// extension is the one of the plugin's [pluginName] (`jpg` without one).
///
/// The plugin's own names (`scaled_<uuid>….jpg`) say nothing to the user,
/// who sees this name in the list and in "Save to…".
String photoFileName(DateTime takenAt, int index, String pluginName) {
  final dot = pluginName.lastIndexOf('.');
  final extension = dot < 0 || dot == pluginName.length - 1
      ? 'jpg'
      : pluginName.substring(dot + 1).toLowerCase();
  // A fixed pattern, not a localised date: it is a file name.
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(takenAt);
  final suffix = index == 0 ? '' : '_${index + 1}';
  return 'IMG_$stamp$suffix.$extension';
}

/// Why picking a file failed.
enum AttachmentPickFailure {
  /// The user refused the camera permission.
  cameraDenied,

  /// The user refused access to the photos.
  photosDenied,

  /// The platform picker failed.
  failed,
}

/// Picking a file failed for [failure]; nothing was picked.
class AttachmentPickException implements Exception {
  /// Creates the exception for [failure].
  const AttachmentPickException(this.failure);

  /// What went wrong.
  final AttachmentPickFailure failure;

  @override
  String toString() => 'AttachmentPickException(${failure.name})';
}

/// Camera, gallery and file pickers for attachments. Injected so widget
/// tests replace the platform dialogs.
abstract interface class AttachmentPicker {
  /// Lets the user pick from [source]. Resolves to the picked files, empty
  /// when the user cancelled. Throws [AttachmentPickException].
  Future<List<PickedFile>> pick(AttachmentSource source);
}

/// [AttachmentPicker] on `image_picker` (camera, gallery) and
/// `file_picker` (any file).
///
/// Photos are resized to at most 2000 × 2000 px at JPEG quality 85 on the
/// phone (`Docs/02_data_model.md`); files are taken as they are.
class PlatformAttachmentPicker implements AttachmentPicker {
  /// Creates the picker; [localClock] (local time) names the photos and
  /// defaults to the system clock.
  const PlatformAttachmentPicker({this.localClock = DateTime.now});

  /// Source of the local time in the photo names ([photoFileName]).
  final DateTime Function() localClock;

  /// Longest side of a photo, in pixels.
  static const double _maxPhotoSide = 2000;

  /// JPEG quality of a photo.
  static const int _photoQuality = 85;

  @override
  Future<List<PickedFile>> pick(AttachmentSource source) async {
    try {
      switch (source) {
        case AttachmentSource.camera:
          final photo = await ImagePicker().pickImage(
            source: ImageSource.camera,
            maxWidth: _maxPhotoSide,
            maxHeight: _maxPhotoSide,
            imageQuality: _photoQuality,
          );
          return [if (photo != null) _fromXFile(photo, 0, localClock())];
        case AttachmentSource.gallery:
          final photos = await ImagePicker().pickMultiImage(
            maxWidth: _maxPhotoSide,
            maxHeight: _maxPhotoSide,
            imageQuality: _photoQuality,
          );
          final takenAt = localClock();
          return [
            for (final (index, photo) in photos.indexed)
              _fromXFile(photo, index, takenAt),
          ];
        case AttachmentSource.file:
          final files = await FilePicker.pickFiles();
          return [
            for (final file in files)
              PickedFile(
                name: file.name,
                openRead: file.readAsByteStream,
                deleteSource: () => _deleteQuietly(file.path),
              ),
          ];
      }
    } on PlatformException catch (error) {
      throw AttachmentPickException(
        switch (error.code) {
          'camera_access_denied' => AttachmentPickFailure.cameraDenied,
          'photo_access_denied' => AttachmentPickFailure.photosDenied,
          _ => AttachmentPickFailure.failed,
        },
      );
    }
  }

  /// The [PickedFile] of the [index]-th photo of a pick made at [takenAt],
  /// from `image_picker`.
  static PickedFile _fromXFile(XFile file, int index, DateTime takenAt) =>
      PickedFile(
        name: photoFileName(takenAt, index, file.name),
        mimeType: file.mimeType,
        openRead: file.openRead,
        deleteSource: () => _deleteQuietly(file.path),
      );

  /// Deletes the plugin's copy at [path], if any, without ever failing.
  static Future<void> _deleteQuietly(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Left for the cache wipe at the next app start.
    }
  }
}
