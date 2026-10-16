/// The kind of a vehicle. It decides which makes and models the catalogue
/// offers and, in the future, which maintenance types apply.
///
/// Trucks and buses are deliberately not managed by the app.
enum VehicleKind {
  /// Passenger car.
  car,

  /// Light commercial van.
  van,

  /// Motorcycle, including scooters above moped class.
  motorcycle,

  /// Moped and small scooter (up to 50 cc or equivalent).
  moped,
}
