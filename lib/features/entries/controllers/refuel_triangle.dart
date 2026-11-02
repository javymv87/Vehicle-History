/// One of the three linked values of the refuel form.
enum TriangleField {
  /// The amount paid, in cents.
  amount,

  /// The quantity put in, in SI (litres, or kg for CNG).
  volume,

  /// The price per SI unit, in euros. Never stored.
  price,
}

/// The amount / volume / price-per-unit triangle of the refuel form
/// (`Docs/03_features.md`, refuel form): the user fills any two, the third
/// is computed and stays editable.
///
/// The value recomputed after an edit is the one the user did not touch
/// among the last two edits, so the two values typed last always win. Pure
/// Dart, in SI units: the form converts what the user types and shows.
class RefuelTriangle {
  /// Creates the triangle from the values of an entry being edited. With an
  /// amount and a volume the price is computed at once, and those two count
  /// as the last edited, so typing a price recomputes the amount.
  RefuelTriangle({this.amountCents, this.volume, this.price}) {
    if (amountCents != null) _touched.add(TriangleField.amount);
    if (volume != null) _touched.add(TriangleField.volume);
    if (_touched.length == 2) price = _compute(TriangleField.price);
  }

  /// The amount in cents, or `null` when empty.
  int? amountCents;

  /// The volume in litres (kg for CNG), or `null` when empty.
  double? volume;

  /// The price in euros per litre (per kg), or `null` when empty.
  double? price;

  /// The fields edited last, oldest first; at most two.
  final List<TriangleField> _touched = [];

  /// Records that the user set [field] to [value] (`null` when the field
  /// was emptied): an `int` of cents for the amount, a `double` otherwise.
  ///
  /// Returns the field recomputed from the two values edited last, if
  /// both are set and the result is defined, or `null` when nothing
  /// changed. Its new value is in [amountCents], [volume] or [price].
  TriangleField? edit(TriangleField field, num? value) {
    switch (field) {
      case TriangleField.amount:
        amountCents = value?.round();
      case TriangleField.volume:
        volume = value?.toDouble();
      case TriangleField.price:
        price = value?.toDouble();
    }
    _touched
      ..remove(field)
      ..add(field);
    if (_touched.length > 2) _touched.removeAt(0);
    if (_touched.length < 2) return null;
    final target =
        TriangleField.values.firstWhere((f) => !_touched.contains(f));
    final computed = _compute(target);
    if (computed == null) return null;
    switch (target) {
      case TriangleField.amount:
        amountCents = computed.round();
      case TriangleField.volume:
        volume = computed;
      case TriangleField.price:
        price = computed;
    }
    return target;
  }

  /// [target] from the two other values, or `null` when one is missing or
  /// the division is undefined: cents for the amount, litres rounded to
  /// the stored 3 decimals for the volume, euros per litre for the price.
  double? _compute(TriangleField target) {
    final cents = amountCents;
    final volume = this.volume;
    final price = this.price;
    switch (target) {
      case TriangleField.amount:
        if (volume == null || price == null) return null;
        return (volume * price * 100).roundToDouble();
      case TriangleField.volume:
        if (cents == null || price == null || price <= 0) return null;
        return double.parse((cents / 100 / price).toStringAsFixed(3));
      case TriangleField.price:
        if (cents == null || volume == null || volume <= 0) return null;
        return cents / 100 / volume;
    }
  }
}
