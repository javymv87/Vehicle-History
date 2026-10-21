import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';

import '../models/backup_manifest.dart';
import 'backup_exceptions.dart';

// The backup package format (`Docs/05_sync_and_storage.md`): a zip with
// `manifest.json`, `vehicle_history.sqlite` and an `attachments/` directory
// with one file per attachment row. Written and read file to file, entry by
// entry, so a package with hundreds of megabytes of photos is never held in
// memory.

/// Name of the manifest inside the package.
const String manifestEntryName = 'manifest.json';

/// Name of the database copy inside the package.
const String databaseEntryName = 'vehicle_history.sqlite';

/// Name of the attachments directory inside the package. Its files are
/// named as their `relative_path` in the database
/// (`attachments/<id>.<ext>`).
const String attachmentsEntryName = 'attachments/';

/// The only shape an attachment entry may have: `attachments/` plus a plain
/// file name. Anything else (sub-directories, `..`, absolute paths) is
/// ignored, so a crafted package cannot write outside `attachments/`.
final RegExp _attachmentEntryPattern =
    RegExp(r'^attachments/[A-Za-z0-9_-][A-Za-z0-9._-]*$');

/// Whether [name] is the name of an attachment file inside a package.
bool isAttachmentEntryName(String name) =>
    _attachmentEntryPattern.hasMatch(name) && !name.contains('..');

/// The 16 bytes every SQLite 3 database file starts with.
final Uint8List _sqliteHeader = Uint8List.fromList(
  [...ascii.encode('SQLite format 3'), 0],
);

/// Size of the SQLite file header, which holds the `user_version`.
const int sqliteHeaderLength = 100;

/// Offset of the big-endian 4-byte `user_version` in the SQLite header.
const int _userVersionOffset = 60;

/// Writes the package to a new file at [zipPath]: [manifest], the database
/// copy at [databasePath], the `attachments/` directory and, in it, every
/// file of [attachments] (entry name → absolute path of the file).
///
/// Uses `archive`'s file-based encoder: each file is streamed from disk into
/// the zip, so memory use does not grow with the package. Attachments are
/// stored without compression: photos and PDFs are compressed already.
Future<void> writeBackupPackage(
  String zipPath, {
  required BackupManifest manifest,
  required String databasePath,
  required Map<String, String> attachments,
}) async {
  final manifestJson =
      const JsonEncoder.withIndent('  ').convert(manifest.toJson());
  final encoder = ZipFileEncoder()..create(zipPath);
  try {
    encoder
      ..addArchiveFile(
        ArchiveFile.bytes(manifestEntryName, utf8.encode(manifestJson)),
      )
      ..addArchiveFile(ArchiveFile.directory(attachmentsEntryName));
    await encoder.addFile(File(databasePath), databaseEntryName);
    for (final MapEntry(key: name, value: path) in attachments.entries) {
      await encoder.addFile(File(path), name, ZipFileEncoder.store);
    }
  } finally {
    await encoder.close();
  }
}

/// A package opened for reading: its manifest and the entries still
/// compressed, read one by one on demand.
///
/// Opening checks the structure: a valid zip, a manifest with a known
/// `format_version` and a database entry. Whether the database is an
/// SQLite file of the manifest's schema, whether this app can import it and
/// whether it is intact is checked by the caller. Always [close] it.
class BackupPackageReader {
  BackupPackageReader._(
    this._input,
    this.manifest,
    this._database,
    this.attachmentEntries,
  );

  /// Opens the package at [path] and reads its manifest.
  ///
  /// Throws [BackupRejectedException] for a file that is not a package.
  static Future<BackupPackageReader> open(String path) async {
    if (!await _hasZipSignature(path)) {
      throw const BackupRejectedException(BackupRejection.notAZip);
    }
    final input = InputFileStream(path);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeStream(input);
        // A malformed file can fail in many ways inside the decoder (format,
        // range or state errors); all of them mean "not a zip".
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        throw const BackupRejectedException(BackupRejection.notAZip);
      }
      if (archive.isEmpty) {
        throw const BackupRejectedException(BackupRejection.notAZip);
      }

