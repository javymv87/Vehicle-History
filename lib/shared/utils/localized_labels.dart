import '../../data/models/fuel_type.dart';
import '../../data/models/log_entry_type.dart';
import '../../data/models/vehicle_kind.dart';
import '../../l10n/app_localizations.dart';
import 'action_result.dart';

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

/// Localised message of an [ActionError].
extension ActionErrorMessage on ActionError {
  /// The message shown to the user for this error, in the language of
  /// [l10n]. Every message says explicitly that nothing was changed.
  String message(AppLocalizations l10n) => switch (this) {
        ActionError.duplicatePlate => l10n.errorDuplicatePlate,
        ActionError.ownerHasVehicles => l10n.errorOwnerHasVehicles,
        ActionError.ownerNotFound => l10n.errorOwnerNotFound,
        ActionError.vehicleNotFound => l10n.errorVehicleNotFound,
        ActionError.entryNotFound => l10n.errorEntryNotFound,
        ActionError.invalidInput => l10n.errorInvalidInput,
        ActionError.unexpected => l10n.errorUnexpected,
      };
}
