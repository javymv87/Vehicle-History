import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/units.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/section_header.dart';
import '../controllers/settings_controller.dart';
import 'choice_dialog.dart';

/// The "Units" section of the Settings page (`Docs/06_settings_and_i18n.md`,
/// "Unidades"): the preset buttons International · Imperial · Custom, then
/// one tile per quantity with the unit in use and its symbol, each opening
/// the radio dialog of the language and theme tiles.
///
/// The preset is never stored: it is derived from the five units every
/// build. Tapping International or Imperial writes all five; Custom only
/// shows that the five match neither: it is selectable-looking only while
/// active, and tapping it changes nothing. Changing one
/// unit writes that key alone. A consumption unit counting with another
/// volume than the chosen one gets a hint under its tile, nothing more.
class UnitsSection extends ConsumerWidget {
  /// Creates the section.
  const UnitsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Not read yet, or unreadable: both count as the SI defaults.
    final preferences =
        ref.watch(unitPreferencesProvider).value ?? UnitPreferences.defaults;
    final controller = ref.read(settingsControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    /// Shows the error of a failed write; a success needs no message.
    Future<void> run(Future<ActionResult<void>> action) async {
      if (await action case ActionFailure(:final error)) {
        showErrorSnackBar(messenger, error.message(l10n));
      }
    }

    /// Opens the dialog of one quantity and writes the chosen unit.
    Future<void> choose<T extends UnitConversion>({
      required String title,
      required List<T> options,
      required T current,
      required Future<ActionResult<void>> Function(T unit) write,
    }) async {
      final chosen = await showChoiceDialog<T>(
        context: context,
        title: title,
        options: options,
        selected: current,
        labelOf: (unit) => unit.label(l10n),
      );
      if (chosen == null || chosen == current) return;
      await run(write(chosen));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.settingsUnits),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SegmentedButton<UnitPreset>(
            key: const ValueKey('unit-preset'),
            segments: [
              for (final preset in UnitPreset.values)
                ButtonSegment(
                  value: preset,
                  label: Text(preset.label(l10n)),
                  // Custom is a state, not a choice: enabled only while it
                  // is the active one, so it shows as selected (a disabled
                  // segment is painted grey even when selected); greyed
                  // out while a preset is active.
                  enabled: preset != UnitPreset.custom ||
                      preferences.preset == UnitPreset.custom,
                ),
            ],
            selected: {preferences.preset},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              // Tapping the selected Custom segment changes nothing.
              if (selection.single == UnitPreset.custom) return;
              run(controller.setUnitPreset(selection.single));
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.straighten),
          title: Text(l10n.settingsUnitDistance),
          subtitle: Text(preferences.distance.label(l10n)),
          onTap: () => choose(
            title: l10n.settingsUnitDistance,
            options: DistanceUnit.values,
            current: preferences.distance,
            write: controller.setDistanceUnit,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.local_gas_station_outlined),
          title: Text(l10n.settingsUnitVolume),
          subtitle: Text(preferences.volume.label(l10n)),
          onTap: () => choose(
            title: l10n.settingsUnitVolume,
            options: VolumeUnit.values,
            current: preferences.volume,
            write: controller.setVolumeUnit,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.thermostat_outlined),
          title: Text(l10n.settingsUnitTemperature),
          subtitle: Text(preferences.temperature.label(l10n)),
          onTap: () => choose(
            title: l10n.settingsUnitTemperature,
            options: TemperatureUnit.values,
            current: preferences.temperature,
            write: controller.setTemperatureUnit,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.speed_outlined),
          title: Text(l10n.settingsUnitPressure),
          subtitle: Text(preferences.pressure.label(l10n)),
          onTap: () => choose(
            title: l10n.settingsUnitPressure,
            options: PressureUnit.values,
            current: preferences.pressure,
            write: controller.setPressureUnit,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.water_drop_outlined),
          title: Text(l10n.settingsUnitConsumption),
          subtitle: Text(preferences.consumption.label(l10n)),
          onTap: () => choose(
            title: l10n.settingsUnitConsumption,
            options: ConsumptionUnit.values,
            current: preferences.consumption,
            write: controller.setConsumptionUnit,
          ),
        ),
        if (preferences.volumeConsumptionMismatch)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
            child: Text(
              l10n.unitConsumptionMismatchHint,
              key: const ValueKey('unit-consumption-hint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
