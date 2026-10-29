import 'package:intl/intl.dart';

import '../../data/models/units.dart';
import '../../l10n/app_localizations.dart';

// The one place where a physical quantity becomes text or text becomes a
// quantity (`Docs/06_settings_and_i18n.md`, "Unidades"). Values cross this
// boundary in SI (km, L, °C, bar, L/100 km), exactly as stored; the user's
// unit and locale exist only on the other side. No screen concatenates a
// unit symbol by hand: it asks the formatter.

/// Matches a number as typed: an optional minus, digits, then optionally
/// one decimal separator (`,` or `.`) and decimals. No thousands separator,
/// so `1.234` is read as 1.234, never as 1234.
final RegExp _numberPattern = RegExp(r'^(-?)(\d+)(?:[.,](\d+))?$');

/// Most digits the integer part of a typed value may have: a longer string
/// is a typo, refused before it can overflow anything.
const int _maxIntegerDigits = 12;

/// Formats and parses one physical quantity in one unit.
///
/// Obtained from [UnitFormatter], which builds one per quantity for the
/// units the user chose; never constructed by a screen.
class QuantityFormatter {
  /// Creates the formatter of [unit] with [symbol], rounding displayed
  /// values to [decimals], in [locale], joining value and symbol with
  /// [join]. [allowNegative] lets [parse] accept a leading minus.
  QuantityFormatter({
    required this.unit,
    required this.symbol,
    required this.decimals,
    required String locale,
    required String Function(String value, String symbol) join,
    this.allowNegative = false,
  })  : _join = join,
        _display = NumberFormat.decimalPattern(locale)
          ..minimumFractionDigits = 0
          ..maximumFractionDigits = decimals,
        _input = NumberFormat.decimalPattern(locale)
          ..minimumFractionDigits = 0
          ..maximumFractionDigits = decimals
          ..turnOffGrouping();

  /// The unit values are shown and typed in.
  final UnitConversion unit;

  /// The localised symbol of [unit], e.g. `km` or `°F`.
  final String symbol;

  /// Decimals shown; the parser accepts any number of them.
  final int decimals;

  /// Whether a typed value may be negative (temperatures).
  final bool allowNegative;

  final String Function(String value, String symbol) _join;
  final NumberFormat _display;
  final NumberFormat _input;

  /// [si] converted to [unit].
  double toDisplay(double si) => unit.fromSI(si);

  /// [value], in [unit], converted to SI.
  double toSI(double value) => unit.toSI(value);

  /// [si] in [unit] with the symbol, e.g. `1,234 km` or `-5 °F`.
  String format(double si) => _join(formatValue(si), symbol);

  /// [si] in [unit] without the symbol, rounded to [decimals] and grouped
  /// for the locale, e.g. `1,234`.
  String formatValue(double si) => _display.format(_rounded(toDisplay(si)));

  /// [si] as the text an input field shows when a stored value is edited:
  /// in [unit], rounded to [decimals], with the decimal separator of the
  /// locale and no grouping, so it parses back to the same value.
  String inputText(double si) => _input.format(_rounded(toDisplay(si)));

  /// Parses [text], typed by the user in [unit], into SI.
  ///
  /// Either decimal separator is accepted, since some keyboards offer only
  /// one; thousands separators are not. Returns `null` for blank text, a
  /// sign where none is allowed, any other character, too many digits, or
  /// a value with no finite SI equivalent (0 for a reciprocal consumption
  /// unit). Callers check for blank text first when "no value" is allowed.
  ///
  /// With [sameAs], a [text] that is exactly how that stored value shows in
  /// an input field ([inputText]) returns that value itself, not its
  /// re-conversion: a reading of 184 301 km shows as `114519` mi, which
  /// would otherwise parse back to 184 300.4 km and fall below the reading
  /// it was copied from. The rules comparing against the last reading pass
  /// it; nothing else is snapped.
  double? parse(String text, {double? sameAs}) {
    if (sameAs != null && text.trim() == inputText(sameAs)) return sameAs;
    final match = _numberPattern.firstMatch(text.trim());
    if (match == null) return null;
    final negative = match.group(1)!.isNotEmpty;
    if (negative && !allowNegative) return null;
    final integer = match.group(2)!;
    if (integer.length > _maxIntegerDigits) return null;
    final decimals = match.group(3) ?? '';
    var value = double.parse('$integer.${decimals.isEmpty ? '0' : decimals}');
    if (negative) value = -value;
    final si = toSI(value);
    return si.isFinite ? si : null;
  }

  /// [value] rounded to [decimals], with a negative zero (`-0.4` shown with
  /// no decimals) turned into plain zero.
  double _rounded(double value) {
    final rounded = double.parse(value.toStringAsFixed(decimals));
    return rounded == 0 ? 0 : rounded;
  }
}

