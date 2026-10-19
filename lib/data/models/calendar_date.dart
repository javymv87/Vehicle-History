/// A calendar day — year, month and day — with no time and no timezone.
///
/// Used for dates the user thinks of as days, such as a birth date or the
/// date of a service: a service done on 4 March stays on 4 March whatever
/// timezone the phone is in. It is deliberately not a [DateTime], which is an
/// instant and would shift across timezones (see CLAUDE.md §11).
///
/// Persisted as ISO-8601 `yyyy-MM-dd` text, which also sorts chronologically.
class CalendarDate implements Comparable<CalendarDate> {
  /// Creates a calendar date from its parts.
  ///
  /// The parts are range-checked in debug builds only. Use [CalendarDate.parse]
  /// for untrusted input: it also rejects days that do not exist, such as
  /// 30 February.
  const CalendarDate(this.year, this.month, this.day)
      : assert(year >= 1 && year <= 9999, 'year must be in 1..9999'),
        assert(month >= 1 && month <= 12, 'month must be in 1..12'),
        assert(day >= 1 && day <= 31, 'day must be in 1..31');

  /// Parses an ISO-8601 `yyyy-MM-dd` string, such as `2024-03-04`.
  ///
  /// Throws a [FormatException] if [source] is not in that exact format or
  /// names a day that does not exist.
  factory CalendarDate.parse(String source) {
    final match = _isoPattern.firstMatch(source);
    if (match == null) {
      throw FormatException('Expected a yyyy-MM-dd date', source);
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (year < 1 || month < 1 || month > 12 || day < 1) {
      throw FormatException('Date out of range', source);
    }
    // DateTime.utc normalises overflowing days (30 Feb → 2 Mar); if any part
    // changed, the input did not name a real day.
    final probe = DateTime.utc(year, month, day);
    if (probe.year != year || probe.month != month || probe.day != day) {
      throw FormatException('Day does not exist', source);
    }
    return CalendarDate(year, month, day);
  }

  /// The local calendar day on which the [instant] falls, in the phone's
  /// current timezone.
  ///
  /// The one explicit conversion from a technical timestamp to a day
  /// (CLAUDE.md §11): used for "today" from the UTC clock, and for the day a
  /// row was created. [instant] may be UTC or local; it is converted to
  /// local time first, never truncated as it is.
  factory CalendarDate.localDayOf(DateTime instant) {
    final local = instant.toLocal();
    return CalendarDate(local.year, local.month, local.day);
  }

  /// Exactly four, two and two digits separated by dashes.
  static final RegExp _isoPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// Four-digit year, 1 to 9999.
  final int year;

  /// Month of the year, 1 (January) to 12 (December).
  final int month;

  /// Day of the month, 1 to 31.
  final int day;

  /// Returns a copy with the given parts replaced.
  CalendarDate copyWith({int? year, int? month, int? day}) =>
      CalendarDate(year ?? this.year, month ?? this.month, day ?? this.day);

  /// Formats this date as ISO-8601 `yyyy-MM-dd`, the storage format.
  ///
  /// Not meant for display: user-facing dates are formatted through `intl`.
  String toIso8601String() {
    final y = year.toString().padLeft(4, '0');
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  int compareTo(CalendarDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  /// Whether this date falls strictly before [other].
  bool isBefore(CalendarDate other) => compareTo(other) < 0;

  /// Whether this date falls strictly after [other].
  bool isAfter(CalendarDate other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is CalendarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'CalendarDate(${toIso8601String()})';
}
