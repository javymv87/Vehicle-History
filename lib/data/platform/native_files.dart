import 'package:flutter/services.dart';

/// What happened to a "save as" request.
enum SaveFileOutcome {
  /// The file was copied to the place the user chose.
  saved,

  /// The user closed the system dialog without choosing a place.
  cancelled,
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
  Future<int?> freeBytes(String path) async {
    try {
      return await _channel.invokeMethod<int>('freeBytes', {'path': path});
    } on MissingPluginException {
      // Not on Android: the free-space check is skipped.
      return null;
    }
  }
}
