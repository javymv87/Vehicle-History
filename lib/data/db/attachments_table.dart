import 'package:drift/drift.dart';

import 'converters.dart';
import 'technical_columns.dart';

/// The `attachments` table: files attached to a history entry, a vehicle or
/// an owner, one row per file (`Docs/02_data_model.md`).
///
/// Polymorphic: [entityType] and [entityId] name the owner of the file, so
/// there is no foreign key; the repository checks that the target exists
/// and is live. The file itself lives at [relativePath] under the
/// application support directory. Added in schema v7.
@DataClassName('AttachmentRow')
@TableIndex(name: 'attachments_entity', columns: {#entityType, #entityId})
class Attachments extends Table with TechnicalColumns {
  /// Kind of the entity the file belongs to, with the `audit_log` codes
  /// (`logEntry`, `vehicle`, `owner`).
  TextColumn get entityType =>
      text().map(const AttachmentEntityTypeConverter())();

  /// Id of the entity the file belongs to.
  TextColumn get entityId => text()();

  /// What the file is (`image`, `pdf`, `other`).
  TextColumn get kind => text().map(const AttachmentKindConverter())();

  /// Original name of the file, shown to the user.
  TextColumn get fileName => text()();

  /// MIME type of the file.
  TextColumn get mimeType => text()();

  /// Path of the stored file relative to the application support
  /// directory: `attachments/<id>.<ext>`.
  TextColumn get relativePath => text()();

  /// Size of the file in bytes. Never negative.
  IntColumn get sizeBytes => integer()();

  /// Optional caption typed by the user.
  TextColumn get caption => text().nullable()();

  /// Position among the attachments of the same entity, ascending.
  IntColumn get sortOrder => integer()();

  // Written as SQL rather than with `Column.check` (see CLAUDE.md §2).
  @override
  List<String> get customConstraints => ['CHECK (size_bytes >= 0)'];
}
