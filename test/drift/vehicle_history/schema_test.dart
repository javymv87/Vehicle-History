import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/app_database.dart';

import 'generated/schema.dart';

/// Checks the database against the committed schema dumps in
/// `drift_schemas/vehicle_history/`.
///
/// `make-migrations` generates `migration_test.dart` here once a second
/// schema version exists; until then this test guards the v1 dump.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('a fresh database matches the committed v1 schema dump', () async {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);

    // Opens the database (running onCreate) and compares every CREATE
    // statement with the v1 dump; throws SchemaMismatch on any difference.
    await verifier.migrateAndValidate(db, 1);
  });

  test('the current code matches the latest dump version', () {
    final db = AppDatabase.forExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, GeneratedHelper.versions.last);
  });
}
