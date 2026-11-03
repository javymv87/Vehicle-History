import 'fuel_type.dart';
import 'log_entry_type.dart';
import 'vehicle_kind.dart';

/// The family a [ReminderKind] belongs to, used to group the kind picker.
enum ReminderKindGroup {
  /// Engine: oil, filters, plugs, belts, valves…
  engine,

  /// Cooling system.
  cooling,

  /// Gearbox, clutch, differentials and the final drive of motorcycles.
  transmission,

  /// Brake fluid and the brake components, one kind per component and axle.
  brakes,

  /// Suspension and steering.
  suspension,

  /// Tyres and wheels.
  wheels,

  /// 12 V electrical system, lights, air conditioning.
  electrical,

  /// Fuel lines, exhaust and emissions.
  fuelExhaust,

  /// LPG and CNG systems of bi-fuel vehicles.
  gasSystem,

  /// High-voltage system of electric and hybrid vehicles.
  highVoltage,

  /// Legal deadlines and documents of the vehicle.
  legal,

  /// The whole service as one item, the inspection list, anything else.
  general,
}

/// Every vehicle kind.
const Set<VehicleKind> _allKinds = {
  VehicleKind.car,
  VehicleKind.van,
  VehicleKind.motorcycle,
  VehicleKind.moped,
};

/// Cars and vans ("C" in the catalogue of step 13a).
const Set<VehicleKind> _cars = {VehicleKind.car, VehicleKind.van};

/// Motorcycles and mopeds ("M").
const Set<VehicleKind> _bikes = {VehicleKind.motorcycle, VehicleKind.moped};

/// Every fuel type.
const Set<FuelType> _allFuels = {
  FuelType.petrol,
  FuelType.diesel,
  FuelType.petrolLpg,
  FuelType.petrolCng,
  FuelType.hybrid,
  FuelType.pluginHybrid,
  FuelType.electric,
  FuelType.other,
};

/// Every fuel type but electric ("not E").
const Set<FuelType> _notElectric = {
  FuelType.petrol,
  FuelType.diesel,
  FuelType.petrolLpg,
  FuelType.petrolCng,
  FuelType.hybrid,
  FuelType.pluginHybrid,
  FuelType.other,
};

/// Every fuel type but diesel and electric ("not D, not E").
const Set<FuelType> _notDieselNorElectric = {
  FuelType.petrol,
  FuelType.petrolLpg,
  FuelType.petrolCng,
  FuelType.hybrid,
  FuelType.pluginHybrid,
  FuelType.other,
};

/// Diesel only ("D").
const Set<FuelType> _diesel = {FuelType.diesel};

/// Electric and hybrids ("E or H").
const Set<FuelType> _electricOrHybrid = {
  FuelType.electric,
  FuelType.hybrid,
  FuelType.pluginHybrid,
};

/// Electric and plug-in hybrid ("E or plug-in hybrid").
const Set<FuelType> _pluggable = {FuelType.electric, FuelType.pluginHybrid};

/// Petrol + LPG ("G").
const Set<FuelType> _lpg = {FuelType.petrolLpg};

/// Petrol + CNG ("N").
const Set<FuelType> _cng = {FuelType.petrolCng};

/// Both bi-fuel types ("G or N").
const Set<FuelType> _gas = {FuelType.petrolLpg, FuelType.petrolCng};

/// The fixed catalogue of what a reminder can be about
/// (`Docs/08_recordatorios.md`): a Dart enum for now, standing in for the
/// user-editable `MaintenanceType` table planned for a later step.
///
/// Stored through its explicit [code], never `Enum.name`. [vehicleKinds]
/// and [fuelTypes] only filter the picker (the list helps, never blocks):
/// the repository accepts any kind on any vehicle.
enum ReminderKind {
  // engine
  /// Engine oil.
  engineOil('engine_oil', ReminderKindGroup.engine, _allKinds, _notElectric),

  /// Oil filter.
  oilFilter('oil_filter', ReminderKindGroup.engine, _allKinds, _notElectric),

