import 'package:drift/drift.dart';

import '../models/audit_entry.dart';
import '../models/calendar_date.dart';
import '../models/fuel_type.dart';
import '../models/log_entry_type.dart';
import '../models/vehicle_kind.dart';

/// Stores a [CalendarDate] as ISO-8601 `yyyy-MM-dd` text.
///
/// Text with no time and no offset keeps a calendar day a day: it can never be
/// shifted by a timezone conversion, and it still sorts chronologically.
class CalendarDateConverter extends TypeConverter<CalendarDate, String> {
  /// Creates the converter. Stateless, so a single const instance is shared.
  const CalendarDateConverter();

  @override
  CalendarDate fromSql(String fromDb) => CalendarDate.parse(fromDb);

  @override
  String toSql(CalendarDate value) => value.toIso8601String();
}

/// Stores a [FuelType] as a stable text code.
///
/// The codes are spelled out instead of using `Enum.name`, so renaming a Dart
/// enum value can never silently change what is on disk.
class FuelTypeConverter extends TypeConverter<FuelType, String> {
  /// Creates the converter. Stateless, so a single const instance is shared.
  const FuelTypeConverter();

  @override
  FuelType fromSql(String fromDb) => switch (fromDb) {
        'petrol' => FuelType.petrol,
        'diesel' => FuelType.diesel,
        'petrolLpg' => FuelType.petrolLpg,
        'petrolCng' => FuelType.petrolCng,
        'hybrid' => FuelType.hybrid,
        'pluginHybrid' => FuelType.pluginHybrid,
        'electric' => FuelType.electric,
        'other' => FuelType.other,
        // Only reachable with a corrupted or foreign database file.
        _ => throw StateError('Unknown fuel type code in database: $fromDb'),
      };

  @override
  String toSql(FuelType value) => switch (value) {
        FuelType.petrol => 'petrol',
        FuelType.diesel => 'diesel',
        FuelType.petrolLpg => 'petrolLpg',
        FuelType.petrolCng => 'petrolCng',
        FuelType.hybrid => 'hybrid',
        FuelType.pluginHybrid => 'pluginHybrid',
        FuelType.electric => 'electric',
        FuelType.other => 'other',
      };
}

/// Stores a [VehicleKind] as a stable text code.
///
/// The codes match the VehiclesDB kind codes, so the catalogue can be looked
/// up with the stored value.
class VehicleKindConverter extends TypeConverter<VehicleKind, String> {
  /// Creates the converter. Stateless, so a single const instance is shared.
  const VehicleKindConverter();

  @override
  VehicleKind fromSql(String fromDb) => switch (fromDb) {
        'car' => VehicleKind.car,
        'van' => VehicleKind.van,
        'motorcycle' => VehicleKind.motorcycle,
        'moped' => VehicleKind.moped,
        // Only reachable with a corrupted or foreign database file.
        _ => throw StateError('Unknown vehicle kind code in database: $fromDb'),
      };

  @override
  String toSql(VehicleKind value) => switch (value) {
        VehicleKind.car => 'car',
        VehicleKind.van => 'van',
        VehicleKind.motorcycle => 'motorcycle',
        VehicleKind.moped => 'moped',
      };
}

/// Stores a [LogEntryType] as a stable text code.
class LogEntryTypeConverter extends TypeConverter<LogEntryType, String> {
  /// Creates the converter. Stateless, so a single const instance is shared.
  const LogEntryTypeConverter();

  @override
  LogEntryType fromSql(String fromDb) => switch (fromDb) {
        'maintenance' => LogEntryType.maintenance,
        'repair' => LogEntryType.repair,
        'legalDue' => LogEntryType.legalDue,
        'refuel' => LogEntryType.refuel,
        'expense' => LogEntryType.expense,
        'measuredCheck' => LogEntryType.measuredCheck,
        'genericCheck' => LogEntryType.genericCheck,
        'note' => LogEntryType.note,
        // Only reachable with a corrupted or foreign database file.
        _ => throw StateError('Unknown log entry type in database: $fromDb'),
      };

  @override
  String toSql(LogEntryType value) => switch (value) {
        LogEntryType.maintenance => 'maintenance',
        LogEntryType.repair => 'repair',
        LogEntryType.legalDue => 'legalDue',
        LogEntryType.refuel => 'refuel',
        LogEntryType.expense => 'expense',
        LogEntryType.measuredCheck => 'measuredCheck',
        LogEntryType.genericCheck => 'genericCheck',
        LogEntryType.note => 'note',
      };
}

/// Stores an [AuditEntityType] as a stable text code.
///
/// The column has no CHECK constraint, so a new entity type (such as
/// `logEntry`, added with schema v3) needs only a new code here.
class AuditEntityTypeConverter extends TypeConverter<AuditEntityType, String> {
  /// Creates the converter. Stateless, so a single const instance is shared.
  const AuditEntityTypeConverter();

  @override
  AuditEntityType fromSql(String fromDb) => switch (fromDb) {
        'owner' => AuditEntityType.owner,
        'vehicle' => AuditEntityType.vehicle,
        'logEntry' => AuditEntityType.logEntry,
        // Only reachable with a corrupted or foreign database file.
        _ => throw StateError('Unknown audit entity type in database: $fromDb'),
      };

  @override
  String toSql(AuditEntityType value) => switch (value) {
        AuditEntityType.owner => 'owner',
        AuditEntityType.vehicle => 'vehicle',
        AuditEntityType.logEntry => 'logEntry',
      };
}

/// Stores an [AuditOperation] as a stable text code.
class AuditOperationConverter extends TypeConverter<AuditOperation, String> {
  /// Creates the converter. Stateless, so a single const instance is shared.
  const AuditOperationConverter();

  @override
  AuditOperation fromSql(String fromDb) => switch (fromDb) {
        'create' => AuditOperation.create,
        'update' => AuditOperation.update,
        'delete' => AuditOperation.delete,
        'restore' => AuditOperation.restore,
        // Only reachable with a corrupted or foreign database file.
        _ => throw StateError('Unknown audit operation in database: $fromDb'),
      };

  @override
  String toSql(AuditOperation value) => switch (value) {
        AuditOperation.create => 'create',
        AuditOperation.update => 'update',
        AuditOperation.delete => 'delete',
        AuditOperation.restore => 'restore',
      };
}
