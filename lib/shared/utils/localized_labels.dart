import '../../data/models/app_preferences.dart';
import '../../data/models/archive_reason.dart';
import '../../data/models/fuel_type.dart';
import '../../data/models/log_entry_type.dart';
import '../../data/models/units.dart';
import '../../data/models/vehicle.dart';
import '../../data/models/vehicle_kind.dart';
import '../../l10n/app_localizations.dart';
import 'action_result.dart';
import 'calendar_date_conversion.dart';
import 'unit_formatter.dart';

/// Localised label of a [FuelType].
extension FuelTypeLabel on FuelType {
  /// The name of this fuel type in the language of [l10n].
  String label(AppLocalizations l10n) => switch (this) {
        FuelType.petrol => l10n.fuelPetrol,
        FuelType.diesel => l10n.fuelDiesel,
        FuelType.petrolLpg => l10n.fuelPetrolLpg,
        FuelType.petrolCng => l10n.fuelPetrolCng,
        FuelType.hybrid => l10n.fuelHybrid,
        FuelType.pluginHybrid => l10n.fuelPluginHybrid,
        FuelType.electric => l10n.fuelElectric,
        FuelType.other => l10n.fuelOther,
      };
}

/// Localised label of an [ArchiveReason].
extension ArchiveReasonLabel on ArchiveReason {
  /// The name of this archive reason in the language of [l10n].
  String label(AppLocalizations l10n) => switch (this) {
        ArchiveReason.none => l10n.archiveReasonNone,
        ArchiveReason.sold => l10n.archiveReasonSold,
        ArchiveReason.scrapped => l10n.archiveReasonScrapped,
        ArchiveReason.stolen => l10n.archiveReasonStolen,
        ArchiveReason.destroyed => l10n.archiveReasonDestroyed,
        ArchiveReason.givenAway => l10n.archiveReasonGivenAway,
        ArchiveReason.leaseEnded => l10n.archiveReasonLeaseEnded,
        ArchiveReason.other => l10n.archiveReasonOther,
      };
}

/// How a vehicle is named in dialog titles.
extension VehicleDisplayName on Vehicle {
  /// Make and model followed by the plate, e.g. "Fiat Punto (AB123CD)", or
  /// the plate alone for a vehicle without make and model (schema v1).
  String displayNameWithPlate(AppLocalizations l10n) => switch (makeAndModel) {
        final name? => l10n.vehicleNameWithPlate(name, plate),
        null => plate,
      };

  /// The archive chip of an archived vehicle, e.g. "Sold · Mar 2026" or
  /// "Sold · Mar 2026 · 184,300 km" (the final reading in the unit of
  /// [units]); `null` for an active one.
  String? archiveChipLabel(AppLocalizations l10n, UnitFormatter units) {
    final day = archivedAt;
    if (day == null) return null;
    final reason = (archiveReason ?? ArchiveReason.none).label(l10n);
    final month = day.toLocalDateTime();
    return switch (archivedKm) {
      final km? =>
        l10n.archiveChipWithKm(reason, month, units.distance.format(km)),
      null => l10n.archiveChip(reason, month),
    };
  }
}

/// Localised label of a [VehicleKind].
extension VehicleKindLabel on VehicleKind {
  /// The name of this vehicle kind in the language of [l10n].
  String label(AppLocalizations l10n) => switch (this) {
        VehicleKind.car => l10n.kindCar,
        VehicleKind.van => l10n.kindVan,
        VehicleKind.motorcycle => l10n.kindMotorcycle,
        VehicleKind.moped => l10n.kindMoped,
      };
}

/// Localised label of a [LogEntryType].
extension LogEntryTypeLabel on LogEntryType {
  /// The name of this entry type in the language of [l10n].
  String label(AppLocalizations l10n) => switch (this) {
        LogEntryType.maintenance => l10n.entryTypeMaintenance,
        LogEntryType.repair => l10n.entryTypeRepair,
        LogEntryType.legalDue => l10n.entryTypeLegalDue,
        LogEntryType.refuel => l10n.entryTypeRefuel,
        LogEntryType.expense => l10n.entryTypeExpense,
        LogEntryType.measuredCheck => l10n.entryTypeMeasuredCheck,
        LogEntryType.genericCheck => l10n.entryTypeGenericCheck,
        LogEntryType.note => l10n.entryTypeNote,
      };
}

/// Label of an [AppLanguage] in the Settings page.
extension AppLanguageLabel on AppLanguage {
  /// "System" in the language of [l10n]; each language by its own name
  /// ("Italiano", "Español", "English"), whatever the interface language.
  String label(AppLocalizations l10n) => switch (this) {
        AppLanguage.system => l10n.settingsSystemDefault,
        AppLanguage.italian => l10n.languageNameItalian,
        AppLanguage.spanish => l10n.languageNameSpanish,
        AppLanguage.english => l10n.languageNameEnglish,
      };
}

/// Localised label of an [AppThemeMode].
extension AppThemeModeLabel on AppThemeMode {
  /// The name of this mode in the language of [l10n].
  String label(AppLocalizations l10n) => switch (this) {
        AppThemeMode.system => l10n.settingsSystemDefault,
        AppThemeMode.light => l10n.themeLight,
        AppThemeMode.dark => l10n.themeDark,
      };
}

