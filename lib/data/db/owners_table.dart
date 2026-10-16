import 'package:drift/drift.dart';

import 'converters.dart';
import 'technical_columns.dart';

/// The `owners` table: people who own one or more vehicles.
@DataClassName('OwnerRow')
class Owners extends Table with TechnicalColumns {
  /// First name. Required and never blank (see [customConstraints]).
  TextColumn get firstName => text()();

  /// Last name.
  TextColumn get lastName => text().nullable()();

  /// Birth date as `yyyy-MM-dd` text, never a timestamp.
  TextColumn get birthDate =>
      text().map(const CalendarDateConverter()).nullable()();

  /// Nationality: ISO 3166-1 alpha-2 code, or free text typed by the user.
  TextColumn get nationality => text().nullable()();

  /// Phone number, as typed.
  TextColumn get phone => text().nullable()();

  /// Email address, as typed.
  TextColumn get email => text().nullable()();

  /// Free notes.
  TextColumn get notes => text().nullable()();

  /// Photo path relative to the app support directory.
  TextColumn get photoPath => text().nullable()();

  // Written as SQL rather than with `Column.check`, whose self-referencing
  // getter trips the `recursive_getters` lint.
  @override
  List<String> get customConstraints => [
        "CHECK (length(trim(first_name)) > 0)",
      ];
}
