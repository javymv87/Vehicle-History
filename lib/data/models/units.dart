// Units of measurement (`Docs/06_settings_and_i18n.md`, "Unidades").
//
// The database, the repositories, the domain rules and the backup package
// store every physical quantity in SI: kilometres, litres, degrees Celsius,
// bar and litres per 100 km. The unit the user chose exists only at the UI
// boundary: `UnitFormatter` converts with the factors below when it parses
// input and formats output. Changing the setting never touches stored data.

/// A unit of one physical quantity, able to convert to and from the SI
/// unit the data is stored in.
abstract interface class UnitConversion {
  /// Text stored in the `settings` table. A fixed code, never `Enum.name`.
  String get code;

  /// Converts [value], in this unit, to the SI unit.
  double toSI(double value);

  /// Converts [si], in the SI unit, to this unit.
  double fromSI(double si);
}

/// Units of distance (SI: kilometre). Setting `unit_distance`.
enum DistanceUnit implements UnitConversion {
  /// Kilometres: the stored unit.
  kilometre('km', 1),

  /// Statute miles: 1 mi = 1.609344 km.
  mile('mi', 1.609344);

  const DistanceUnit(this.code, this.kmPerUnit);

  @override
  final String code;

  /// How many kilometres one unit is.
  final double kmPerUnit;

  @override
  double toSI(double value) => value * kmPerUnit;

  @override
  double fromSI(double si) => si / kmPerUnit;

  /// The value stored as [code]; an absent or unknown value is
  /// [kilometre], so a row written by a newer app version never breaks the
  /// start.
  static DistanceUnit fromCode(String? code) => values.firstWhere(
        (unit) => unit.code == code,
        orElse: () => kilometre,
      );
}

/// Units of volume (SI: litre). Setting `unit_volume`.
enum VolumeUnit implements UnitConversion {
  /// Litres: the stored unit.
  litre('l', 1),

  /// US liquid gallons: 1 gal = 3.785411784 L.
  gallonUs('gal_us', 3.785411784),

  /// Imperial (UK) gallons: 1 gal = 4.54609 L.
  gallonUk('gal_uk', 4.54609);

  const VolumeUnit(this.code, this.litresPerUnit);

  @override
  final String code;

  /// How many litres one unit is.
  final double litresPerUnit;

  @override
  double toSI(double value) => value * litresPerUnit;

  @override
  double fromSI(double si) => si / litresPerUnit;

  /// The value stored as [code]; absent or unknown is [litre].
  static VolumeUnit fromCode(String? code) => values.firstWhere(
        (unit) => unit.code == code,
        orElse: () => litre,
      );
}

/// Units of temperature (SI for this app: degree Celsius). Setting
/// `unit_temperature`.
enum TemperatureUnit implements UnitConversion {
  /// Degrees Celsius: the stored unit.
  celsius('c'),

  /// Degrees Fahrenheit: °F = °C × 9 / 5 + 32.
  fahrenheit('f');

  const TemperatureUnit(this.code);

  @override
  final String code;

  @override
  double toSI(double value) => switch (this) {
        celsius => value,
        fahrenheit => (value - 32) * 5 / 9,
      };

  @override
  double fromSI(double si) => switch (this) {
        celsius => si,
        fahrenheit => si * 9 / 5 + 32,
      };

  /// The value stored as [code]; absent or unknown is [celsius].
  static TemperatureUnit fromCode(String? code) => values.firstWhere(
        (unit) => unit.code == code,
        orElse: () => celsius,
      );
}

/// Units of pressure (SI for this app: bar). Setting `unit_pressure`.
enum PressureUnit implements UnitConversion {
  /// Bar: the stored unit.
  bar('bar', 1),

  /// Pounds per square inch: 1 bar = 14.503773773 psi.
  psi('psi', 14.503773773);

  const PressureUnit(this.code, this.unitsPerBar);

  @override
  final String code;

  /// How many of this unit one bar is.
  final double unitsPerBar;

  @override
  double toSI(double value) => value / unitsPerBar;

  @override
  double fromSI(double si) => si * unitsPerBar;

  /// The value stored as [code]; absent or unknown is [bar].
  static PressureUnit fromCode(String? code) => values.firstWhere(
        (unit) => unit.code == code,
        orElse: () => bar,
      );
}

/// Units of fuel consumption (SI for this app: litres per 100 km). Setting
/// `unit_consumption`.
///
/// The three other units are reciprocal to L/100 km: `x = k / value` in
/// both directions, with `k` derived from the distance and volume factors
/// (100 km per litre; miles per US or UK gallon).
enum ConsumptionUnit implements UnitConversion {
  /// Litres per 100 km: the stored unit.
  litresPer100Km('l_100km', VolumeUnit.litre),

  /// Kilometres per litre: 100 / (L/100 km).
  kmPerLitre('km_l', VolumeUnit.litre),

  /// Miles per US gallon.
  mpgUs('mpg_us', VolumeUnit.gallonUs),

  /// Miles per imperial gallon.
  mpgUk('mpg_uk', VolumeUnit.gallonUk);

  const ConsumptionUnit(this.code, this.volumeUnit);

  @override
  final String code;

  /// The volume this unit counts with, so the settings page can hint when
  /// it differs from the chosen [VolumeUnit].
  final VolumeUnit volumeUnit;

  /// `k` of `unit = k / (L/100 km)`, or `null` for the stored unit itself.
  /// Derived from the distance and volume factors, never typed by hand:
  /// miles per gallon = (100 km / L) × (L / gal) ÷ (km / mi).
  double? get _reciprocalFactor => switch (this) {
        litresPer100Km => null,
        kmPerLitre => 100,
        mpgUs ||
        mpgUk =>
          100 * volumeUnit.litresPerUnit / DistanceUnit.mile.kmPerUnit,
      };

