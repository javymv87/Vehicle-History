import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:vehicle_history/data/db/app_database.dart';

/// Opens a fresh, empty in-memory database.
///
/// Each test gets its own instance, so drift's warning about several open
/// databases does not apply here and is silenced.
AppDatabase openTestDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase.forExecutor(NativeDatabase.memory());
}

/// A controllable UTC clock for deterministic timestamps.
class FakeClock {
  /// Starts the clock at [start], which must be UTC.
  FakeClock([DateTime? start])
      : _now = start ?? DateTime.utc(2024, 3, 4, 10, 30);

  /// The instant the clock currently returns.
  DateTime _now;

  /// Returns the current fake instant. Pass this as the repository clock.
  DateTime call() => _now;

  /// Moves the clock forward by [step].
  void advance([Duration step = const Duration(minutes: 1)]) {
    _now = _now.add(step);
  }
}
