import '../../data/models/calendar_date.dart';

/// Explicit conversions between [CalendarDate] and the [DateTime] values that
/// Flutter's date picker and `intl` formatting work with.
///
/// Only the year, month and day travel across; no timezone conversion ever
/// happens (CLAUDE.md §11), so a day stays the same day.
extension CalendarDateConversion on CalendarDate {
  /// This day at local midnight, for the date picker and `DateFormat` only.
  DateTime toLocalDateTime() => DateTime(year, month, day);
}

/// The calendar day of [picked], a value returned by the date picker.
///
/// Reads the local year, month and day as they are, without converting to
/// UTC first.
CalendarDate calendarDateOf(DateTime picked) =>
    CalendarDate(picked.year, picked.month, picked.day);
