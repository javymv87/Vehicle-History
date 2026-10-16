import 'copy_with_sentinel.dart';
import 'fuel_type.dart';

/// A vehicle: the central entity almost everything else links to.
///
/// Immutable snapshot of a live (not deleted) vehicle as stored on the
/// device. Created and changed only through `VehicleRepository`, which sets
/// [id], [createdAt] and [updatedAt].
class Vehicle {
  /// Creates a vehicle snapshot. Normally called by the repository only.
  const Vehicle({
    required this.id,
    required this.plate,
    this.nickname,
    required this.ownerId,
    required this.currentOdometerKm,
    required this.fuelType,
    this.recommendedEngineOil,
    this.manufacturerNotes,
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Device-generated UUID v4.
  final String id;

  /// Licence plate, trimmed and upper-case. Unique among live vehicles.
  final String plate;

  /// Optional friendly name, such as "Dad's Punto".
  final String? nickname;

  /// Id of the owner. Every vehicle has exactly one.
  final String ownerId;

  /// Last known total odometer reading, in whole kilometres.
  ///
  /// Set when the vehicle is created. Changing it belongs to the mileage
  /// feature, not to the vehicle form (see `Docs/04_maintenance_logic.md`).
  final int currentOdometerKm;

  /// Fuel the vehicle runs on.
  final FuelType fuelType;

  /// Engine oil recommended by the manufacturer, as free text.
  final String? recommendedEngineOil;

  /// Any other useful manufacturer notes.
  final String? manufacturerNotes;

  /// Photo file path, relative to the app support directory.
  final String? photoPath;

  /// When the vehicle was created, in UTC.
  final DateTime createdAt;

  /// When the vehicle was last modified, in UTC.
  final DateTime updatedAt;

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable fields can be cleared by passing `null` explicitly; omitting a
  /// parameter keeps the current value.
  Vehicle copyWith({
    String? id,
    String? plate,
    Object? nickname = unset,
    String? ownerId,
    int? currentOdometerKm,
    FuelType? fuelType,
    Object? recommendedEngineOil = unset,
    Object? manufacturerNotes = unset,
    Object? photoPath = unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Vehicle(
      id: id ?? this.id,
      plate: plate ?? this.plate,
      nickname:
          identical(nickname, unset) ? this.nickname : nickname as String?,
      ownerId: ownerId ?? this.ownerId,
      currentOdometerKm: currentOdometerKm ?? this.currentOdometerKm,
      fuelType: fuelType ?? this.fuelType,
      recommendedEngineOil: identical(recommendedEngineOil, unset)
          ? this.recommendedEngineOil
          : recommendedEngineOil as String?,
      manufacturerNotes: identical(manufacturerNotes, unset)
          ? this.manufacturerNotes
          : manufacturerNotes as String?,
      photoPath:
          identical(photoPath, unset) ? this.photoPath : photoPath as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Vehicle &&
      other.id == id &&
      other.plate == plate &&
      other.nickname == nickname &&
      other.ownerId == ownerId &&
      other.currentOdometerKm == currentOdometerKm &&
      other.fuelType == fuelType &&
      other.recommendedEngineOil == recommendedEngineOil &&
      other.manufacturerNotes == manufacturerNotes &&
      other.photoPath == photoPath &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        plate,
        nickname,
        ownerId,
        currentOdometerKm,
        fuelType,
        recommendedEngineOil,
        manufacturerNotes,
        photoPath,
        createdAt,
        updatedAt,
      );

  @override
  String toString() => 'Vehicle(id: $id, plate: $plate, ownerId: $ownerId, '
      'currentOdometerKm: $currentOdometerKm, fuelType: ${fuelType.name})';
}
