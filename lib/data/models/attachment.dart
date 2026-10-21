import 'copy_with_sentinel.dart';

/// Largest file accepted as an attachment: 25 MB (`Docs/02_data_model.md`).
const int maxAttachmentBytes = 25 * 1024 * 1024;

/// Directory, relative to the application support directory, that holds
/// the attachment files, one per `attachments` row.
const String attachmentsDirName = 'attachments';

/// Directory, relative to the application support directory, where picked
/// files wait until the form that picked them is saved or cancelled.
const String attachmentsStagingDirName = 'attachments_tmp';

/// Kind of entity an attachment belongs to.
///
/// Stored with the same codes as `audit_log.entity_type` (`logEntry`,
/// `vehicle`, `owner`), see `AttachmentEntityTypeConverter`.
enum AttachmentEntityType {
  /// A history entry (photos of a service, the invoice, …).
  logEntry,

  /// A vehicle (registration document, insurance policy, …).
  vehicle,

  /// An owner (driving licence, ID card, …).
  owner,
}

/// What an attachment file is, which decides how it is shown.
enum AttachmentKind {
  /// A picture: shown as a thumbnail and in the full-screen viewer.
  image,

  /// A PDF document: opened with the phone's app.
  pdf,

  /// Anything else: opened with the phone's app, if one handles it.
  other;

  /// The kind of a file with [mimeType] (preferred) or, without one, the
  /// extension of [fileName].
  static AttachmentKind of({String? mimeType, required String fileName}) {
    final mime = (mimeType ?? mimeTypeForFileName(fileName)).toLowerCase();
    if (mime.startsWith('image/')) return image;
    if (mime == 'application/pdf') return pdf;
    return other;
  }
}

/// MIME types of the extensions the app recognises by name.
const Map<String, String> _mimeTypesByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'bmp': 'image/bmp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
};

/// Generic MIME type of a file whose type is unknown.
const String genericMimeType = 'application/octet-stream';

/// The lower-case extension of [fileName] without the dot, or `null` when
/// it has none (or only a leading dot, like `.hidden`).
String? fileExtensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return null;
  return fileName.substring(dot + 1).toLowerCase();
}

/// The MIME type of [fileName] from its extension; [genericMimeType] when
/// the extension is missing or unknown.
String mimeTypeForFileName(String fileName) =>
    _mimeTypesByExtension[fileExtensionOf(fileName)] ?? genericMimeType;

/// The extension used for the stored copy of [fileName]: its own extension
/// when it is short and plain (letters and digits, at most 8), `bin`
/// otherwise, so a stored name never carries odd characters.
String storedExtensionFor(String fileName) {
  final extension = fileExtensionOf(fileName);
  if (extension == null ||
      extension.length > 8 ||
      !RegExp(r'^[a-z0-9]+$').hasMatch(extension)) {
    return 'bin';
  }
  return extension;
}

/// The path, relative to the application support directory, of the stored
/// file of the attachment [id] named [fileName]:
/// `attachments/<id>.<ext>`. Always with `/`, whatever the platform.
String attachmentRelativePath(String id, String fileName) =>
    '$attachmentsDirName/$id.${storedExtensionFor(fileName)}';

/// The entity an attachment belongs to: its kind and its id.
class AttachmentTarget {
  /// Creates the target [entityType] / [entityId].
  const AttachmentTarget(this.entityType, this.entityId);

  /// Attachments of the history entry [id].
  const AttachmentTarget.logEntry(String id)
      : this(AttachmentEntityType.logEntry, id);

  /// The vehicle's own attachments (its documents).
  const AttachmentTarget.vehicle(String id)
      : this(AttachmentEntityType.vehicle, id);

  /// The owner's attachments (their documents).
  const AttachmentTarget.owner(String id)
      : this(AttachmentEntityType.owner, id);

  /// Kind of the entity.
  final AttachmentEntityType entityType;

  /// Id of the entity.
  final String entityId;

  @override
  bool operator ==(Object other) =>
      other is AttachmentTarget &&
      other.entityType == entityType &&
      other.entityId == entityId;

