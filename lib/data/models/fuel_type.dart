/// The fuel a vehicle runs on, as declared by the manufacturer.
///
/// Bi-fuel LPG and CNG cars are common in Italy, so they have their own
/// values instead of falling under [other].
enum FuelType {
  /// Petrol (gasoline) only.
  petrol,

  /// Diesel only.
  diesel,

  /// Bi-fuel: petrol and LPG.
  petrolLpg,

  /// Bi-fuel: petrol and CNG (methane).
  petrolCng,

  /// Full hybrid (petrol or diesel engine plus a non-plug-in battery).
  hybrid,

  /// Plug-in hybrid.
  pluginHybrid,

  /// Battery electric.
  electric,

  /// Anything not covered by the values above.
  other,
}
