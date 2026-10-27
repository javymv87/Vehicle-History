/// Why a vehicle was archived (`Docs/02_data_model.md`, "Archivo").
///
/// A fixed list, never free text: `other` with the archive note is the
/// escape hatch. Stored through `ArchiveReasonConverter` with explicit codes.
enum ArchiveReason {
  /// No particular reason given (the default of the archive dialog).
  none,

  /// The vehicle was sold.
  sold,

  /// The vehicle was scrapped.
  scrapped,

  /// The vehicle was stolen.
  stolen,

  /// The vehicle was destroyed, e.g. in an accident.
  destroyed,

  /// The vehicle was given away.
  givenAway,

  /// A rental or lease ended.
  leaseEnded,

  /// Any other reason; the archive note says which.
  other,
}