/// The formatters of every quantity for the units the user chose
/// ([preferences]) and the interface language.
///
/// Screens build it from the current preferences and `AppLocalizations`
/// (through `unitFormatterOf`) and format or parse through its quantities:
/// `units.distance.format(km)`, `units.distance.parse(text)`,
/// `units.distance.symbol`. Nothing else in the UI knows a unit symbol.
class UnitFormatter {
  /// Creates the formatters for [preferences], with the symbols and number
  /// formats of [l10n].
  UnitFormatter({required this.preferences, required AppLocalizations l10n})
      : _l10n = l10n;

  /// The units in use.
  final UnitPreferences preferences;

  final AppLocalizations _l10n;

  /// Distances (stored in km): shown with no decimals.
  late final QuantityFormatter distance = _formatter(
    preferences.distance,
    preferences.distance.symbol(_l10n),
    decimals: 0,
  );

  /// Volumes (stored in litres): two decimals.
  late final QuantityFormatter volume = _formatter(
    preferences.volume,
    preferences.volume.symbol(_l10n),
    decimals: 2,
  );

  /// Temperatures (stored in °C): one decimal, negative allowed.
  late final QuantityFormatter temperature = _formatter(
    preferences.temperature,
    preferences.temperature.symbol(_l10n),
    decimals: 1,
    allowNegative: true,
  );

  /// Pressures (stored in bar): one decimal in bar, none in psi.
  late final QuantityFormatter pressure = _formatter(
    preferences.pressure,
    preferences.pressure.symbol(_l10n),
    decimals: preferences.pressure == PressureUnit.psi ? 0 : 1,
  );

  /// Fuel consumption (stored in L/100 km): one decimal.
  late final QuantityFormatter consumption = _formatter(
    preferences.consumption,
    preferences.consumption.symbol(_l10n),
    decimals: 1,
  );

  /// The friendly "big odometer jump" threshold in the distance unit, e.g.
  /// `50,000 km` or `30,000 mi` (`friendlyBigOdometerJump`).
  String get bigOdometerJumpThreshold => distance.format(
        distance.toSI(friendlyBigOdometerJump(preferences.distance)),
      );

  QuantityFormatter _formatter(
    UnitConversion unit,
    String symbol, {
    required int decimals,
    bool allowNegative = false,
  }) =>
      QuantityFormatter(
        unit: unit,
        symbol: symbol,
        decimals: decimals,
        locale: _l10n.localeName,
        join: _l10n.unitValueWithSymbol,
        allowNegative: allowNegative,
      );
}

/// The localised symbol of a [DistanceUnit].
extension DistanceUnitSymbol on DistanceUnit {
  /// The symbol, e.g. `km`.
  String symbol(AppLocalizations l10n) => switch (this) {
        DistanceUnit.kilometre => l10n.unitSymbolKilometre,
        DistanceUnit.mile => l10n.unitSymbolMile,
      };
}

/// The localised symbol of a [VolumeUnit].
extension VolumeUnitSymbol on VolumeUnit {
  /// The symbol, e.g. `L`.
  String symbol(AppLocalizations l10n) => switch (this) {
        VolumeUnit.litre => l10n.unitSymbolLitre,
        VolumeUnit.gallonUs => l10n.unitSymbolGallonUs,
        VolumeUnit.gallonUk => l10n.unitSymbolGallonUk,
      };
}

/// The localised symbol of a [TemperatureUnit].
extension TemperatureUnitSymbol on TemperatureUnit {
  /// The symbol, e.g. `°C`.
  String symbol(AppLocalizations l10n) => switch (this) {
        TemperatureUnit.celsius => l10n.unitSymbolCelsius,
        TemperatureUnit.fahrenheit => l10n.unitSymbolFahrenheit,
      };
}

/// The localised symbol of a [PressureUnit].
extension PressureUnitSymbol on PressureUnit {
  /// The symbol, e.g. `bar`.
  String symbol(AppLocalizations l10n) => switch (this) {
        PressureUnit.bar => l10n.unitSymbolBar,
        PressureUnit.psi => l10n.unitSymbolPsi,
      };
}

/// The localised symbol of a [ConsumptionUnit].
extension ConsumptionUnitSymbol on ConsumptionUnit {
  /// The symbol, e.g. `L/100 km`.
  String symbol(AppLocalizations l10n) => switch (this) {
        ConsumptionUnit.litresPer100Km => l10n.unitSymbolLitresPer100Km,
        ConsumptionUnit.kmPerLitre => l10n.unitSymbolKmPerLitre,
        ConsumptionUnit.mpgUs => l10n.unitSymbolMpgUs,
        ConsumptionUnit.mpgUk => l10n.unitSymbolMpgUk,
      };
}