/// Label of a [UnitPreset] on the Settings page.
extension UnitPresetLabel on UnitPreset {
  /// The name of this preset in the language of [l10n].
  String label(AppLocalizations l10n) => switch (this) {
        UnitPreset.international => l10n.unitPresetInternational,
        UnitPreset.imperial => l10n.unitPresetImperial,
        UnitPreset.custom => l10n.unitPresetCustom,
      };
}

/// Label of a unit in the Settings dialogs and tiles: its name and symbol,
/// e.g. "Kilometres (km)".
extension UnitLabel on UnitConversion {
  /// The name and symbol of this unit in the language of [l10n].
  String label(AppLocalizations l10n) {
    final unit = this;
    final name = switch (unit) {
      DistanceUnit.kilometre => l10n.unitNameKilometre,
      DistanceUnit.mile => l10n.unitNameMile,
      VolumeUnit.litre => l10n.unitNameLitre,
      VolumeUnit.gallonUs => l10n.unitNameGallonUs,
      VolumeUnit.gallonUk => l10n.unitNameGallonUk,
      TemperatureUnit.celsius => l10n.unitNameCelsius,
      TemperatureUnit.fahrenheit => l10n.unitNameFahrenheit,
      PressureUnit.bar => l10n.unitNameBar,
      PressureUnit.psi => l10n.unitNamePsi,
      ConsumptionUnit.litresPer100Km => l10n.unitNameLitresPer100Km,
      ConsumptionUnit.kmPerLitre => l10n.unitNameKmPerLitre,
      ConsumptionUnit.mpgUs => l10n.unitNameMpgUs,
      ConsumptionUnit.mpgUk => l10n.unitNameMpgUk,
      _ => throw ArgumentError.value(unit, 'unit', 'has no name'),
    };
    final symbol = switch (unit) {
      DistanceUnit() => unit.symbol(l10n),
      VolumeUnit() => unit.symbol(l10n),
      TemperatureUnit() => unit.symbol(l10n),
      PressureUnit() => unit.symbol(l10n),
      ConsumptionUnit() => unit.symbol(l10n),
      _ => throw ArgumentError.value(unit, 'unit', 'has no symbol'),
    };
    return l10n.unitOptionLabel(name, symbol);
  }
}

/// Localised message of an [ActionError].
extension ActionErrorMessage on ActionError {
  /// The message shown to the user for this error, in the language of
  /// [l10n]. Every message says explicitly what happened to the data:
  /// nothing was changed, except after an import that could not be undone.
  String message(AppLocalizations l10n) => switch (this) {
        ActionError.duplicatePlate => l10n.errorDuplicatePlate,
        ActionError.ownerHasVehicles => l10n.errorOwnerHasVehicles,
        ActionError.ownerHasTrashedVehicles =>
          l10n.errorOwnerHasTrashedVehicles,
        ActionError.ownerNotFound => l10n.errorOwnerNotFound,
        ActionError.vehicleNotFound => l10n.errorVehicleNotFound,
        ActionError.vehicleArchived => l10n.errorVehicleArchived,
        ActionError.entryNotFound => l10n.errorEntryNotFound,
        ActionError.readingNotFound => l10n.errorReadingNotFound,
        ActionError.attachmentNotFound => l10n.errorAttachmentNotFound,
        ActionError.attachmentTooLarge => l10n.errorAttachmentTooLarge,
        ActionError.cameraDenied => l10n.errorCameraDenied,
        ActionError.photosDenied => l10n.errorPhotosDenied,
        ActionError.pickFailed => l10n.errorPickFailed,
        ActionError.saveFailed => l10n.errorSaveFailed,
        ActionError.openNoApp => l10n.errorOpenNoApp,
        ActionError.shareFailed => l10n.errorShareFailed,
        ActionError.attachmentFileMissing => l10n.errorFileMissing,
        ActionError.readingNotDeletable => l10n.errorReadingNotDeletable,
        ActionError.readingNotEditable => l10n.errorReadingNotEditable,
        ActionError.newerReadingExists => l10n.errorNewerReadingExists,
        ActionError.invalidInput => l10n.errorInvalidInput,
        ActionError.backupNotAPackage => l10n.errorBackupNotAPackage,
        ActionError.backupFromNewerApp => l10n.errorBackupFromNewerApp,
        ActionError.backupCorrupt => l10n.errorBackupCorrupt,
        ActionError.backupNoSpace => l10n.errorBackupNoSpace,
        ActionError.exportFailed => l10n.errorExportFailed,
        ActionError.importFailed => l10n.errorImportFailed,
        ActionError.importRestoreFailed => l10n.errorImportRestoreFailed,
        ActionError.driveOffline => l10n.errorDriveOffline,
        ActionError.driveFailed => l10n.errorDriveFailed,
        ActionError.driveNeedsRelink => l10n.errorDriveRelink,
        ActionError.driveLinkFailed => l10n.errorDriveLinkFailed,
        ActionError.driveCloudChanged => l10n.errorDriveCloudChanged,
        ActionError.driveCloudTooNew => l10n.errorDriveCloudTooNew,
        ActionError.unexpected => l10n.errorUnexpected,
      };
}
