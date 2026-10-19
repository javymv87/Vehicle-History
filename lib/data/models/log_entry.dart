import 'calendar_date.dart';
import 'copy_with_sentinel.dart';
import 'log_entry_type.dart';

/// One row of a vehicle's history: something that happened on a day.
///
/// Immutable snapshot of a live (not deleted) entry. Created and changed only
/// through `LogEntryRepository`, which sets [id], [createdAt] and
/// [updatedAt].
class LogEntry {
  /// Creates an entry snapshot. Normally called by the repository only.
  const LogEntry({
    required this.id,
    required this.vehicleId,
    required this.date,
    this.km,
    required this.type,
    this.description,
    this.costCents,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Device-generated UUID v4.
  final String id;

  /// Id of the vehicle the entry belongs to.
  final String vehicleId;

  /// Day the event happened. A calendar day, never shifted by timezones.
  final CalendarDate date;

  /// Odometer reading at the time of the event, in whole kilometres.
  ///
  /// Required for the types where [LogEntryType.requiresKm] is true. It stays
  /// inside the entry: it never updates the vehicle's odometer history.
  final int? km;

  /// What kind of event this is.
  final LogEntryType type;

  /// Free text describing the event.
  final String? description;

  /// Total cost in euro cents, never negative. `null` when not recorded,
  /// which is different from a recorded cost of 0.
  final int? costCents;

  /// When the entry was created, in UTC. Breaks ties between entries of the
  /// same day in the history order.
  final DateTime createdAt;

  /// When the entry was last modified, in UTC.
  final DateTime updatedAt;

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable fields can be cleared by passing `null` explicitly; omitting a
  /// parameter keeps the current value.
  LogEntry copyWith({
    String? id,
    String? vehicleId,
    CalendarDate? date,
    Object? km = unset,
    LogEntryType? type,
    Object? description = unset,
    Object? costCents = unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LogEntry(
      id: id ?? this.id,
      vehicleId: vehicleId ?? this.vehicleId,
      date: date ?? this.date,
      km: identical(km, unset) ? this.km : km as int?,
      type: type ?? this.type,
      description: identical(description, unset)
          ? this.description
          : description as String?,
      costCents:
          identical(costCents, unset) ? this.costCents : costCents as int?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LogEntry &&
      other.id == id &&
      other.vehicleId == vehicleId &&
      other.date == date &&
      other.km == km &&
      other.type == type &&
      other.description == description &&
      other.costCents == costCents &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        vehicleId,
        date,
        km,
        type,
        description,
        costCents,
        createdAt,
        updatedAt,
      );

  @override
  String toString() => 'LogEntry(id: $id, vehicleId: $vehicleId, '
      'date: ${date.toIso8601String()}, type: ${type.name}, km: $km, '
      'costCents: $costCents)';
}