  /// Both directions are the same reciprocal; 0 maps to infinity, which
  /// the formatter refuses as input.
  double _convert(double value) {
    final factor = _reciprocalFactor;
    return factor == null ? value : factor / value;
  }

  @override
  double toSI(double value) => _convert(value);

  @override
  double fromSI(double si) => _convert(si);

  /// The value stored as [code]; absent or unknown is [litresPer100Km].
  static ConsumptionUnit fromCode(String? code) => values.firstWhere(
        (unit) => unit.code == code,
        orElse: () => litresPer100Km,
      );
}

/// The two fixed presets of the settings page, and "custom" for any other
/// combination. Never stored: derived from the five units every time.
enum UnitPreset {
  /// km, L, °C, bar, L/100 km.
  international,

  /// mi, US gal, °F, psi, mpg (US).
  imperial,

  /// Any other combination; shown, never chosen directly.
  custom,
}

/// The five units the user chose, as stored in the `settings` table
/// (`unit_distance`, `unit_volume`, `unit_temperature`, `unit_pressure`,
/// `unit_consumption`); an absent key is its SI default.
class UnitPreferences {
  /// Creates a set of preferences; every omitted unit is the SI one.
  const UnitPreferences({
    this.distance = DistanceUnit.kilometre,
    this.volume = VolumeUnit.litre,
    this.temperature = TemperatureUnit.celsius,
    this.pressure = PressureUnit.bar,
    this.consumption = ConsumptionUnit.litresPer100Km,
  });

  /// The preferences before the user chose anything: [international].
  static const UnitPreferences defaults = UnitPreferences();

  /// The [UnitPreset.international] combination.
  static const UnitPreferences international = defaults;

  /// The [UnitPreset.imperial] combination.
  static const UnitPreferences imperial = UnitPreferences(
    distance: DistanceUnit.mile,
    volume: VolumeUnit.gallonUs,
    temperature: TemperatureUnit.fahrenheit,
    pressure: PressureUnit.psi,
    consumption: ConsumptionUnit.mpgUs,
  );

  /// Reads the five stored codes; a `null` or unknown code is the default.
  factory UnitPreferences.fromCodes({
    String? distance,
    String? volume,
    String? temperature,
    String? pressure,
    String? consumption,
  }) =>
      UnitPreferences(
        distance: DistanceUnit.fromCode(distance),
        volume: VolumeUnit.fromCode(volume),
        temperature: TemperatureUnit.fromCode(temperature),
        pressure: PressureUnit.fromCode(pressure),
        consumption: ConsumptionUnit.fromCode(consumption),
      );

  /// The preferences of [preset]; [UnitPreset.custom] has none and throws.
  factory UnitPreferences.ofPreset(UnitPreset preset) => switch (preset) {
        UnitPreset.international => international,
        UnitPreset.imperial => imperial,
        UnitPreset.custom =>
          throw ArgumentError.value(preset, 'preset', 'has no fixed units'),
      };

  /// Unit of distance.
  final DistanceUnit distance;

  /// Unit of volume.
  final VolumeUnit volume;

  /// Unit of temperature.
  final TemperatureUnit temperature;

  /// Unit of pressure.
  final PressureUnit pressure;

  /// Unit of fuel consumption.
  final ConsumptionUnit consumption;

  /// Which preset these five units are, computed every time: changing one
  /// unit makes the set [UnitPreset.custom], and changing it back makes it
  /// the preset again.
  UnitPreset get preset {
    if (this == international) return UnitPreset.international;
    if (this == imperial) return UnitPreset.imperial;
    return UnitPreset.custom;
  }

  /// Whether the consumption unit counts with another volume than the
  /// chosen one (e.g. gallons with L/100 km): only a hint, never refused,
  /// since changing the volume never changes the consumption unit.
  bool get volumeConsumptionMismatch => consumption.volumeUnit != volume;

  /// Returns a copy with the given units replaced.
  UnitPreferences copyWith({
    DistanceUnit? distance,
    VolumeUnit? volume,
    TemperatureUnit? temperature,
    PressureUnit? pressure,
    ConsumptionUnit? consumption,
  }) =>
      UnitPreferences(
        distance: distance ?? this.distance,
        volume: volume ?? this.volume,
        temperature: temperature ?? this.temperature,
        pressure: pressure ?? this.pressure,
        consumption: consumption ?? this.consumption,
      );

  @override
  bool operator ==(Object other) =>
      other is UnitPreferences &&
      other.distance == distance &&
      other.volume == volume &&
      other.temperature == temperature &&
      other.pressure == pressure &&
      other.consumption == consumption;

  @override
  int get hashCode =>
      Object.hash(distance, volume, temperature, pressure, consumption);

  @override
  String toString() => 'UnitPreferences(${distance.code}, ${volume.code}, '
      '${temperature.code}, ${pressure.code}, ${consumption.code})';
}

/// The "big odometer jump" threshold as the user reads it: the stored rule
/// compares 50 000 km (`bigOdometerJumpKm`) whatever the unit; the dialog
/// names the friendly round figure of the chosen unit instead of the
/// converted 31 069 mi.
///
/// Every display threshold lives here, next to the units, never in a
/// screen.
double friendlyBigOdometerJump(DistanceUnit unit) => switch (unit) {
      DistanceUnit.kilometre => 50000,
      DistanceUnit.mile => 30000,
    };