  /// Air filter.
  airFilter('air_filter', ReminderKindGroup.engine, _allKinds, _notElectric),

  /// Fuel filter.
  fuelFilter('fuel_filter', ReminderKindGroup.engine, _allKinds, _notElectric),

  /// Cabin (pollen) filter.
  cabinFilter('cabin_filter', ReminderKindGroup.engine, _cars, _allFuels),

  /// Spark plugs.
  sparkPlugs(
    'spark_plugs',
    ReminderKindGroup.engine,
    _allKinds,
    _notDieselNorElectric,
  ),

  /// Glow plugs of a diesel engine.
  glowPlugs('glow_plugs', ReminderKindGroup.engine, _allKinds, _diesel),

  /// Timing belt.
  timingBelt('timing_belt', ReminderKindGroup.engine, _allKinds, _notElectric),

  /// Timing chain check.
  timingChainCheck(
    'timing_chain_check',
    ReminderKindGroup.engine,
    _allKinds,
    _notElectric,
  ),

  /// Auxiliary (accessory) belt.
  auxiliaryBelt(
    'auxiliary_belt',
    ReminderKindGroup.engine,
    _allKinds,
    _notElectric,
  ),

  /// Valve clearance adjustment.
  valveClearance(
    'valve_clearance',
    ReminderKindGroup.engine,
    _allKinds,
    _notElectric,
  ),

  /// Crankcase breather.
  crankcaseBreather(
    'crankcase_breather',
    ReminderKindGroup.engine,
    _allKinds,
    _notElectric,
  ),

  /// Throttle body cleaning.
  throttleBodyClean(
    'throttle_body_clean',
    ReminderKindGroup.engine,
    _allKinds,
    _notElectric,
  ),

  /// Diesel particulate filter check.
  dpfCheck('dpf_check', ReminderKindGroup.engine, _allKinds, _diesel),

  /// AdBlue refill.
  adblueRefill('adblue_refill', ReminderKindGroup.engine, _cars, _diesel),

  /// Engine mounts check.
  engineMountsCheck(
    'engine_mounts_check',
    ReminderKindGroup.engine,
    _allKinds,
    _allFuels,
  ),

  // cooling
  /// Coolant.
  coolant('coolant', ReminderKindGroup.cooling, _allKinds, _allFuels),

  /// Radiator check.
  radiatorCheck(
    'radiator_check',
    ReminderKindGroup.cooling,
    _allKinds,
    _allFuels,
  ),

  /// Cooling hoses.
  coolingHoses(
    'cooling_hoses',
    ReminderKindGroup.cooling,
    _allKinds,
    _allFuels,
  ),

  // transmission
  /// Manual gearbox oil.
  gearboxOil(
    'gearbox_oil',
    ReminderKindGroup.transmission,
    _allKinds,
    _notElectric,
  ),

  /// Automatic, CVT or DCT transmission fluid.
  transmissionFluid(
    'transmission_fluid',
    ReminderKindGroup.transmission,
    _cars,
    _notElectric,
  ),

  /// Clutch fluid.
  clutchFluid(
    'clutch_fluid',
    ReminderKindGroup.transmission,
    _allKinds,
    _notElectric,
  ),

  /// Clutch check.
  clutchCheck(
    'clutch_check',
    ReminderKindGroup.transmission,
    _allKinds,
    _notElectric,
  ),

  /// Differential oil.
  differentialOil(
    'differential_oil',
    ReminderKindGroup.transmission,
    _cars,
    _allFuels,
  ),

  /// Transfer case oil.
  transferCaseOil(
    'transfer_case_oil',
    ReminderKindGroup.transmission,
    _cars,
    _allFuels,
  ),

  /// CV boots check.
  cvBootsCheck(
    'cv_boots_check',
    ReminderKindGroup.transmission,
    _cars,
    _allFuels,
  ),

  /// Drive chain lubrication.
  driveChainLube(
    'drive_chain_lube',
    ReminderKindGroup.transmission,
    _bikes,
    _allFuels,
  ),