  @override
  int get hashCode => Object.hash(entityType, entityId);

  @override
  String toString() => 'AttachmentTarget(${entityType.name}, $entityId)';
}

/// A file picked by the user and copied into the staging directory, ready
/// to become an attachment when its form is saved.
class StagedFile {
  /// Creates the staged file description.
  const StagedFile({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });

  /// Absolute path of the copy in the staging directory.
  final String path;

  /// Original name of the file, shown to the user.
  final String fileName;

  /// MIME type of the file.
  final String mimeType;

  /// Size of the file in bytes.
  final int sizeBytes;

  /// What the file is, from its MIME type and name.
  AttachmentKind get kind =>
      AttachmentKind.of(mimeType: mimeType, fileName: fileName);

  @override
  String toString() => 'StagedFile($fileName, $sizeBytes bytes)';
}

/// How many attachment files there are and how much space they take.
class AttachmentTotals {
  /// Creates the totals.
  const AttachmentTotals({required this.count, required this.bytes});

  /// No attachment at all.
  static const AttachmentTotals none = AttachmentTotals(count: 0, bytes: 0);

  /// Number of attachments.
  final int count;

  /// Their total size in bytes.
  final int bytes;

  @override
  bool operator ==(Object other) =>
      other is AttachmentTotals && other.count == count && other.bytes == bytes;

  @override
  int get hashCode => Object.hash(count, bytes);

  @override
  String toString() => 'AttachmentTotals($count, $bytes bytes)';
}

/// A file attached to a history entry, a vehicle or an owner.
///
/// Immutable snapshot of a live (not deleted) row of `attachments`. Created
/// and changed only through `AttachmentRepository`. The file itself is at
/// [relativePath] under the application support directory.
class Attachment {
  /// Creates an attachment snapshot. Normally called by the repository only.
  const Attachment({
    required this.id,
    required this.target,
    required this.kind,
    required this.fileName,
    required this.mimeType,
    required this.relativePath,
    required this.sizeBytes,
    this.caption,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Device-generated UUID v4.
  final String id;

  /// The entry, vehicle or owner the file belongs to.
  final AttachmentTarget target;

  /// What the file is.
  final AttachmentKind kind;

  /// Original name of the file, shown to the user and suggested by
  /// "Save to…".
  final String fileName;

  /// MIME type of the file.
  final String mimeType;

  /// Path of the stored file, relative to the application support
  /// directory: `attachments/<id>.<ext>`.
  final String relativePath;

  /// Size of the file in bytes.
  final int sizeBytes;

  /// Optional caption typed by the user.
  final String? caption;

  /// Position among the attachments of the same [target], ascending.
  final int sortOrder;

  /// Creation instant, in UTC.
  final DateTime createdAt;

  /// Last modification instant, in UTC.
  final DateTime updatedAt;

  /// Whether the file is a picture.
  bool get isImage => kind == AttachmentKind.image;

  /// Returns a copy with the given fields replaced. Passing `caption: null`
  /// clears the caption.
  Attachment copyWith({
    Object? caption = unset,
    int? sortOrder,
    DateTime? updatedAt,
  }) =>
      Attachment(
        id: id,
        target: target,
        kind: kind,
        fileName: fileName,
        mimeType: mimeType,
        relativePath: relativePath,
        sizeBytes: sizeBytes,
        caption: identical(caption, unset) ? this.caption : caption as String?,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is Attachment &&
      other.id == id &&
      other.target == target &&
      other.kind == kind &&
      other.fileName == fileName &&
      other.mimeType == mimeType &&
      other.relativePath == relativePath &&
      other.sizeBytes == sizeBytes &&
      other.caption == caption &&
      other.sortOrder == sortOrder &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        target,
        kind,
        fileName,
        mimeType,
        relativePath,
        sizeBytes,
        caption,
        sortOrder,
        createdAt,
        updatedAt,
      );

  @override
  String toString() => 'Attachment(id: $id, $target, $fileName)';
}
