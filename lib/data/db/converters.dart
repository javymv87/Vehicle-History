import 'package:drift/drift.dart';

import '../models/audit_entry.dart';
import '../models/calendar_date.dart';
import '../models/fuel_type.dart';

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

/// Stores an [AuditEntityType] as a stable text code.
class AuditEntityTypeConverter extends TypeConverter<AuditEntityType, String> {
  /// Creates the converter. Stateless, so a single const instance is shared.
  const AuditEntityTypeConverter();

  @override
  AuditEntityType fromSql(String fromDb) => switch (fromDb) {
        'owner' => AuditEntityType.owner,
        'vehicle' => AuditEntityType.vehicle,
        // Only reachable with a corrupted or foreign database file.
        _ => throw StateError('Unknown audit entity type in database: $fromDb'),
      };

  @override
  String toSql(AuditEntityType value) => switch (value) {
        AuditEntityType.owner => 'owner',
        AuditEntityType.vehicle => 'vehicle',
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
