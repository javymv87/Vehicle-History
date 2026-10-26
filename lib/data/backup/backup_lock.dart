import 'dart:async';

/// Lets only one backup operation touch the database file and the backup
/// temporary files at a time: manual export and import, Drive upload and
/// download.
///
/// Outlives the database connection (an import closes and reopens it), so
/// it is held by a provider that does not depend on the database.
class BackupLock {
  /// The operation running now, completed when it ends.
  Future<void>? _current;

  /// Whether an operation is running.
  bool get isBusy => _current != null;

  /// Runs [action] once every earlier operation has ended.
  Future<T> run<T>(Future<T> Function() action) async {
    while (_current != null) {
      await _current;
    }
    final done = Completer<void>();
    _current = done.future;
    try {
      return await action();
    } finally {
      _current = null;
      done.complete();
    }
  }

  /// Runs [action] only if nothing else is running; returns `null` without
  /// running it otherwise. Used by the automatic upload, which simply tries
  /// again later.
  Future<T?> tryRun<T>(Future<T> Function() action) =>
      isBusy ? Future<T?>.value() : run<T?>(action);
}
