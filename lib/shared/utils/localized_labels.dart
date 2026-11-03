import '../../data/models/app_preferences.dart';
import '../../data/models/archive_reason.dart';
import '../../data/models/fuel_consumption.dart';
import '../../data/models/fuel_type.dart';
import '../../data/models/log_entry_type.dart';
import '../../data/models/refuel.dart';
import '../../data/models/reminder.dart';
import '../../data/models/reminder_kind.dart';
import '../../data/models/reminder_status.dart';
import '../../data/models/trashed_vehicle.dart';
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

/// Localised label of a [RefuelFuel].
extension RefuelFuelLabel on RefuelFuel {
  /// The name of this fuel in the language of [l10n].
  String label(AppLocalizations l10n) => switch (this) {
        RefuelFuel.petrol => l10n.refuelFuelPetrol,
        RefuelFuel.diesel => l10n.refuelFuelDiesel,
        RefuelFuel.lpg => l10n.refuelFuelLpg,
        RefuelFuel.cng => l10n.refuelFuelCng,
        RefuelFuel.other => l10n.refuelFuelOther,
      };
}

/// Localised reason of a [SegmentProblem], to complete
/// `AppLocalizations.segmentInvalid`.
extension SegmentProblemLabel on SegmentProblem {
  /// Why the segment cannot be computed, in the language of [l10n].
  String label(AppLocalizations l10n) => switch (this) {
        SegmentProblem.missedRefuel => l10n.segmentProblemMissedRefuel,
        SegmentProblem.missingVolume => l10n.segmentProblemMissingVolume,
        SegmentProblem.missingKm => l10n.segmentProblemMissingKm,
        SegmentProblem.noDistance => l10n.segmentProblemNoDistance,
        SegmentProblem.noVolume => l10n.segmentProblemNoVolume,
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

/// Localised message of an [ActionFailure], naming its count when the
/// error has one.
extension ActionFailureMessage on ActionFailure<Object?> {
  /// The message of [error], with [count] where the message names it.
  String message(AppLocalizations l10n) => switch ((error, count)) {
        (ActionError.fuelTypeConflict, final int count) =>
          l10n.errorFuelTypeConflictCount(count),
        _ => error.message(l10n),
      };
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
        ActionError.fuelTypeConflict => l10n.errorFuelTypeConflict,
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
        ActionError.reminderNotFound => l10n.errorReminderNotFound,
        ActionError.reminderKindInUse => l10n.errorReminderKindInUse,
        ActionError.reminderRule => l10n.errorReminderRule,
        ActionError.unexpected => l10n.errorUnexpected,
      };
}

/// Localised name of a [ReminderKind].
extension ReminderKindLabel on ReminderKind {
  /// The name of this kind in the language of [l10n], also the title the
  /// reminder form prefills.
  String label(AppLocalizations l10n) => switch (this) {
        ReminderKind.engineOil => l10n.reminderKindEngineOil,
        ReminderKind.oilFilter => l10n.reminderKindOilFilter,
        ReminderKind.airFilter => l10n.reminderKindAirFilter,
        ReminderKind.fuelFilter => l10n.reminderKindFuelFilter,
        ReminderKind.cabinFilter => l10n.reminderKindCabinFilter,
        ReminderKind.sparkPlugs => l10n.reminderKindSparkPlugs,
        ReminderKind.glowPlugs => l10n.reminderKindGlowPlugs,
        ReminderKind.timingBelt => l10n.reminderKindTimingBelt,
        ReminderKind.timingChainCheck => l10n.reminderKindTimingChainCheck,
        ReminderKind.auxiliaryBelt => l10n.reminderKindAuxiliaryBelt,
        ReminderKind.valveClearance => l10n.reminderKindValveClearance,
        ReminderKind.crankcaseBreather => l10n.reminderKindCrankcaseBreather,
        ReminderKind.throttleBodyClean => l10n.reminderKindThrottleBodyClean,
        ReminderKind.dpfCheck => l10n.reminderKindDpfCheck,
        ReminderKind.adblueRefill => l10n.reminderKindAdblueRefill,
        ReminderKind.engineMountsCheck => l10n.reminderKindEngineMountsCheck,
        ReminderKind.coolant => l10n.reminderKindCoolant,
        ReminderKind.radiatorCheck => l10n.reminderKindRadiatorCheck,
        ReminderKind.coolingHoses => l10n.reminderKindCoolingHoses,
        ReminderKind.gearboxOil => l10n.reminderKindGearboxOil,
        ReminderKind.transmissionFluid => l10n.reminderKindTransmissionFluid,
        ReminderKind.clutchFluid => l10n.reminderKindClutchFluid,
        ReminderKind.clutchCheck => l10n.reminderKindClutchCheck,
        ReminderKind.differentialOil => l10n.reminderKindDifferentialOil,
        ReminderKind.transferCaseOil => l10n.reminderKindTransferCaseOil,
        ReminderKind.cvBootsCheck => l10n.reminderKindCvBootsCheck,
        ReminderKind.driveChainLube => l10n.reminderKindDriveChainLube,
        ReminderKind.driveChainKit => l10n.reminderKindDriveChainKit,
        ReminderKind.driveBelt => l10n.reminderKindDriveBelt,
        ReminderKind.cvtRollersBelt => l10n.reminderKindCvtRollersBelt,
        ReminderKind.finalDriveOil => l10n.reminderKindFinalDriveOil,
        ReminderKind.reductionGearOil => l10n.reminderKindReductionGearOil,
        ReminderKind.brakeFluid => l10n.reminderKindBrakeFluid,
        ReminderKind.brakePadsFront => l10n.reminderKindBrakePadsFront,
        ReminderKind.brakePadsRear => l10n.reminderKindBrakePadsRear,
        ReminderKind.brakeDiscsFront => l10n.reminderKindBrakeDiscsFront,
        ReminderKind.brakeDiscsRear => l10n.reminderKindBrakeDiscsRear,
        ReminderKind.brakeShoesFront => l10n.reminderKindBrakeShoesFront,
        ReminderKind.brakeShoesRear => l10n.reminderKindBrakeShoesRear,
        ReminderKind.brakeDrumsFront => l10n.reminderKindBrakeDrumsFront,
        ReminderKind.brakeDrumsRear => l10n.reminderKindBrakeDrumsRear,
        ReminderKind.parkingBrakeAdjust => l10n.reminderKindParkingBrakeAdjust,
        ReminderKind.brakeHoses => l10n.reminderKindBrakeHoses,
        ReminderKind.shockAbsorbers => l10n.reminderKindShockAbsorbers,
        ReminderKind.forkOil => l10n.reminderKindForkOil,
        ReminderKind.steeringHeadBearings =>
          l10n.reminderKindSteeringHeadBearings,
        ReminderKind.swingarmPivot => l10n.reminderKindSwingarmPivot,
        ReminderKind.wheelBearings => l10n.reminderKindWheelBearings,
        ReminderKind.ballJointsTieRods => l10n.reminderKindBallJointsTieRods,
        ReminderKind.powerSteeringFluid => l10n.reminderKindPowerSteeringFluid,
        ReminderKind.wheelAlignment => l10n.reminderKindWheelAlignment,
        ReminderKind.tyresReplace => l10n.reminderKindTyresReplace,
        ReminderKind.tyresRotation => l10n.reminderKindTyresRotation,
        ReminderKind.tyresSeasonalSwap => l10n.reminderKindTyresSeasonalSwap,
        ReminderKind.tyrePressureCheck => l10n.reminderKindTyrePressureCheck,
        ReminderKind.wheelBalancing => l10n.reminderKindWheelBalancing,
        ReminderKind.battery12v => l10n.reminderKindBattery12v,
        ReminderKind.batteryCheck => l10n.reminderKindBatteryCheck,
        ReminderKind.lightsCheck => l10n.reminderKindLightsCheck,
        ReminderKind.wiperBlades => l10n.reminderKindWiperBlades,
        ReminderKind.washerFluid => l10n.reminderKindWasherFluid,
        ReminderKind.acGasRecharge => l10n.reminderKindAcGasRecharge,
        ReminderKind.acSystemDisinfect => l10n.reminderKindAcSystemDisinfect,
        ReminderKind.keyFobBattery => l10n.reminderKindKeyFobBattery,
        ReminderKind.fuelLinesCheck => l10n.reminderKindFuelLinesCheck,
        ReminderKind.exhaustCheck => l10n.reminderKindExhaustCheck,
        ReminderKind.evapSystemCheck => l10n.reminderKindEvapSystemCheck,
        ReminderKind.fuelInjectorClean => l10n.reminderKindFuelInjectorClean,
        ReminderKind.lpgFilter => l10n.reminderKindLpgFilter,
        ReminderKind.lpgInjectorsCheck => l10n.reminderKindLpgInjectorsCheck,
        ReminderKind.lpgTankReplace => l10n.reminderKindLpgTankReplace,
        ReminderKind.cngFilter => l10n.reminderKindCngFilter,
        ReminderKind.cngCylinderInspection =>
          l10n.reminderKindCngCylinderInspection,
        ReminderKind.gasSystemInspection =>
          l10n.reminderKindGasSystemInspection,
        ReminderKind.hvBatteryCheck => l10n.reminderKindHvBatteryCheck,
        ReminderKind.hvBatteryCoolant => l10n.reminderKindHvBatteryCoolant,
        ReminderKind.chargingPortCheck => l10n.reminderKindChargingPortCheck,
        ReminderKind.inspection => l10n.reminderKindInspection,
        ReminderKind.roadTax => l10n.reminderKindRoadTax,
        ReminderKind.insurance => l10n.reminderKindInsurance,
        ReminderKind.superbollo => l10n.reminderKindSuperbollo,
        ReminderKind.otherDocument => l10n.reminderKindOtherDocument,
        ReminderKind.scheduledService => l10n.reminderKindScheduledService,
        ReminderKind.inspectionChecklist =>
          l10n.reminderKindInspectionChecklist,
        ReminderKind.other => l10n.reminderKindOther,
      };
}

/// Localised header of a [ReminderKindGroup] in the kind picker.
extension ReminderKindGroupLabel on ReminderKindGroup {
  /// The name of this group in the language of [l10n].
  String label(AppLocalizations l10n) => switch (this) {
        ReminderKindGroup.engine => l10n.reminderGroupEngine,
        ReminderKindGroup.cooling => l10n.reminderGroupCooling,
        ReminderKindGroup.transmission => l10n.reminderGroupTransmission,
        ReminderKindGroup.brakes => l10n.reminderGroupBrakes,
        ReminderKindGroup.suspension => l10n.reminderGroupSuspension,
        ReminderKindGroup.wheels => l10n.reminderGroupWheels,
        ReminderKindGroup.electrical => l10n.reminderGroupElectrical,
        ReminderKindGroup.fuelExhaust => l10n.reminderGroupFuelExhaust,
        ReminderKindGroup.gasSystem => l10n.reminderGroupGasSystem,
        ReminderKindGroup.highVoltage => l10n.reminderGroupHighVoltage,
        ReminderKindGroup.legal => l10n.reminderGroupLegal,
        ReminderKindGroup.general => l10n.reminderGroupGeneral,
      };
}

/// Localised name of a [ReminderStatus].
extension ReminderStatusLabel on ReminderStatus {
  /// The status in the language of [l10n]: always shown next to its colour
  /// and icon, never by the colour alone.
  String label(AppLocalizations l10n) => switch (this) {
        ReminderStatus.overdue => l10n.reminderStatusOverdue,
        ReminderStatus.dueSoon => l10n.reminderStatusDueSoon,
        ReminderStatus.ok => l10n.reminderStatusOk,
        ReminderStatus.completed => l10n.reminderStatusCompleted,
      };
}

/// Localised name of a [ReminderChangeType] in a reminder's history.
extension ReminderChangeTypeLabel on ReminderChangeType {
  /// What the change was, in the language of [l10n].
  String label(AppLocalizations l10n) => switch (this) {
        ReminderChangeType.create => l10n.reminderChangeCreate,
        ReminderChangeType.edit => l10n.reminderChangeEdit,
        ReminderChangeType.applyOverride => l10n.reminderChangeOverride,
        ReminderChangeType.restoreReference =>
          l10n.reminderChangeRestoreReference,
        ReminderChangeType.snooze => l10n.reminderChangeSnooze,
        ReminderChangeType.unsnooze => l10n.reminderChangeUnsnooze,
        ReminderChangeType.close => l10n.reminderChangeClose,
        ReminderChangeType.complete => l10n.reminderChangeComplete,
      };
}

/// Joins [parts] as a localised list: "a, b and c" (the conjunction of
/// the language of [l10n]); a single part as it is.
String joinAsList(AppLocalizations l10n, List<String> parts) {
  if (parts.isEmpty) return '';
  var joined = parts.first;
  for (var i = 1; i < parts.length; i++) {
    joined = i == parts.length - 1
        ? l10n.listJoinAnd(joined, parts[i])
        : l10n.listJoinComma(joined, parts[i]);
  }
  return joined;
}

/// What goes with a deleted vehicle, as the messages of the delete and
/// purge confirmations and the Trash row name it (U16).
extension VehicleContentsTexts on VehicleContents {
  /// The parts as a list, e.g. "its 3 entries, its 2 odometer readings and
  /// 1 reminder"; attachments and reminders only when there are some.
  String asList(AppLocalizations l10n) => joinAsList(l10n, [
        l10n.vehicleContentsEntries(entryCount),
        l10n.vehicleContentsReadings(readingCount),
        if (attachmentCount > 0)
          l10n.vehicleContentsAttachments(attachmentCount),
        if (reminderCount > 0) l10n.vehicleContentsReminders(reminderCount),
      ]);

  /// The message of the delete confirmation of the vehicle.
  String deleteMessage(AppLocalizations l10n) => reminderCount > 0
      ? l10n.deleteVehicleMessageList(asList(l10n))
      : attachmentCount == 0
          ? l10n.deleteVehicleMessage(entryCount, readingCount)
          : l10n.deleteVehicleMessageWithAttachments(
              entryCount,
              readingCount,
              attachmentCount,
            );

  /// The message of the permanent delete confirmation of the vehicle.
  String purgeMessage(AppLocalizations l10n) => reminderCount > 0
      ? l10n.purgeVehicleMessageList(asList(l10n))
      : attachmentCount == 0
          ? l10n.purgeVehicleMessage(entryCount, readingCount)
          : l10n.purgeVehicleMessageWithAttachments(
              entryCount,
              readingCount,
              attachmentCount,
            );

  /// The counts line of the Trash row.
  String trashLine(AppLocalizations l10n) {
    final counts = attachmentCount == 0
        ? l10n.trashContents(entryCount, readingCount)
        : l10n.trashContentsWithAttachments(
            entryCount,
            readingCount,
            attachmentCount,
          );
    return reminderCount > 0
        ? l10n.trashContentsWithReminders(counts, reminderCount)
        : counts;
  }
}
