import 'package:flutter/services.dart';

/// What happened to a "save as" request.
enum SaveFileOutcome {
  /// The file was copied to the place the user chose.
  saved,

  /// The user closed the system dialog without choosing a place.
  cancelled,
}

/// A file handed to the native side: where it is, the name the user sees
/// and its MIME type.
class NativeFile {
  /// Describes the file at [path], shown as [name].
  const NativeFile({
    required this.path,
    required this.name,
    required this.mimeType,
  });

  /// Absolute path of the file.
  final String path;

  /// Name given to the copy (the attachment's original name).
  final String name;

  /// MIME type of the file.
  final String mimeType;

  /// The map the channel expects.
  Map<String, String> toMap() =>
      {'path': path, 'name': name, 'mimeType': mimeType};
}

/// The native file operations of `MainActivity.kt` (channel
/// `vehicle_history/files`), Android only.
///
/// Injected so tests replace it with a fake.
abstract interface class NativeFiles {
  /// Asks the user where to save the file at [sourcePath], suggesting
  /// [suggestedName], and copies it there in 64 KB chunks, never loading it
  /// into memory (Android `ACTION_CREATE_DOCUMENT`).
  ///
  /// Throws [PlatformException] when the copy fails.
  Future<SaveFileOutcome> saveFile({
    required String sourcePath,
    required String suggestedName,
    required String mimeType,
  });

  /// Asks the user for a folder (Android `ACTION_OPEN_DOCUMENT_TREE`) and
  /// copies each of [files] into it under its name, in 64 KB chunks; the
  /// provider adds " (1)" to a name already there instead of overwriting.
  ///
  /// Resolves to the number of files saved, or `null` when the user
  /// cancelled. Throws [PlatformException] when a copy fails (its `details`
  /// is the number saved before the failure).
  Future<int?> saveFilesToFolder(List<NativeFile> files);

  /// Offers [files] to other apps through the system share sheet, under
  /// their names. Resolves once the sheet is shown.
  ///
  /// Throws [PlatformException] when the copies cannot be made or no app
  /// can receive them.
  Future<void> shareFiles(List<NativeFile> files);

  /// The bytes free for the app on the volume holding [path], or `null`
  /// when the platform cannot tell.
  Future<int?> freeBytes(String path);
}

/// [NativeFiles] on the method channel implemented in `MainActivity.kt`.
class MethodChannelNativeFiles implements NativeFiles {
  /// Creates the wrapper. Stateless.
  const MethodChannelNativeFiles();

  /// The channel; its name must match `MainActivity.kt`.
  static const MethodChannel _channel = MethodChannel('vehicle_history/files');

  @override
  Future<SaveFileOutcome> saveFile({
    required String sourcePath,
    required String suggestedName,
    required String mimeType,
  }) async {
    final result = await _channel.invokeMethod<String>('saveFile', {
      'sourcePath': sourcePath,
      'suggestedName': suggestedName,
      'mimeType': mimeType,
    });
    return result == 'saved'
        ? SaveFileOutcome.saved
        : SaveFileOutcome.cancelled;
  }

  @override
  Future<int?> saveFilesToFolder(List<NativeFile> files) =>
      _channel.invokeMethod<int>('saveFilesToFolder', {
        'files': [for (final file in files) file.toMap()],
      });

  @override
  Future<void> shareFiles(List<NativeFile> files) =>
      _channel.invokeMethod<void>('shareFiles', {
        'files': [for (final file in files) file.toMap()],
      });

  @override
  Future<int?> freeBytes(String path) async {
    try {
      return await _channel.invokeMethod<int>('freeBytes', {'path': path});
    } on MissingPluginException {
      // Not on Android: the free-space check is skipped.
      return null;
    }
  }
}
