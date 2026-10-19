import '../catalog/search_text.dart';
import 'calendar_date.dart';
import 'log_entry.dart';
import 'log_entry_type.dart';

/// Which entries of a vehicle's history to show (`Docs/03_features.md`,
/// "Filtros y búsqueda").
///
/// Immutable. Every criterion is optional, and the criteria combine with AND:
/// an entry is shown only if it passes all of them.
class LogEntryFilter {
  /// Creates a filter; with no arguments it lets every entry through.
  const LogEntryFilter({
    this.from,
    this.to,
    this.types = const {},
    this.text = '',
  });

  /// The filter that lets every entry through.
  static const LogEntryFilter none = LogEntryFilter();

  /// First day shown, inclusive; `null` for no lower bound.
  final CalendarDate? from;

  /// Last day shown, inclusive; `null` for no upper bound.
  final CalendarDate? to;

  /// Types shown; empty for every type.
  final Set<LogEntryType> types;

  /// Text searched in the description, ignoring case and accents, anywhere
  /// in it. Blank for no text criterion.
  final String text;

  /// Whether a date bound is set.
  bool get hasDateRange => from != null || to != null;

  /// Whether a text criterion is set.
  bool get hasText => text.trim().isNotEmpty;

  /// Whether no criterion is set, so every entry passes.
  bool get isEmpty => !hasDateRange && types.isEmpty && !hasText;

  /// Whether [entry] passes every criterion.
  ///
  /// The Drift repository applies the date and type criteria in SQL and only
  /// [matchesText] in Dart; this method is the reference for both.
  bool matches(LogEntry entry) {
    if (from case final from? when entry.date.isBefore(from)) return false;
    if (to case final to? when entry.date.isAfter(to)) return false;
    if (types.isNotEmpty && !types.contains(entry.type)) return false;
    return matchesText(entry.description);
  }

  /// Whether [description] contains [text], ignoring case and accents.
  ///
  /// Always true without a text criterion; never true for an entry with no
  /// description when there is one.
  bool matchesText(String? description) {
    final needle = foldForSearch(text.trim());
    if (needle.isEmpty) return true;
    if (description == null) return false;
    return foldForSearch(description).contains(needle);
  }

  /// Returns a copy with the date range replaced (both bounds at once, so a
  /// range can be cleared with `withDateRange(null, null)`).
  LogEntryFilter withDateRange(CalendarDate? from, CalendarDate? to) =>
      LogEntryFilter(from: from, to: to, types: types, text: text);

  /// Returns a copy showing only [types] (empty for every type).
  LogEntryFilter withTypes(Set<LogEntryType> types) => LogEntryFilter(
        from: from,
        to: to,
        types: Set.unmodifiable(types),
        text: text,
      );

  /// Returns a copy without [type] among the shown types.
  LogEntryFilter withoutType(LogEntryType type) =>
      withTypes({...types}..remove(type));

  /// Returns a copy searching [text] in the description.
  LogEntryFilter withText(String text) =>
      LogEntryFilter(from: from, to: to, types: types, text: text);

  @override
  bool operator ==(Object other) =>
      other is LogEntryFilter &&
      other.from == from &&
      other.to == to &&
      other.text == text &&
      other.types.length == types.length &&
      other.types.containsAll(types);

  @override
  int get hashCode => Object.hash(
        from,
        to,
        text,
        Object.hashAllUnordered(types),
      );

  @override
  String toString() => 'LogEntryFilter(from: $from, to: $to, '
      'types: ${[for (final t in types) t.name]}, text: "$text")';
}
