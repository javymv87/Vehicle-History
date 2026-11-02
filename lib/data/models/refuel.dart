import 'fuel_type.dart';

/// The fuel put in by one refuelling (`Docs/04_maintenance_logic.md`,
/// "Repostajes y consumos"), stored as `log_entries.fuel` since schema v10.
///
/// A vehicle's [FuelType] decides which of these its refuels can carry
/// ([FuelTypeRefuels.refuelFuels]): one for most vehicles, two for the
/// bi-fuel ones, none for an electric vehicle. Each fuel has its own
/// full-tank chain.
enum RefuelFuel {
  /// Petrol (gasoline): also the fuel of hybrids and of bi-fuel vehicles'
  /// petrol tank.
  petrol('petrol'),

  /// Diesel.
  diesel('diesel'),

  /// LPG, the second fuel of a petrol + LPG vehicle.
  lpg('lpg'),

  /// CNG (methane), the second fuel of a petrol + CNG vehicle, measured in
  /// kilograms, not litres.
  cng('cng'),

  /// The fuel of a vehicle whose type is "other".
  other('other');

  const RefuelFuel(this.code);

  /// Text stored in `log_entries.fuel`. A fixed code, never `Enum.name`.
  final String code;

  /// What the refuel's quantity measures: a mass in kg for CNG, a volume in
  /// litres for every other fuel. `log_entries.volume` holds the number in
  /// that SI unit.
  FuelQuantity get quantity =>
      this == cng ? FuelQuantity.mass : FuelQuantity.volume;
}

/// The physical quantity a refuel is measured in.
enum FuelQuantity {
  /// Litres, shown in the volume unit of the settings.
  volume,

  /// Kilograms (CNG), always shown in kg: no conversion, no setting.
  mass,
}

/// The refuel-only fields of a history entry (schema v10): `null` on the
/// entry for every other type and for the refuels of an electric vehicle,
/// which are just an expense.
class RefuelDetails {
  /// Creates the refuel fields. A new refuel is a full tank, with no
  /// refuel missed before it.
  const RefuelDetails({
    required this.fuel,
    this.volume,
    this.fullTank = true,
    this.missedPrevious = false,
  });

  /// The fuel put in; one of the vehicle's [FuelTypeRefuels.refuelFuels].
  final RefuelFuel fuel;

  /// Quantity put in, in litres (kilograms for [RefuelFuel.cng]), rounded
  /// to [volumeDecimals]; `null` when not recorded, which keeps the refuel
  /// out of the consumption chain.
  final double? volume;

  /// Whether the tank was filled up. Ignored by the chain without a
  /// [volume].
  final bool fullTank;

  /// Whether the user skipped recording a refuel before this one: the
  /// segment it belongs to cannot be computed.
  final bool missedPrevious;

  /// Decimals [volume] is stored with.
  static const int volumeDecimals = 3;

  /// [value] rounded to [volumeDecimals], as it is stored.
  static double roundVolume(double value) =>
      double.parse(value.toStringAsFixed(volumeDecimals));

  /// Returns a copy with the given fields replaced; [volume] is cleared by
  /// passing [clearVolume].
  RefuelDetails copyWith({
    RefuelFuel? fuel,
    double? volume,
    bool clearVolume = false,
    bool? fullTank,
    bool? missedPrevious,
  }) =>
      RefuelDetails(
        fuel: fuel ?? this.fuel,
        volume: clearVolume ? null : volume ?? this.volume,
        fullTank: fullTank ?? this.fullTank,
        missedPrevious: missedPrevious ?? this.missedPrevious,
      );

  @override
  bool operator ==(Object other) =>
      other is RefuelDetails &&
      other.fuel == fuel &&
      other.volume == volume &&
      other.fullTank == fullTank &&
      other.missedPrevious == missedPrevious;

  @override
  int get hashCode => Object.hash(fuel, volume, fullTank, missedPrevious);

  @override
  String toString() => 'RefuelDetails(${fuel.code}, volume: $volume, '
      'fullTank: $fullTank, missedPrevious: $missedPrevious)';
}

/// The fuels of a petrol-only vehicle, hybrids included.
const List<RefuelFuel> _petrol = [RefuelFuel.petrol];

/// The refuel fuels a vehicle's [FuelType] allows (`Docs/02_data_model.md`,
/// "Repostaje").
extension FuelTypeRefuels on FuelType {
  /// The fuels its refuels can carry, the primary one first; empty for an
  /// electric vehicle, whose refuels have no fuel fields.
  List<RefuelFuel> get refuelFuels => switch (this) {
        // Hybrids run on petrol: one chain, no choice.
        FuelType.petrol || FuelType.hybrid || FuelType.pluginHybrid => _petrol,
        FuelType.diesel => const [RefuelFuel.diesel],
        FuelType.petrolLpg => const [RefuelFuel.petrol, RefuelFuel.lpg],
        FuelType.petrolCng => const [RefuelFuel.petrol, RefuelFuel.cng],
        FuelType.other => const [RefuelFuel.other],
        FuelType.electric => const [],
      };

  /// The fuel a refuel gets when none is chosen: the only one, or petrol on
  /// a bi-fuel vehicle; `null` for an electric vehicle.
  RefuelFuel? get primaryRefuelFuel => refuelFuels.firstOrNull;

  /// Whether the refuel form asks which fuel was put in (bi-fuel only).
  bool get hasFuelChoice => refuelFuels.length > 1;

  /// Whether its refuels carry fuel fields at all (every type but electric).
  bool get hasRefuelFields => refuelFuels.isNotEmpty;
}