  /// Drive chain kit: chain and sprockets.
  driveChainKit(
    'drive_chain_kit',
    ReminderKindGroup.transmission,
    _bikes,
    _allFuels,
  ),

  /// Drive belt of a motorcycle.
  driveBelt('drive_belt', ReminderKindGroup.transmission, _bikes, _allFuels),

  /// CVT rollers and belt of a scooter.
  cvtRollersBelt(
    'cvt_rollers_belt',
    ReminderKindGroup.transmission,
    _bikes,
    _allFuels,
  ),

  /// Final drive oil of a shaft drive.
  finalDriveOil(
    'final_drive_oil',
    ReminderKindGroup.transmission,
    _bikes,
    _allFuels,
  ),

  /// Reduction gear oil of an electric or hybrid drive.
  reductionGearOil(
    'reduction_gear_oil',
    ReminderKindGroup.transmission,
    _allKinds,
    _electricOrHybrid,
  ),

  // brakes
  /// Brake fluid.
  brakeFluid('brake_fluid', ReminderKindGroup.brakes, _allKinds, _allFuels),

  /// Front brake pads.
  brakePadsFront(
    'brake_pads_front',
    ReminderKindGroup.brakes,
    _allKinds,
    _allFuels,
  ),

  /// Rear brake pads.
  brakePadsRear(
    'brake_pads_rear',
    ReminderKindGroup.brakes,
    _allKinds,
    _allFuels,
  ),

  /// Front brake discs.
  brakeDiscsFront(
    'brake_discs_front',
    ReminderKindGroup.brakes,
    _allKinds,
    _allFuels,
  ),

  /// Rear brake discs.
  brakeDiscsRear(
    'brake_discs_rear',
    ReminderKindGroup.brakes,
    _allKinds,
    _allFuels,
  ),

  /// Front brake shoes.
  brakeShoesFront(
    'brake_shoes_front',
    ReminderKindGroup.brakes,
    _allKinds,
    _allFuels,
  ),

  /// Rear brake shoes.
  brakeShoesRear(
    'brake_shoes_rear',
    ReminderKindGroup.brakes,
    _allKinds,
    _allFuels,
  ),

  /// Front brake drums.
  brakeDrumsFront(
    'brake_drums_front',
    ReminderKindGroup.brakes,
    _allKinds,
    _allFuels,
  ),

  /// Rear brake drums.
  brakeDrumsRear(
    'brake_drums_rear',
    ReminderKindGroup.brakes,
    _allKinds,
    _allFuels,
  ),

  /// Parking brake adjustment.
  parkingBrakeAdjust(
    'parking_brake_adjust',
    ReminderKindGroup.brakes,
    _cars,
    _allFuels,
  ),

  /// Brake hoses.
  brakeHoses('brake_hoses', ReminderKindGroup.brakes, _allKinds, _allFuels),

  // suspension
  /// Shock absorbers.
  shockAbsorbers(
    'shock_absorbers',
    ReminderKindGroup.suspension,
    _allKinds,
    _allFuels,
  ),

  /// Fork oil of a motorcycle.
  forkOil('fork_oil', ReminderKindGroup.suspension, _bikes, _allFuels),

  /// Steering head bearings.
  steeringHeadBearings(
    'steering_head_bearings',
    ReminderKindGroup.suspension,
    _bikes,
    _allFuels,
  ),

  /// Swingarm pivot.
  swingarmPivot(
    'swingarm_pivot',
    ReminderKindGroup.suspension,
    _bikes,
    _allFuels,
  ),

  /// Wheel bearings.
  wheelBearings(
    'wheel_bearings',
    ReminderKindGroup.suspension,
    _allKinds,
    _allFuels,
  ),

  /// Ball joints and tie rods.
  ballJointsTieRods(
    'ball_joints_tie_rods',
    ReminderKindGroup.suspension,
    _cars,
    _allFuels,
  ),

