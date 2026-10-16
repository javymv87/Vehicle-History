import 'package:uuid/uuid.dart';

import 'repository_exceptions.dart';

/// Returns the current instant in UTC. Injected so tests control time.
typedef UtcClock = DateTime Function();

/// The default [UtcClock]: the system clock, converted to UTC.
DateTime systemUtcClock() => DateTime.now().toUtc();

/// Shared generator of device-side UUID v4 identifiers.
const Uuid _uuid = Uuid();

/// Returns a new random UUID v4 string.
String newId() => _uuid.v4();

/// Reads [clock] and checks it really returned UTC.
///
/// A local-time clock would store instants with an offset and break every
/// comparison between timestamps, so it fails loudly instead.
DateTime utcNow(UtcClock clock) {
  final now = clock();
  if (!now.isUtc) {
    throw ArgumentError.value(now, 'clock', 'must return a UTC DateTime');
  }
  return now;
}

/// Trims [value] and turns an empty result into `null`.
///
/// Used for optional free-text fields, so "nothing typed" is stored as NULL
/// and not as an empty or blank string.
String? trimToNull(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Trims a required text [value], refusing a blank one.
///
/// Throws an [InvalidFieldException] naming [field] when nothing is left.
String requireText(String value, String field) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw InvalidFieldException(field, 'must not be blank');
  }
  return trimmed;
}
