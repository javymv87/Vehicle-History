/// Why a file was refused as a backup package. Checked before anything is
/// touched, so a rejection never changes the user's data.
enum BackupRejection {
  /// The file is not a readable zip archive.
  notAZip,

  /// The archive has no `manifest.json`.
  missingManifest,

  /// `manifest.json` is not valid JSON or lacks a required key.
  invalidManifest,

  /// The package uses a newer `format_version` than this app knows.
  newerFormat,

  /// The archive has no `vehicle_history.sqlite`.
  missingDatabase,

  /// `vehicle_history.sqlite` is not an SQLite file, or its schema version
  /// does not match the manifest.
  notADatabase,

  /// The database fails `PRAGMA integrity_check` or cannot be opened.
  corruptDatabase,

  /// The database was written by a newer version of the app.
  newerSchema,

  /// A table this schema version must have is missing.
  missingTables,

  /// The phone has not enough free space to unpack and swap in the package.
  notEnoughSpace,
}

/// The file chosen for an import is not a package this app can import.
///
/// Thrown before anything is closed or replaced: the data is untouched.
class BackupRejectedException implements Exception {
  /// Creates the exception for [reason].
  const BackupRejectedException(this.reason);

  /// What the validation found.
  final BackupRejection reason;

  @override
  String toString() => 'BackupRejectedException(${reason.name})';
}

/// A valid package could not be imported, and the data from before the
/// import was put back.
///
/// The database connection was closed on the way, so the caller must open
/// a new one.
class BackupImportFailedException implements Exception {
  /// Creates the exception for the error that stopped the import.
  const BackupImportFailedException(this.cause);

  /// What went wrong while replacing, opening or migrating the database.
  final Object cause;

  @override
  String toString() => 'BackupImportFailedException($cause)';
}

/// The import failed **and** putting the previous data back failed too.
///
/// The previous data is still in `vehicle_history.pre_import.sqlite`, next to
/// the database file; it is never deleted automatically.
class BackupRestoreFailedException implements Exception {
  /// Creates the exception for the import error [cause] and the restore
  /// error [restoreError].
  const BackupRestoreFailedException(this.cause, this.restoreError);

  /// What made the import fail.
  final Object cause;

  /// What made putting the previous data back fail.
  final Object restoreError;

  @override
  String toString() =>
      'BackupRestoreFailedException(cause: $cause, restore: $restoreError)';
}
