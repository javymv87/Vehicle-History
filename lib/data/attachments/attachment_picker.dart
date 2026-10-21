import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

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
  });

  /// The file name, shown to the user and kept as the attachment's name.
  final String name;

  /// The MIME type reported by the platform, if any.
  final String? mimeType;

  /// Opens the content as a stream of bytes, read once while staging.
  final Stream<List<int>> Function() openRead;
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
  /// Creates the picker. Stateless.
  const PlatformAttachmentPicker();

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
          return [if (photo != null) _fromXFile(photo)];
        case AttachmentSource.gallery:
          final photos = await ImagePicker().pickMultiImage(
            maxWidth: _maxPhotoSide,
            maxHeight: _maxPhotoSide,
            imageQuality: _photoQuality,
          );
          return [for (final photo in photos) _fromXFile(photo)];
        case AttachmentSource.file:
          final files = await FilePicker.pickFiles();
          return [
            for (final file in files)
              PickedFile(
                name: file.name,
                openRead: file.readAsByteStream,
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

  /// The [PickedFile] of a photo from `image_picker`.
  static PickedFile _fromXFile(XFile file) => PickedFile(
        name: file.name,
        mimeType: file.mimeType,
        openRead: file.openRead,
      );
}