  /// Power steering fluid.
  powerSteeringFluid(
    'power_steering_fluid',
    ReminderKindGroup.suspension,
    _cars,
    _notElectric,
  ),

  /// Wheel alignment.
  wheelAlignment(
    'wheel_alignment',
    ReminderKindGroup.suspension,
    _cars,
    _allFuels,
  ),

  // wheels
  /// Tyre replacement.
  tyresReplace('tyres_replace', ReminderKindGroup.wheels, _allKinds, _allFuels),

  /// Tyre rotation.
  tyresRotation('tyres_rotation', ReminderKindGroup.wheels, _cars, _allFuels),

  /// Seasonal tyre swap (summer / winter).
  tyresSeasonalSwap(
    'tyres_seasonal_swap',
    ReminderKindGroup.wheels,
    _cars,
    _allFuels,
  ),

  /// Tyre pressure check.
  tyrePressureCheck(
    'tyre_pressure_check',
    ReminderKindGroup.wheels,
    _allKinds,
    _allFuels,
  ),

  /// Wheel balancing.
  wheelBalancing(
    'wheel_balancing',
    ReminderKindGroup.wheels,
    _allKinds,
    _allFuels,
  ),

  // electrical
  /// 12 V battery replacement.
  battery12v('battery_12v', ReminderKindGroup.electrical, _allKinds, _allFuels),

  /// Battery check.
  batteryCheck(
    'battery_check',
    ReminderKindGroup.electrical,
    _allKinds,
    _allFuels,
  ),

  /// Lights check.
  lightsCheck(
    'lights_check',
    ReminderKindGroup.electrical,
    _allKinds,
    _allFuels,
  ),

  /// Wiper blades.
  wiperBlades('wiper_blades', ReminderKindGroup.electrical, _cars, _allFuels),

  /// Washer fluid.
  washerFluid('washer_fluid', ReminderKindGroup.electrical, _cars, _allFuels),

  /// Air conditioning gas recharge.
  acGasRecharge(
    'ac_gas_recharge',
    ReminderKindGroup.electrical,
    _cars,
    _allFuels,
  ),

  /// Air conditioning disinfection.
  acSystemDisinfect(
    'ac_system_disinfect',
    ReminderKindGroup.electrical,
    _cars,
    _allFuels,
  ),

  /// Key fob battery.
  keyFobBattery(
    'key_fob_battery',
    ReminderKindGroup.electrical,
    _cars,
    _allFuels,
  ),

  // fuelExhaust
  /// Fuel lines check.
  fuelLinesCheck(
    'fuel_lines_check',
    ReminderKindGroup.fuelExhaust,
    _allKinds,
    _notElectric,
  ),

  /// Exhaust check.
  exhaustCheck(
    'exhaust_check',
    ReminderKindGroup.fuelExhaust,
    _allKinds,
    _notElectric,
  ),

  /// Evaporative emission system check.
  evapSystemCheck(
    'evap_system_check',
    ReminderKindGroup.fuelExhaust,
    _allKinds,
    _notDieselNorElectric,
  ),

  /// Fuel injector cleaning.
  fuelInjectorClean(
    'fuel_injector_clean',
    ReminderKindGroup.fuelExhaust,
    _allKinds,
    _notElectric,
  ),

  // gasSystem
  /// LPG filter.
  lpgFilter('lpg_filter', ReminderKindGroup.gasSystem, _allKinds, _lpg),

  /// LPG injectors check.
  lpgInjectorsCheck(
    'lpg_injectors_check',
    ReminderKindGroup.gasSystem,
    _allKinds,
    _lpg,
  ),

  /// LPG tank replacement.
  lpgTankReplace(
    'lpg_tank_replace',
    ReminderKindGroup.gasSystem,
    _allKinds,
    _lpg,
  ),

  /// CNG filter.
  cngFilter('cng_filter', ReminderKindGroup.gasSystem, _allKinds, _cng),

  /// CNG cylinder inspection.
  cngCylinderInspection(
    'cng_cylinder_inspection',
    ReminderKindGroup.gasSystem,
    _allKinds,
    _cng,
  ),

