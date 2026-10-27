import 'package:drift/drift.dart';

import '../models/attachment.dart';
import '../models/audit_entry.dart';
import '../models/log_entry.dart';
import '../models/mileage_reading.dart';
import '../models/owner.dart';
import '../models/vehicle.dart';
import 'app_database.dart';

// Conversions between Drift-generated rows / companions and domain models.
//
// They live here so that Drift types never leave `lib/data/db/`: DAOs accept
// and return domain models, and repositories never see a row or companion.

/// Maps an `owners` row to the domain model.
extension OwnerRowMapping on OwnerRow {
  /// Converts this row into an [Owner]. Timestamps are forced to UTC.
  Owner toModel() => Owner(
        id: id,
        firstName: firstName,
        lastName: lastName,
        birthDate: birthDate,
        nationality: nationality,
        phone: phone,
        email: email,
        notes: notes,
        photoPath: photoPath,
        createdAt: createdAt.toUtc(),
        updatedAt: updatedAt.toUtc(),
      );
}

/// Maps the domain model to `owners` companions.
extension OwnerCompanionMapping on Owner {
  /// Full row for an insert. The row starts live (`deleted = 0`).
  OwnersCompanion toInsertCompanion() => OwnersCompanion.insert(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        firstName: firstName,
        lastName: Value(lastName),
        birthDate: Value(birthDate),
        nationality: Value(nationality),
        phone: Value(phone),
        email: Value(email),
        notes: Value(notes),
        photoPath: Value(photoPath),
      );

  /// User-editable fields plus `updated_at`. Leaves `id`, `created_at` and
  /// `deleted` untouched.
  OwnersCompanion toUpdateCompanion() => OwnersCompanion(
        updatedAt: Value(updatedAt),
        firstName: Value(firstName),
        lastName: Value(lastName),
        birthDate: Value(birthDate),
        nationality: Value(nationality),
        phone: Value(phone),
        email: Value(email),
        notes: Value(notes),
        photoPath: Value(photoPath),
      );
}

/// Maps a `vehicles` row to the domain model.
extension VehicleRowMapping on VehicleRow {
  /// Converts this row into a [Vehicle]. Timestamps are forced to UTC.
  Vehicle toModel() => Vehicle(
        id: id,
        plate: plate,
        kind: kind,
        make: make,
        makeSlug: makeSlug,
        model: model,
        modelSlug: modelSlug,
        modelYear: modelYear,
        version: version,
        nickname: nickname,
        ownerId: ownerId,
        currentOdometerKm: currentOdometerKm,
        fuelType: fuelType,
        recommendedEngineOil: recommendedEngineOil,
        manufacturerNotes: manufacturerNotes,
        photoPath: photoPath,
        archivedAt: archivedAt,
        archiveReason: archiveReason,
        archiveNote: archiveNote,
        archivedKm: archivedKm,
        createdAt: createdAt.toUtc(),
        updatedAt: updatedAt.toUtc(),
      );
}

/// Maps the domain model to `vehicles` companions.
extension VehicleCompanionMapping on Vehicle {
  /// Full row for an insert. The row starts live (`deleted = 0`).
  VehiclesCompanion toInsertCompanion() => VehiclesCompanion.insert(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        plate: plate,
        kind: Value(kind),
        make: Value(make),
        makeSlug: Value(makeSlug),
        model: Value(model),
        modelSlug: Value(modelSlug),
        modelYear: Value(modelYear),
        version: Value(version),
        nickname: Value(nickname),
        ownerId: ownerId,
        currentOdometerKm: currentOdometerKm,
        fuelType: fuelType,
        recommendedEngineOil: Value(recommendedEngineOil),
        manufacturerNotes: Value(manufacturerNotes),
        photoPath: Value(photoPath),
        archivedAt: Value(archivedAt),
        archiveReason: Value(archiveReason),
        archiveNote: Value(archiveNote),
        archivedKm: Value(archivedKm),
      );

  /// User-editable fields plus `updated_at`.
  ///
  /// Deliberately leaves out `current_odometer_km`: the vehicle form never
  /// changes it (that belongs to the mileage feature). The archive columns
  /// are written only by `archiveLive` / `reactivateArchived`.
  VehiclesCompanion toUpdateCompanion() => VehiclesCompanion(
        updatedAt: Value(updatedAt),
        plate: Value(plate),
        kind: Value(kind),
        make: Value(make),
        makeSlug: Value(makeSlug),
        model: Value(model),
        modelSlug: Value(modelSlug),
        modelYear: Value(modelYear),
        version: Value(version),
        nickname: Value(nickname),
        ownerId: Value(ownerId),
        fuelType: Value(fuelType),
        recommendedEngineOil: Value(recommendedEngineOil),
        manufacturerNotes: Value(manufacturerNotes),
        photoPath: Value(photoPath),
      );
}

