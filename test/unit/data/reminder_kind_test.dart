import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/db/converters.dart';
import 'package:vehicle_history/data/models/fuel_type.dart';
import 'package:vehicle_history/data/models/log_entry_type.dart';
import 'package:vehicle_history/data/models/reminder_kind.dart';
import 'package:vehicle_history/data/models/vehicle_kind.dart';

/// The catalogue of step 13a, group by group, exactly: the loading
/// procedure of `Docs/08_recordatorios.md` writes these codes.
const Map<ReminderKindGroup, List<String>> catalogue = {
  ReminderKindGroup.engine: [
    'engine_oil',
    'oil_filter',
    'air_filter',
    'fuel_filter',
    'cabin_filter',
    'spark_plugs',
    'glow_plugs',
    'timing_belt',
    'timing_chain_check',
    'auxiliary_belt',
    'valve_clearance',
    'crankcase_breather',
    'throttle_body_clean',
    'dpf_check',
    'adblue_refill',
    'engine_mounts_check',
  ],
  ReminderKindGroup.cooling: ['coolant', 'radiator_check', 'cooling_hoses'],
  ReminderKindGroup.transmission: [
    'gearbox_oil',
    'transmission_fluid',
    'clutch_fluid',
    'clutch_check',
    'differential_oil',
    'transfer_case_oil',
    'cv_boots_check',
    'drive_chain_lube',
    'drive_chain_kit',
    'drive_belt',
    'cvt_rollers_belt',
    'final_drive_oil',
    'reduction_gear_oil',
  ],
  ReminderKindGroup.brakes: [
    'brake_fluid',
    'brake_pads_front',
    'brake_pads_rear',
    'brake_discs_front',
    'brake_discs_rear',
    'brake_shoes_front',
    'brake_shoes_rear',
    'brake_drums_front',
    'brake_drums_rear',
    'parking_brake_adjust',
    'brake_hoses',
  ],
  ReminderKindGroup.suspension: [
    'shock_absorbers',
    'fork_oil',
    'steering_head_bearings',
    'swingarm_pivot',
    'wheel_bearings',
    'ball_joints_tie_rods',
    'power_steering_fluid',
    'wheel_alignment',
  ],
  ReminderKindGroup.wheels: [
    'tyres_replace',
    'tyres_rotation',
    'tyres_seasonal_swap',
    'tyre_pressure_check',
    'wheel_balancing',
  ],
  ReminderKindGroup.electrical: [
    'battery_12v',
    'battery_check',
    'lights_check',
    'wiper_blades',
    'washer_fluid',
    'ac_gas_recharge',
    'ac_system_disinfect',
    'key_fob_battery',
  ],
  ReminderKindGroup.fuelExhaust: [
    'fuel_lines_check',
    'exhaust_check',
    'evap_system_check',
    'fuel_injector_clean',
  ],
  ReminderKindGroup.gasSystem: [
    'lpg_filter',
    'lpg_injectors_check',
    'lpg_tank_replace',
    'cng_filter',
    'cng_cylinder_inspection',
    'gas_system_inspection',
  ],
  ReminderKindGroup.highVoltage: [
    'hv_battery_check',
    'hv_battery_coolant',
    'charging_port_check',
  ],
  ReminderKindGroup.legal: [
    'inspection',
    'road_tax',
    'insurance',
    'superbollo',
    'other_document',
  ],
  ReminderKindGroup.general: [
    'scheduled_service',
    'inspection_checklist',
    'other',
  ],
};

