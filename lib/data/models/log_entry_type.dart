/// The kind of a history entry (`Docs/02_data_model.md`, "LogEntry").
///
/// One unified entry model: the type only decides which fields make sense,
/// never which table the entry lives in.
enum LogEntryType {
  /// Scheduled, ordinary maintenance.
  maintenance,

  /// Repair or extraordinary work.
  repair,

  /// Legal deadline: road tax, compulsory inspection, insurance.
  legalDue,

  /// Refuelling. Its extra fields (litres, price per litre) come later.
  refuel,

  /// Generic expense: tolls, car wash, accessories…
  expense,

  /// Check with a measurement. Exists for the measurements step; the form
  /// does not offer it yet (see [selectable]).
  measuredCheck,

  /// Generic, unclassified check.
  genericCheck,

  /// Note or event: accidents, fines, free reminders.
  note;

  /// The types the entry form and the filters offer, in display order.
  ///
  /// [measuredCheck] is left out until the measurements step: without its
  /// measurement it would be just a [genericCheck].
  static const List<LogEntryType> selectable = [
    maintenance,
    repair,
    legalDue,
    refuel,
    expense,
    genericCheck,
    note,
  ];

  /// Whether an entry of this type must record the odometer reading.
  ///
  /// Required where the km is part of what happened (work on the vehicle, a
  /// refuelling, a check); optional where it is not, such as paying the road
  /// tax. The km stays inside the entry and never feeds `MileageReading`.
  bool get requiresKm => switch (this) {
        maintenance ||
        repair ||
        refuel ||
        genericCheck ||
        measuredCheck =>
          true,
        legalDue || expense || note => false,
      };

  /// Whether an entry of this type may be dated after today.
  ///
  /// Only for what is naturally planned ahead: a legal deadline, a booked
  /// expense, a note. Work on the vehicle, a refuelling or a check is
  /// recorded once it happened, so its date is never in the future.
  bool get allowsFutureDate => switch (this) {
        legalDue || expense || note => true,
        maintenance ||
        repair ||
        refuel ||
        genericCheck ||
        measuredCheck =>
          false,
      };
}
