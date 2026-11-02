import 'package:intl/intl.dart';

// Conversions between euro amounts as stored (integer cents, CLAUDE.md §11)
// and as the user reads and types them. These are the only places where an
// amount becomes text or text becomes an amount: never do arithmetic on a
// formatted value.

/// Largest amount the cost field accepts, in cents: 999,999,999.99 €.
///
/// Far beyond any real vehicle cost; it only keeps a typo from producing a
/// number the reports could not sum safely.
const int maxCostCents = 99999999999;

/// Characters the cost field lets the user type: digits and either decimal
/// separator.
final RegExp amountCharacters = RegExp('[0-9.,]');

/// Matches an amount as typed: digits, then optionally one separator and at
/// most two decimals. No sign and no thousands separator.
final RegExp _amountPattern = RegExp(r'^(\d+)(?:[.,](\d{0,2}))?$');

/// Parses an amount in euros typed by the user into cents.
///
/// The decimal separator of the locale is expected (`,` in Italian and
/// Spanish, `.` in English), but the other one is accepted too: some phone
/// keyboards show only one of them. Thousands separators are not accepted,
/// so `1.234` can never be read as 1234 €: with three decimals it is
/// refused instead.
///
/// Returns `null` when [text] is blank, has more than two decimals, a sign,
/// any other character, or exceeds [maxCostCents]. Callers check for blank
/// text first when "no amount" is allowed.
int? tryParseEuroCents(String text) {
  final match = _amountPattern.firstMatch(text.trim());
  if (match == null) return null;
  final euros = match.group(1)!;
  // More digits than the maximum could ever have: refuse before parsing, so
  // a long string can never overflow.
  if (euros.length > 9) return null;
  final decimals = (match.group(2) ?? '').padRight(2, '0');
  final cents = int.parse(euros) * 100 + int.parse(decimals);
  return cents > maxCostCents ? null : cents;
}

/// [cents] formatted as a euro amount for display in [locale], e.g.
/// `1.234,56 €` in Italian and Spanish and `€1,234.56` in English.
String formatEuroCents(int cents, String locale) =>
    NumberFormat.simpleCurrency(locale: locale, name: 'EUR')
        .format(cents / 100);

/// [cents] as the text the cost field shows when an entry is edited: two
/// decimals with the separator of [locale] and no thousands separator, e.g.
/// `1234,50` in Spanish, so it parses back to the same amount.
String euroCentsInputText(int cents, String locale) =>
    NumberFormat('0.00', locale).format(cents / 100);

/// Matches a price per unit as typed: digits, then optionally one separator
/// and at most three decimals, as pump prices are shown (1,859 €/L).
final RegExp _unitPricePattern = RegExp(r'^(\d+)(?:[.,](\d{0,3}))?$');

/// Parses a price per unit in euros typed by the user (either decimal
/// separator, at most three decimals, no sign and no thousands separator).
///
/// A price is a rate, never an amount: it is not stored, only used by the
/// refuel form to compute the amount or the volume. Returns `null` for
/// blank or malformed text.
double? tryParseUnitPrice(String text) {
  final match = _unitPricePattern.firstMatch(text.trim());
  if (match == null) return null;
  final euros = match.group(1)!;
  if (euros.length > 6) return null;
  final decimals = match.group(2) ?? '';
  return double.parse('$euros.${decimals.isEmpty ? '0' : decimals}');
}

/// [euros] per unit as the price field shows it: three decimals with the
/// separator of [locale] and no grouping, so it parses back.
String unitPriceInputText(double euros, String locale) =>
    NumberFormat('0.000', locale).format(euros);

/// A rate in [euros] (a price per unit, a cost per distance) formatted as
/// a euro value in [locale] with [decimals] decimals, e.g. `1,859 €`.
String formatEuroRate(double euros, String locale, {int decimals = 2}) =>
    NumberFormat.simpleCurrency(
      locale: locale,
      name: 'EUR',
      decimalDigits: decimals,
    ).format(euros);