/// Maps a `log_entries` row to the domain model.
extension LogEntryRowMapping on LogEntryRow {
  /// Converts this row into a [LogEntry]. Timestamps are forced to UTC.
  LogEntry toModel() => LogEntry(
        id: id,
        vehicleId: vehicleId,
        date: entryDate,
        km: km,
        type: type,
        description: description,
        costCents: costCents,
        createdAt: createdAt.toUtc(),
        updatedAt: updatedAt.toUtc(),
      );
}

/// Maps the domain model to `log_entries` companions.
extension LogEntryCompanionMapping on LogEntry {
  /// Full row for an insert. The row starts live (`deleted = 0`).
  LogEntriesCompanion toInsertCompanion() => LogEntriesCompanion.insert(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        vehicleId: vehicleId,
        entryDate: date,
        km: Value(km),
        type: type,
        description: Value(description),
        costCents: Value(costCents),
      );

  /// User-editable fields plus `updated_at`. Leaves `id`, `vehicle_id`,
  /// `created_at` and `deleted` untouched: an entry never moves to another
  /// vehicle.
  LogEntriesCompanion toUpdateCompanion() => LogEntriesCompanion(
        updatedAt: Value(updatedAt),
        entryDate: Value(date),
        km: Value(km),
        type: Value(type),
        description: Value(description),
        costCents: Value(costCents),
      );
}

/// Maps a `mileage_readings` row to the domain model.
extension MileageReadingRowMapping on MileageReadingRow {
  /// Converts this row into a [MileageReading]. Timestamps are forced to
  /// UTC.
  MileageReading toModel() => MileageReading(
        id: id,
        vehicleId: vehicleId,
        date: readingDate,
        km: km,
        createdAt: createdAt.toUtc(),
        updatedAt: updatedAt.toUtc(),
      );
}

/// Maps the domain model to `mileage_readings` companions.
extension MileageReadingCompanionMapping on MileageReading {
  /// Full row for an insert. The row starts live (`deleted = 0`).
  MileageReadingsCompanion toInsertCompanion() =>
      MileageReadingsCompanion.insert(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        vehicleId: vehicleId,
        readingDate: date,
        km: km,
      );

  /// The day, the km and `updated_at`. Leaves `id`, `vehicle_id`,
  /// `created_at` and `deleted` untouched: a reading never moves to another
  /// vehicle, and keeps its place among the readings of the same day.
  MileageReadingsCompanion toUpdateCompanion() => MileageReadingsCompanion(
        updatedAt: Value(updatedAt),
        readingDate: Value(date),
        km: Value(km),
      );
}

/// Maps an `audit_log` row to the domain model.
extension AuditLogRowMapping on AuditLogRow {
  /// Converts this row into an [AuditEntry]. The timestamp is forced to UTC.
  AuditEntry toModel() => AuditEntry(
        id: id,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        at: at.toUtc(),
      );
}

/// Maps the domain model to an `audit_log` companion.
extension AuditEntryCompanionMapping on AuditEntry {
  /// Full row for an insert.
  AuditLogCompanion toInsertCompanion() => AuditLogCompanion.insert(
        id: id,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        at: at,
      );
}

/// Maps an `attachments` row to the domain model.
extension AttachmentRowMapping on AttachmentRow {
  /// Converts this row into an [Attachment]. Timestamps are forced to UTC.
  Attachment toModel() => Attachment(
        id: id,
        target: AttachmentTarget(entityType, entityId),
        kind: kind,
        fileName: fileName,
        mimeType: mimeType,
        relativePath: relativePath,
        sizeBytes: sizeBytes,
        caption: caption,
        sortOrder: sortOrder,
        createdAt: createdAt.toUtc(),
        updatedAt: updatedAt.toUtc(),
      );
}

/// Maps the domain model to an `attachments` companion.
extension AttachmentCompanionMapping on Attachment {
  /// Full row for an insert. The row starts live (`deleted = 0`).
  AttachmentsCompanion toInsertCompanion() => AttachmentsCompanion.insert(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt,
        entityType: target.entityType,
        entityId: target.entityId,
        kind: kind,
        fileName: fileName,
        mimeType: mimeType,
        relativePath: relativePath,
        sizeBytes: sizeBytes,
        caption: Value(caption),
        sortOrder: sortOrder,
      );
}