      final manifestEntry = archive.find(manifestEntryName);
      if (manifestEntry == null || !manifestEntry.isFile) {
        throw const BackupRejectedException(BackupRejection.missingManifest);
      }
      final BackupManifest manifest;
      try {
        manifest = BackupManifest.fromJson(
          jsonDecode(utf8.decode(_contentOf(manifestEntry))),
        );
      } on FormatException {
        throw const BackupRejectedException(BackupRejection.invalidManifest);
      }
      if (manifest.formatVersion > BackupManifest.currentFormatVersion) {
        throw const BackupRejectedException(BackupRejection.newerFormat);
      }
      if (manifest.formatVersion != BackupManifest.currentFormatVersion ||
          manifest.schemaVersion < 1) {
        throw const BackupRejectedException(BackupRejection.invalidManifest);
      }

      final databaseEntry = archive.find(databaseEntryName);
      if (databaseEntry == null || !databaseEntry.isFile) {
        throw const BackupRejectedException(BackupRejection.missingDatabase);
      }
      return BackupPackageReader._(input, manifest, databaseEntry, {
        for (final entry in archive)
          if (entry.isFile && isAttachmentEntryName(entry.name))
            entry.name: entry,
      });
    } on Object {
      await input.close();
      rethrow;
    }
  }

  /// The open package file.
  final InputFileStream _input;

  /// What the package says it holds.
  final BackupManifest manifest;

  /// The database entry.
  final ArchiveFile _database;

  /// The attachment files in the package, by entry name
  /// (`attachments/<id>.<ext>`).
  final Map<String, ArchiveFile> attachmentEntries;

  /// Uncompressed size of the database entry, in bytes.
  int get databaseSize => _database.size;

  /// Total uncompressed size of the attachment files, in bytes.
  int get attachmentsSize =>
      attachmentEntries.values.fold(0, (sum, e) => sum + e.size);

  /// Writes the database entry to a new file at [path].
  ///
  /// Throws [BackupRejectedException] when the entry cannot be inflated.
  Future<void> extractDatabase(String path) => _extract(_database, path);

  /// Writes the attachment entry [name] to a new file at [path].
  Future<void> extractAttachment(String name, String path) =>
      _extract(attachmentEntries[name]!, path);

  /// Streams [entry] into a new file at [path].
  Future<void> _extract(ArchiveFile entry, String path) async {
    final output = OutputFileStream(path);
    try {
      entry.writeContent(output);
      // Entries are inflated lazily, so a damaged archive may only fail
      // here; that still means "not a zip".
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      throw const BackupRejectedException(BackupRejection.notAZip);
    } finally {
      await output.close();
    }
  }

  /// Closes the package file.
  Future<void> close() => _input.close();
}

/// Whether the file at [path] starts with the zip signature ("PK"): the
/// decoder reads arbitrary bytes as an empty archive instead of failing.
Future<bool> _hasZipSignature(String path) async {
  final file = await File(path).open();
  try {
    final head = await file.read(2);
    return head.length == 2 && head[0] == 0x50 && head[1] == 0x4b;
  } finally {
    await file.close();
  }
}

/// The uncompressed bytes of the small [entry] (the manifest).
///
/// Throws [BackupRejectedException] when the entry cannot be inflated.
Uint8List _contentOf(ArchiveFile entry) {
  try {
    return entry.content;
    // Same as when decoding: any failure inside the decoder.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    throw const BackupRejectedException(BackupRejection.notAZip);
  }
}

/// The `user_version` stored in the SQLite file [header] (its first
/// [sqliteHeaderLength] bytes), or `null` when it is not an SQLite 3
/// database.
///
/// Drift keeps its `schemaVersion` there, so this is the schema of the file
/// without opening it.
int? sqliteUserVersion(Uint8List header) {
  if (header.length < sqliteHeaderLength) return null;
  for (var i = 0; i < _sqliteHeader.length; i++) {
    if (header[i] != _sqliteHeader[i]) return null;
  }
  return ByteData.sublistView(header).getUint32(_userVersionOffset);
}

/// File name suggested for a package exported at [localTime] (the phone's
/// local time): `vehicle-history-YYYYMMDD-HHmm.zip`.
String backupFileName(DateTime localTime) =>
    'vehicle-history-${DateFormat('yyyyMMdd-HHmm', 'en_US').format(localTime)}'
    '.zip';
