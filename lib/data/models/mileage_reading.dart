import 'calendar_date.dart';

/// One reading of a vehicle's total odometer, entered explicitly by the user
/// (`Docs/02_data_model.md`, "MileageReading").
///
/// Immutable snapshot of a live (not deleted) reading. Created and changed
/// only through `MileageReadingRepository`, which sets [id], [createdAt] and
/// [updatedAt].
class MileageReading {
  /// Creates a reading snapshot. Normally called by the repository only.
  const MileageReading({
    required this.id,
    required this.vehicleId,
    required this.date,
    required this.km,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Device-generated UUID v4.
  final String id;

  /// Id of the vehicle the reading belongs to.
  final String vehicleId;

  /// Day of the reading. A calendar day, never shifted by timezones.
  final CalendarDate date;

  /// Total odometer value, in kilometres: the stored (SI) unit, whatever the
  /// user types in. Not necessarily whole, since a value typed in miles is
  /// stored as its exact km.
  final double km;

  /// When the reading was created, in UTC. Breaks ties between readings of
  /// the same day: the one created later is the more recent.
  final DateTime createdAt;

  /// When the reading was last modified, in UTC.
  final DateTime updatedAt;

  /// Whether this reading comes after [other] in the series: a later day,
  /// or the same day and created later.
  ///
  /// The same order the repository uses to find the last reading.
  bool isAfter(MileageReading other) {
    final byDate = date.compareTo(other.date);
    if (byDate != 0) return byDate > 0;
    return createdAt.isAfter(other.createdAt);
  }

  /// Returns a copy with the given fields replaced.
  MileageReading copyWith({
    String? id,
    String? vehicleId,
    CalendarDate? date,
    double? km,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MileageReading(
      id: id ?? this.id,
      vehicleId: vehicleId ?? this.vehicleId,
      date: date ?? this.date,
      km: km ?? this.km,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MileageReading &&
      other.id == id &&
      other.vehicleId == vehicleId &&
      other.date == date &&
      other.km == km &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, vehicleId, date, km, createdAt, updatedAt);

  @override
  String toString() => 'MileageReading(id: $id, vehicleId: $vehicleId, '
      'date: ${date.toIso8601String()}, km: $km)';
}
