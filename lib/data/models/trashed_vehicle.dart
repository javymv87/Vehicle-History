import 'owner.dart';
import 'vehicle.dart';

/// How long a deleted vehicle stays in the Trash before the startup cleanup
/// removes it from disk for good (`Docs/05_sync_and_storage.md`).
///
/// The same period applies to deleted entries, readings and owners.
const Duration trashRetention = Duration(days: 30);

/// What a vehicle carries with it: its live history entries, odometer
/// readings and attachments, the rows a delete hides and a restore brings
/// back.
class VehicleContents {
  /// Creates the counts.
  const VehicleContents({
    required this.entryCount,
    required this.readingCount,
    this.attachmentCount = 0,
  });

  /// Number of live history entries of the vehicle.
  final int entryCount;

  /// Number of live odometer readings of the vehicle (at least one, its
  /// initial reading).
  final int readingCount;

  /// Number of live attachments of the vehicle: its own documents plus the
  /// files of its live entries.
  final int attachmentCount;

  @override
  bool operator ==(Object other) =>
      other is VehicleContents &&
      other.entryCount == entryCount &&
      other.readingCount == readingCount &&
      other.attachmentCount == attachmentCount;

  @override
  int get hashCode => Object.hash(entryCount, readingCount, attachmentCount);

  @override
  String toString() => 'VehicleContents(entries: $entryCount, '
      'readings: $readingCount, attachments: $attachmentCount)';
}

/// A soft-deleted vehicle as shown in the Trash: the vehicle, its owner,
/// when it was deleted and what it carries.
class TrashedVehicle {
  /// Creates a Trash row snapshot. Normally called by the repository only.
  const TrashedVehicle({
    required this.vehicle,
    required this.owner,
    required this.deletedAt,
    required this.contents,
  });

  /// The deleted vehicle, as it was when deleted.
  final Vehicle vehicle;

  /// The vehicle's owner. Read whatever its own state: an owner deleted
  /// before the Trash existed still has its row.
  final Owner owner;

  /// When the vehicle was deleted, in UTC.
  final DateTime deletedAt;

  /// Live entries, readings and attachments that come back with a restore.
  final VehicleContents contents;

  /// When the startup cleanup may remove the vehicle for good.
  DateTime get purgeAt => deletedAt.add(trashRetention);

  /// Whole days left before [purgeAt], counted from [now] and rounded up, so
  /// a vehicle deleted a moment ago shows the full 30 days. Never negative:
  /// 0 means the next app start removes it.
  int daysUntilPurge(DateTime now) {
    final left = purgeAt.difference(now);
    if (left <= Duration.zero) return 0;
    const day = Duration(days: 1);
    return (left.inMicroseconds + day.inMicroseconds - 1) ~/ day.inMicroseconds;
  }

  @override
  bool operator ==(Object other) =>
      other is TrashedVehicle &&
      other.vehicle == vehicle &&
      other.owner == owner &&
      other.deletedAt == deletedAt &&
      other.contents == contents;

  @override
  int get hashCode => Object.hash(vehicle, owner, deletedAt, contents);

  @override
  String toString() => 'TrashedVehicle(id: ${vehicle.id}, '
      'deletedAt: $deletedAt, $contents)';
}
