import 'package:flutter/foundation.dart';

import '../../data/models/audit_entry.dart';
import '../../data/repositories/repository_exceptions.dart';

/// Why a user action (save, delete, restore) failed, in terms the UI can
/// translate into a localised message.
///
/// Controllers never hand raw exceptions to widgets: they map them to one of
/// these values with [actionErrorOf].
enum ActionError {
  /// Another live vehicle already uses the plate.
  duplicatePlate,

  /// The owner still has live vehicles and was not deleted.
  ownerHasVehicles,

  /// The owner involved is missing or deleted.
  ownerNotFound,

  /// The vehicle involved is missing or deleted.
  vehicleNotFound,

  /// The history entry involved is missing or deleted.
  entryNotFound,

  /// The odometer reading involved is missing or deleted.
  readingNotFound,

  /// The reading is not the last one, or is the initial one, and cannot be
  /// deleted.
  readingNotDeletable,

  /// The reading cannot be corrected: its vehicle has more than one.
  readingNotEditable,

  /// The deleted reading cannot come back: a more recent one exists.
  newerReadingExists,

  /// The data layer refused a value that the form let through.
  invalidInput,

  /// Anything else, such as a disk or SQLite failure.
  unexpected,
}

/// Maps an exception thrown by a repository to an [ActionError].
///
/// Exceptions that are not a `RepositoryException` become
/// [ActionError.unexpected] and are reported to the debug console.
ActionError actionErrorOf(Object error, [StackTrace? stackTrace]) {
  return switch (error) {
    DuplicatePlateException() => ActionError.duplicatePlate,
    OwnerHasVehiclesException() => ActionError.ownerHasVehicles,
    EntityNotFoundException(entityType: AuditEntityType.owner) =>
      ActionError.ownerNotFound,
    EntityNotFoundException(entityType: AuditEntityType.vehicle) =>
      ActionError.vehicleNotFound,
    EntityNotFoundException(entityType: AuditEntityType.logEntry) =>
      ActionError.entryNotFound,
    EntityNotFoundException(entityType: AuditEntityType.mileageReading) =>
      ActionError.readingNotFound,
    MileageReadingRuleException(
      rule: MileageReadingRule.notLast || MileageReadingRule.initial,
    ) =>
      ActionError.readingNotDeletable,
    MileageReadingRuleException(rule: MileageReadingRule.notSoleReading) =>
      ActionError.readingNotEditable,
    MileageReadingRuleException(
      rule: MileageReadingRule.newerReadingExists,
    ) =>
      ActionError.newerReadingExists,
    InvalidFieldException() => ActionError.invalidInput,
    _ => _unexpected(error, stackTrace),
  };
}

/// Reports an unexpected [error] and returns [ActionError.unexpected].
ActionError _unexpected(Object error, StackTrace? stackTrace) {
  debugPrint('Unexpected action error: $error\n${stackTrace ?? ''}');
  return ActionError.unexpected;
}

/// Outcome of a user action: either a value or an [ActionError].
sealed class ActionResult<T> {
  /// Base constructor for the two outcomes.
  const ActionResult();
}

/// The action succeeded and produced [value].
final class ActionSuccess<T> extends ActionResult<T> {
  /// Creates a successful outcome carrying [value].
  const ActionSuccess(this.value);

  /// What the action produced, such as the saved entity.
  final T value;
}

/// The action failed; nothing was written.
final class ActionFailure<T> extends ActionResult<T> {
  /// Creates a failed outcome for [error].
  const ActionFailure(this.error);

  /// Why the action failed.
  final ActionError error;
}

/// Runs [action] and wraps its outcome in an [ActionResult].
///
/// Only [Exception]s are turned into an [ActionFailure]; an [Error] is a
/// programming mistake and is rethrown.
Future<ActionResult<T>> runAction<T>(Future<T> Function() action) async {
  try {
    return ActionSuccess(await action());
  } on Exception catch (error, stackTrace) {
    return ActionFailure(actionErrorOf(error, stackTrace));
  }
}
