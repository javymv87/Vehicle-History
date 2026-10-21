import 'package:open_filex/open_filex.dart';

/// What happened when the app asked the phone to open a file.
enum OpenFileOutcome {
  /// An app opened the file.
  opened,

  /// No installed app can open this kind of file.
  noApp,

  /// The file is not on disk.
  notFound,

  /// Anything else went wrong.
  failed,
}

/// Opens an attachment with the phone's own app (PDF and other files).
/// Injected so widget tests do not reach the platform.
abstract interface class FileOpener {
  /// Opens the file at [path] of type [mimeType].
  Future<OpenFileOutcome> open(String path, String mimeType);
}

/// [FileOpener] on `open_filex`, which shares the file through its own
/// `FileProvider` so the other app can read it from the app's private
/// directory.
class PlatformFileOpener implements FileOpener {
  /// Creates the opener. Stateless.
  const PlatformFileOpener();

  @override
  Future<OpenFileOutcome> open(String path, String mimeType) async {
    final result = await OpenFilex.open(path, type: mimeType);
    return switch (result.type) {
      ResultType.done => OpenFileOutcome.opened,
      ResultType.noAppToOpen => OpenFileOutcome.noApp,
      ResultType.fileNotFound => OpenFileOutcome.notFound,
      ResultType.permissionDenied || ResultType.error => OpenFileOutcome.failed,
    };
  }
}