void main() {
  test('the catalogue is exactly the 85 kinds of step 13a, in order', () {
    expect(ReminderKind.values, hasLength(85));
    expect(
      [for (final kind in ReminderKind.values) kind.code],
      [for (final codes in catalogue.values) ...codes],
    );
    for (final kind in ReminderKind.values) {
      expect(catalogue[kind.group], contains(kind.code), reason: kind.code);
    }
  });

  test('codes round-trip through the converter and fromCode', () {
    const converter = ReminderKindConverter();
    for (final kind in ReminderKind.values) {
      expect(converter.fromSql(converter.toSql(kind)), kind);
      expect(ReminderKind.fromCode(kind.code), kind);
    }
    expect(ReminderKind.fromCode('nope'), isNull);
    expect(() => converter.fromSql('nope'), throwsStateError);
  });

  test('no ARB file repeats a key', () {
    // A repeated key is valid JSON: the last value silently wins, as when
    // the picker's "Other…" replaced the name of the kind "Other".
    for (final language in ['en', 'es', 'it']) {
      final text = File('lib/l10n/app_$language.arb').readAsStringSync();
      final keys = [
        for (final match
            in RegExp(r'^  "([^"]+)":', multiLine: true).allMatches(text))
          match.group(1)!,
      ];
      final seen = <String>{};
      final repeated = [
        for (final key in keys)
          if (!seen.add(key)) key,
      ];
      expect(repeated, isEmpty, reason: 'app_$language.arb');
      // Every top-level key was found, so none hides from the check.
      expect(keys, hasLength((jsonDecode(text) as Map).length));
    }
  });

  group('appliesTo', () {
    bool applies(ReminderKind kind, VehicleKind vehicle, FuelType fuel) =>
        kind.appliesTo(vehicle, fuel);

    test('vehicle kinds: C = car and van, M = motorcycle and moped', () {
      expect(
        applies(ReminderKind.cabinFilter, VehicleKind.van, FuelType.petrol),
        isTrue,
      );
      expect(
        applies(
          ReminderKind.cabinFilter,
          VehicleKind.motorcycle,
          FuelType.petrol,
        ),
        isFalse,
      );
      expect(
        applies(ReminderKind.forkOil, VehicleKind.moped, FuelType.petrol),
        isTrue,
      );
      expect(
        applies(ReminderKind.forkOil, VehicleKind.car, FuelType.petrol),
        isFalse,
      );
    });

    test('fuel filters: "not E", "not D, not E" and positive sets', () {
      expect(
        applies(ReminderKind.engineOil, VehicleKind.car, FuelType.electric),
        isFalse,
      );
      expect(
        applies(ReminderKind.sparkPlugs, VehicleKind.car, FuelType.diesel),
        isFalse,
      );
      expect(
        applies(ReminderKind.sparkPlugs, VehicleKind.car, FuelType.hybrid),
        isTrue,
      );
      expect(
        applies(ReminderKind.glowPlugs, VehicleKind.car, FuelType.diesel),
        isTrue,
      );
      expect(
        applies(ReminderKind.lpgFilter, VehicleKind.car, FuelType.petrolLpg),
        isTrue,
      );
      expect(
        applies(ReminderKind.lpgFilter, VehicleKind.car, FuelType.petrolCng),
        isFalse,
      );
      expect(
        applies(
          ReminderKind.gasSystemInspection,
          VehicleKind.car,
          FuelType.petrolCng,
        ),
        isTrue,
      );
      expect(
        applies(
          ReminderKind.chargingPortCheck,
          VehicleKind.car,
          FuelType.pluginHybrid,
        ),
        isTrue,
      );
      expect(
        applies(
          ReminderKind.chargingPortCheck,
          VehicleKind.car,
          FuelType.hybrid,
        ),
        isFalse,
      );
      expect(
        applies(
          ReminderKind.reductionGearOil,
          VehicleKind.car,
          FuelType.hybrid,
        ),
        isTrue,
      );
    });

    test('"other" fuel passes every "not" filter and no positive set', () {
      expect(
        applies(ReminderKind.sparkPlugs, VehicleKind.car, FuelType.other),
        isTrue,
      );
      for (final kind in [
        ReminderKind.glowPlugs,
        ReminderKind.dpfCheck,
        ReminderKind.adblueRefill,
        ReminderKind.lpgFilter,
        ReminderKind.cngFilter,
        ReminderKind.hvBatteryCheck,
      ]) {
        expect(applies(kind, VehicleKind.car, FuelType.other), isFalse);
      }
    });

    test('every legal and general kind applies to every car', () {
      for (final kind in ReminderKind.values) {
        if (kind.group == ReminderKindGroup.legal ||
            kind.group == ReminderKindGroup.general) {
          expect(
            applies(kind, VehicleKind.car, FuelType.electric),
            isTrue,
            reason: kind.code,
          );
        }
      }
    });
  });

  test('closing entry types and the mark-done type follow the group', () {
    for (final kind in ReminderKind.values) {
      if (kind.isLegal) {
        expect(
          kind.closingEntryTypes,
          {LogEntryType.legalDue, LogEntryType.expense},
        );
        expect(kind.markDoneEntryType, LogEntryType.legalDue);
      } else {
        expect(
          kind.closingEntryTypes,
          {LogEntryType.maintenance, LogEntryType.repair},
        );
        expect(kind.markDoneEntryType, LogEntryType.maintenance);
      }
    }
  });

  test('only "other" and "other_document" may repeat on a vehicle', () {
    expect(
      [
        for (final kind in ReminderKind.values)
          if (!kind.uniquePerVehicle) kind,
      ],
      [ReminderKind.otherDocument, ReminderKind.other],
    );
  });
}
