/// Number of live rows of each main table in a backup package, and the
/// number of attachment files it carries.
///
/// "Live" means what the user sees: owners and vehicles not deleted, and
/// entries and readings not deleted whose vehicle is not deleted either
/// (those of a vehicle in the Trash come back with it, but are not shown).
/// [attachments] is different on purpose: it counts the files in the
/// package's `attachments/`, those of deleted attachments included, since
/// the Trash travels with the package.
class BackupCounts {
  /// Creates the counts.
  const BackupCounts({
    required this.owners,
    required this.vehicles,
    required this.logEntries,
    required this.mileageReadings,
    this.attachments = 0,
  });

  /// Live owners.
  final int owners;

  /// Live vehicles.
  final int vehicles;

  /// Live history entries of live vehicles.
  final int logEntries;

  /// Live odometer readings of live vehicles.
  final int mileageReadings;

  /// Attachment files in the package, live or deleted (added in step 8).
  final int attachments;

  /// The JSON object written into `manifest.json`.
  Map<String, Object?> toJson() => {
        'owners': owners,
        'vehicles': vehicles,
        'log_entries': logEntries,
        'mileage_readings': mileageReadings,
        'attachments': attachments,
      };

  /// Reads the counts written by [toJson].
  ///
  /// `attachments` may be missing, in a package of an app from before the
  /// attachments: it is 0 then. Throws [FormatException] when a count is
  /// missing (`attachments` aside), not an integer or negative.
  factory BackupCounts.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('counts is not an object');
    }
    int count(String key, {bool optional = false}) {
      final value = json[key];
      if (optional && value == null) return 0;
      if (value is! int || value < 0) {
        throw FormatException('counts.$key is not a non-negative integer');
      }
      return value;
    }

    return BackupCounts(
      owners: count('owners'),
      vehicles: count('vehicles'),
      logEntries: count('log_entries'),
      mileageReadings: count('mileage_readings'),
      attachments: count('attachments', optional: true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackupCounts &&
      other.owners == owners &&
      other.vehicles == vehicles &&
      other.logEntries == logEntries &&
      other.mileageReadings == mileageReadings &&
      other.attachments == attachments;

  @override
  int get hashCode =>
      Object.hash(owners, vehicles, logEntries, mileageReadings, attachments);

  @override
  String toString() => 'BackupCounts(owners: $owners, vehicles: $vehicles, '
      'logEntries: $logEntries, mileageReadings: $mileageReadings, '
      'attachments: $attachments)';
}

/// The `manifest.json` of a backup package (`Docs/05_sync_and_storage.md`):
/// what the package holds, written at export and read before an import.
class BackupManifest {
  /// Creates a manifest.
  const BackupManifest({
    required this.formatVersion,
    required this.schemaVersion,
    required this.appVersion,
    required this.exportedAt,
    required this.counts,
    required this.lastModifiedAt,
    this.attachmentsBytes = 0,
  });

  /// The package format this app writes and the only one it reads.
  static const int currentFormatVersion = 1;

  /// Version of the package layout (files and manifest keys).
  final int formatVersion;

  /// Drift `schemaVersion` of the database in the package.
  final int schemaVersion;

  /// Version of the app that exported it, as in `pubspec.yaml`.
  final String appVersion;

  /// When the package was exported, in UTC.
  final DateTime exportedAt;

  /// Live rows of each main table.
  final BackupCounts counts;

  /// The latest `updated_at` across owners, vehicles, entries and readings
  /// (deleted rows included), in UTC; `null` for an empty database.
  final DateTime? lastModifiedAt;

  /// Total size in bytes of the files in `attachments/` (added in step 8;
  /// 0 for an older package).
  final int attachmentsBytes;

  /// The JSON object written as `manifest.json`. Instants are ISO-8601 UTC.
  Map<String, Object?> toJson() => {
        'format_version': formatVersion,
        'schema_version': schemaVersion,
        'app_version': appVersion,
        'exported_at': exportedAt.toUtc().toIso8601String(),
        'counts': counts.toJson(),
        'last_modified_at': lastModifiedAt?.toUtc().toIso8601String(),
        'attachments_bytes': attachmentsBytes,
      };

  /// Reads a manifest written by [toJson].
  ///
  /// Only the shape is checked here; whether the app can import that
  /// format or schema is up to the caller. Throws [FormatException] when a
  /// key is missing or has the wrong type.
  factory BackupManifest.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('manifest is not an object');
    }
    int integer(String key) {
      final value = json[key];
      if (value is! int) throw FormatException('$key is not an integer');
      return value;
    }

    DateTime instant(Object? value, String key) {
      final parsed = value is String ? DateTime.tryParse(value) : null;
      if (parsed == null) throw FormatException('$key is not a timestamp');
      return parsed.toUtc();
    }

    final appVersion = json['app_version'];
    if (appVersion is! String) {
      throw const FormatException('app_version is not a string');
    }
    final lastModified = json['last_modified_at'];
    // Missing in the packages of the step-6 and step-7 apps.
    final attachmentsBytes = json['attachments_bytes'] ?? 0;
    if (attachmentsBytes is! int || attachmentsBytes < 0) {
      throw const FormatException('attachments_bytes is not a size');
    }
    return BackupManifest(
      formatVersion: integer('format_version'),
      schemaVersion: integer('schema_version'),
      appVersion: appVersion,
      exportedAt: instant(json['exported_at'], 'exported_at'),
      counts: BackupCounts.fromJson(json['counts']),
      lastModifiedAt: lastModified == null
          ? null
          : instant(lastModified, 'last_modified_at'),
      attachmentsBytes: attachmentsBytes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackupManifest &&
      other.formatVersion == formatVersion &&
      other.schemaVersion == schemaVersion &&
      other.appVersion == appVersion &&
      other.exportedAt == exportedAt &&
      other.counts == counts &&
      other.lastModifiedAt == lastModifiedAt &&
      other.attachmentsBytes == attachmentsBytes;

  @override
  int get hashCode => Object.hash(
        formatVersion,
        schemaVersion,
        appVersion,
        exportedAt,
        counts,
        lastModifiedAt,
        attachmentsBytes,
      );

  @override
  String toString() => 'BackupManifest(format: $formatVersion, '
      'schema: $schemaVersion, app: $appVersion, exportedAt: $exportedAt, '
      'counts: $counts, lastModifiedAt: $lastModifiedAt, '
      'attachmentsBytes: $attachmentsBytes)';
}
