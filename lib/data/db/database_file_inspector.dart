import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// What [DatabaseFileInspector.inspect] found in a database file.
class DatabaseFileReport {
  /// Creates the report.
  const DatabaseFileReport({
    required this.intact,
    required this.tableNames,
    this.attachmentPaths = const {},
  });

  /// Whether the file opened and `PRAGMA integrity_check` returned `ok`.
  final bool intact;

  /// Names of the tables in the file; empty when it is not [intact].
  final Set<String> tableNames;

  /// `relative_path` of every attachment row, live or deleted; empty when
  /// the file has no `attachments` table (schema before v7).
  final Set<String> attachmentPaths;
}

/// Checks a database file that is **not** the app's database, such as the
/// copy inside a backup package, without changing it.
///
/// Injected into the backup service so tests can replace it.
abstract interface class DatabaseFileInspector {
  /// Opens the SQLite file at [path], whose header says it is at
  /// [userVersion], and reports whether it is intact and which tables it
  /// has. Never runs a migration and never throws for a damaged file.
  Future<DatabaseFileReport> inspect(String path, int userVersion);
}

/// [DatabaseFileInspector] that opens the file with SQLite.
///
/// Runs on the calling isolate, so SQLite errors arrive as
/// [SqliteException]: the file of a backup package is small, and the check
/// runs while the page shows its progress indicator.
class SqliteDatabaseFileInspector implements DatabaseFileInspector {
  /// Creates the inspector. Stateless.
  const SqliteDatabaseFileInspector();

  @override
  Future<DatabaseFileReport> inspect(String path, int userVersion) async {
    const damaged = DatabaseFileReport(intact: false, tableNames: {});
    final executor = NativeDatabase(File(path));
    try {
      await executor.ensureOpen(_InspectionUser(userVersion));
      final check = await executor.runSelect('PRAGMA integrity_check', []);
      final intact =
          check.length == 1 && check.single.values.single.toString() == 'ok';
      if (!intact) return damaged;
      final tables = await executor.runSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
        [],
      );
      final tableNames = {for (final row in tables) row['name']! as String};
      final attachments = tableNames.contains('attachments')
          ? await executor.runSelect(
              'SELECT relative_path FROM attachments',
              [],
            )
          : const <Map<String, Object?>>[];
      return DatabaseFileReport(
        intact: true,
        tableNames: tableNames,
        attachmentPaths: {
          for (final row in attachments) row['relative_path']! as String,
        },
      );
    } on SqliteException {
      // "file is not a database", "database disk image is malformed", ...
      return damaged;
    } finally {
      await executor.close();
    }
  }
}

/// A [QueryExecutorUser] that opens a file as it is: it reports the file's
/// own version, so drift sees nothing to migrate, and does nothing before
/// opening.
class _InspectionUser implements QueryExecutorUser {
  /// Creates the user for a file at [schemaVersion].
  const _InspectionUser(this.schemaVersion);

  @override
  final int schemaVersion;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