  /// Gas system inspection (LPG or CNG).
  gasSystemInspection(
    'gas_system_inspection',
    ReminderKindGroup.gasSystem,
    _allKinds,
    _gas,
  ),

  // highVoltage
  /// High-voltage battery check.
  hvBatteryCheck(
    'hv_battery_check',
    ReminderKindGroup.highVoltage,
    _allKinds,
    _electricOrHybrid,
  ),

  /// High-voltage battery coolant.
  hvBatteryCoolant(
    'hv_battery_coolant',
    ReminderKindGroup.highVoltage,
    _allKinds,
    _electricOrHybrid,
  ),

  /// Charging port check.
  chargingPortCheck(
    'charging_port_check',
    ReminderKindGroup.highVoltage,
    _allKinds,
    _pluggable,
  ),

  // legal
  /// Compulsory periodic inspection (revisione).
  inspection('inspection', ReminderKindGroup.legal, _allKinds, _allFuels),

  /// Road tax (bollo).
  roadTax('road_tax', ReminderKindGroup.legal, _allKinds, _allFuels),

  /// Insurance.
  insurance('insurance', ReminderKindGroup.legal, _allKinds, _allFuels),

  /// Italian surcharge on powerful cars (superbollo).
  superbollo('superbollo', ReminderKindGroup.legal, _cars, _allFuels),

  /// Any other document of the vehicle; not unique per vehicle.
  otherDocument(
    'other_document',
    ReminderKindGroup.legal,
    _allKinds,
    _allFuels,
  ),

  // general
  /// The whole scheduled service ("tagliando") as one item.
  scheduledService(
    'scheduled_service',
    ReminderKindGroup.general,
    _allKinds,
    _allFuels,
  ),

  /// The annual inspection list of motorcycle manuals.
  inspectionChecklist(
    'inspection_checklist',
    ReminderKindGroup.general,
    _allKinds,
    _allFuels,
  ),

  /// Anything else, with a free title; not unique per vehicle.
  other('other', ReminderKindGroup.general, _allKinds, _allFuels);

  const ReminderKind(this.code, this.group, this.vehicleKinds, this.fuelTypes);

  /// Text stored in `reminders.kind`. Stable: the runbook of
  /// `Docs/08_recordatorios.md` writes it too.
  final String code;

  /// The family shown as a header in the picker.
  final ReminderKindGroup group;

  /// Vehicle kinds the picker offers this kind for.
  final Set<VehicleKind> vehicleKinds;

  /// Fuel types the picker offers this kind for.
  final Set<FuelType> fuelTypes;

  /// Whether the picker offers this kind for a vehicle of [kind] running on
  /// [fuel]. A UI filter only: "Show all" lists every kind, and the
  /// repository accepts any.
  bool appliesTo(VehicleKind kind, FuelType fuel) =>
      vehicleKinds.contains(kind) && fuelTypes.contains(fuel);

  /// Whether this is a legal deadline or document rather than work on the
  /// vehicle.
  bool get isLegal => group == ReminderKindGroup.legal;

  /// The entry types that can close a reminder of this kind: a legal
  /// deadline is closed by paying or renewing it, anything else by work on
  /// the vehicle.
  Set<LogEntryType> get closingEntryTypes => isLegal
      ? const {LogEntryType.legalDue, LogEntryType.expense}
      : const {LogEntryType.maintenance, LogEntryType.repair};

  /// The type of the entry "Mark done" creates.
  LogEntryType get markDoneEntryType =>
      isLegal ? LogEntryType.legalDue : LogEntryType.maintenance;

  /// Whether a vehicle may have only one live, uncompleted reminder of this
  /// kind (`Docs/04_maintenance_logic.md`: an assigned type does not appear
  /// again). [other] and [otherDocument] can repeat.
  bool get uniquePerVehicle => this != other && this != otherDocument;

  /// The kind stored as [code], or `null` when the code is unknown.
  static ReminderKind? fromCode(String code) {
    for (final kind in values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}
