import 'package:drift/drift.dart';

import '../models/audit_entry.dart';
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
        nickname: nickname,
        ownerId: ownerId,
        currentOdometerKm: currentOdometerKm,
        fuelType: fuelType,
        recommendedEngineOil: recommendedEngineOil,
        manufacturerNotes: manufacturerNotes,
        photoPath: photoPath,
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
        nickname: Value(nickname),
        ownerId: ownerId,
        currentOdometerKm: currentOdometerKm,
        fuelType: fuelType,
        recommendedEngineOil: Value(recommendedEngineOil),
        manufacturerNotes: Value(manufacturerNotes),
        photoPath: Value(photoPath),
      );

  /// User-editable fields plus `updated_at`.
  ///
  /// Deliberately leaves out `current_odometer_km`: the vehicle form never
  /// changes it (that belongs to the mileage feature).
  VehiclesCompanion toUpdateCompanion() => VehiclesCompanion(
        updatedAt: Value(updatedAt),
        plate: Value(plate),
        nickname: Value(nickname),
        ownerId: Value(ownerId),
        fuelType: Value(fuelType),
        recommendedEngineOil: Value(recommendedEngineOil),
        manufacturerNotes: Value(manufacturerNotes),
        photoPath: Value(photoPath),
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
