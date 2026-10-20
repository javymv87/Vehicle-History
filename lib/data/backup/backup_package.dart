import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import '../models/backup_manifest.dart';
import 'backup_exceptions.dart';

// The backup package format (`Docs/05_sync_and_storage.md`): a zip with
// `manifest.json`, `vehicle_history.sqlite` and an `attachments/` directory.
// Pure Dart, so it is tested without a device or a file system.

/// Name of the manifest inside the package.
const String manifestEntryName = 'manifest.json';

/// Name of the database copy inside the package.
const String databaseEntryName = 'vehicle_history.sqlite';

/// Name of the attachments directory inside the package. Empty for now;
/// the attachments step fills it without changing the format.
const String attachmentsEntryName = 'attachments/';

/// The 16 bytes every SQLite 3 database file starts with.
final Uint8List _sqliteHeader = Uint8List.fromList(
  [...ascii.encode('SQLite format 3'), 0],
);

/// Size of the SQLite file header, which holds the `user_version`.
const int _sqliteHeaderLength = 100;

/// Offset of the big-endian 4-byte `user_version` in the SQLite header.
const int _userVersionOffset = 60;

/// The contents of a package, as read by [decodeBackupPackage].
typedef DecodedBackupPackage = ({BackupManifest manifest, Uint8List database});

/// Builds the zip of a package from its [manifest] and the bytes of a
/// consistent copy of the [database].
Uint8List encodeBackupPackage(BackupManifest manifest, Uint8List database) {
  final manifestJson =
      const JsonEncoder.withIndent('  ').convert(manifest.toJson());
  final archive = Archive()
    ..add(ArchiveFile.bytes(manifestEntryName, utf8.encode(manifestJson)))
    ..add(ArchiveFile.bytes(databaseEntryName, database))
    ..add(ArchiveFile.directory(attachmentsEntryName));
  return ZipEncoder().encodeBytes(archive);
}

/// Reads a package and checks its structure: a valid zip, a manifest with a
/// known `format_version`, and a database entry that is an SQLite file whose
/// `user_version` matches the manifest's `schema_version`.
///
/// Whether this app can import that schema, and whether the database is
/// intact, is checked by the caller. Throws [BackupRejectedException].
DecodedBackupPackage decodeBackupPackage(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: true);
    // A malformed file can fail in many ways inside the decoder (format,
    // range or state errors); all of them mean "not a zip".
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    throw const BackupRejectedException(BackupRejection.notAZip);
  }
  // The decoder reads arbitrary bytes as an empty archive instead of
  // failing, so a zip is also recognised by its signature ("PK").
  if (archive.isEmpty || bytes[0] != 0x50 || bytes[1] != 0x4b) {
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
  final database = _contentOf(databaseEntry);
  if (sqliteUserVersion(database) != manifest.schemaVersion) {
    throw const BackupRejectedException(BackupRejection.notADatabase);
  }
  return (manifest: manifest, database: database);
}

/// The uncompressed bytes of [entry].
///
/// Entries are inflated lazily, so a damaged archive may only fail here;
/// that still means "not a zip". Throws [BackupRejectedException].
Uint8List _contentOf(ArchiveFile entry) {
  try {
    return entry.content;
    // Same as when decoding: any failure inside the decoder.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    throw const BackupRejectedException(BackupRejection.notAZip);
  }
}

/// The `user_version` stored in the header of the SQLite file [bytes], or
/// `null` when [bytes] is not an SQLite 3 database.
///
/// Drift keeps its `schemaVersion` there, so this is the schema of the file
/// without opening it.
int? sqliteUserVersion(Uint8List bytes) {
  if (bytes.length < _sqliteHeaderLength) return null;
  for (var i = 0; i < _sqliteHeader.length; i++) {
    if (bytes[i] != _sqliteHeader[i]) return null;
  }
  return ByteData.sublistView(bytes).getUint32(_userVersionOffset);
}

/// File name suggested for a package exported at [localTime] (the phone's
/// local time): `vehicle-history-YYYYMMDD-HHmm.zip`.
String backupFileName(DateTime localTime) =>
    'vehicle-history-${DateFormat('yyyyMMdd-HHmm', 'en_US').format(localTime)}'
    '.zip';
