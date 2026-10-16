import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/router/navigation.dart';
import '../../../data/models/fuel_type.dart';
import '../../../data/models/vehicle.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../owners/controllers/owner_list_controller.dart';
import '../controllers/vehicle_form_controller.dart';
import '../widgets/owner_picker_field.dart';

/// Form that creates a vehicle (no [vehicleId]) or edits one.
///
/// The current km is asked only when creating: afterwards it changes only
/// through the odometer feature.
class VehicleFormPage extends ConsumerWidget {
  /// Creates the form; [vehicleId] is `null` to create a new vehicle.
  const VehicleFormPage({super.key, this.vehicleId});

  /// Id of the vehicle to edit, from the path; `null` when creating.
  final String? vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final title =
        vehicleId == null ? l10n.newVehicleTitle : l10n.editVehicleTitle;
    final initial = ref.watch(vehicleFormControllerProvider(vehicleId));
    return initial.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: MessageView(icon: Icons.error_outline, message: l10n.loadError),
      ),
      data: (vehicle) => vehicleId != null && vehicle == null
          ? NotFoundPage(message: l10n.vehicleNotFound)
          : _VehicleForm(vehicleId: vehicleId, initial: vehicle, title: title),
    );
  }
}

/// The vehicle form itself, holding the values being typed.
class _VehicleForm extends ConsumerStatefulWidget {
  const _VehicleForm({
    required this.vehicleId,
    required this.initial,
    required this.title,
  });

  final String? vehicleId;
  final Vehicle? initial;
  final String title;

  @override
  ConsumerState<_VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends ConsumerState<_VehicleForm> {
  final _formKey = GlobalKey<FormState>();
  late final _plate = TextEditingController(text: widget.initial?.plate);
  late final _nickname = TextEditingController(text: widget.initial?.nickname);
  final _km = TextEditingController();
  late final _oil =
      TextEditingController(text: widget.initial?.recommendedEngineOil);
  late final _notes =
      TextEditingController(text: widget.initial?.manufacturerNotes);
  late String? _ownerId = widget.initial?.ownerId;
  late FuelType? _fuelType = widget.initial?.fuelType;

  /// Error shown on the plate field after the repository refused the plate
  /// as a duplicate. Cleared as soon as the plate is edited.
  String? _plateError;

  /// Bumped to rebuild the owner picker from scratch, e.g. to drop the
  /// "New owner" entry it shows after the owner form was cancelled.
  int _ownerPickerGeneration = 0;

  /// Whether a save is running; the save button is disabled meanwhile.
  bool _saving = false;

  bool get _creating => widget.vehicleId == null;

  @override
  void dispose() {
    for (final controller in [_plate, _nickname, _km, _oil, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Opens the owner form and selects the owner it creates.
  Future<void> _createOwner() async {
    final ownerId = await context.push<String>(AppRoutes.newOwner);
    if (!mounted) return;
    setState(() {
      if (ownerId != null) _ownerId = ownerId;
      _ownerPickerGeneration++;
    });
  }

  /// Validates the fields and saves through the controller.
  Future<void> _save() async {
    setState(() => _plateError = null);
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final result = await ref
        .read(vehicleFormControllerProvider(widget.vehicleId).notifier)
        .save(
          VehicleDraft(
            plate: _plate.text,
            nickname: _nickname.text,
            ownerId: _ownerId!,
            fuelType: _fuelType!,
            currentOdometerKm: _creating ? int.parse(_km.text) : null,
            recommendedEngineOil: _oil.text,
            manufacturerNotes: _notes.text,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case ActionSuccess(:final value):
        showSavedSnackBar(messenger, l10n.vehicleSaved);
        context.popOrGo(AppRoutes.vehicle(value.id), value.id);
      case ActionFailure(error: ActionError.duplicatePlate):
        setState(() => _plateError = l10n.errorDuplicatePlate);
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  /// Checks the current km: required, a whole number, never negative.
  String? _validateKm(String? value, AppLocalizations l10n) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return l10n.validationKmRequired;
    final km = int.tryParse(text);
    if (km == null || km < 0) return l10n.validationKmInvalid;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final owners = ref.watch(ownerListProvider);
    const gap = SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _saving || !owners.hasValue ? null : _save,
            child: Text(l10n.actionSave),
          ),
        ],
      ),
      body: AsyncValueView(
        value: owners,
        data: (owners) => Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _plate,
                decoration: _decoration(l10n.fieldPlate),
                forceErrorText: _plateError,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                autofocus: _creating,
                onChanged: (_) {
                  if (_plateError != null) setState(() => _plateError = null);
                },
                validator: (value) => (value ?? '').trim().isEmpty
                    ? l10n.validationPlateRequired
                    : null,
              ),
              gap,
              TextFormField(
                controller: _nickname,
                decoration: _decoration(l10n.fieldNickname),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
              ),
              gap,
              OwnerPickerField(
                key: ValueKey('owner-picker-$_ownerPickerGeneration'),
                owners: owners,
                selectedOwnerId: _ownerId,
                onSelected: (id) => setState(() => _ownerId = id),
                onNewOwner: _createOwner,
              ),
              gap,
              DropdownButtonFormField<FuelType>(
                initialValue: _fuelType,
                isExpanded: true,
                decoration: _decoration(l10n.fieldFuelType),
                items: [
                  for (final fuelType in FuelType.values)
                    DropdownMenuItem(
                      value: fuelType,
                      child: Text(
                        fuelType.label(l10n),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _fuelType = value),
                validator: (value) =>
                    value == null ? l10n.validationFuelTypeRequired : null,
              ),
              if (_creating) ...[
                gap,
                TextFormField(
                  controller: _km,
                  decoration: _decoration(l10n.fieldCurrentKm),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  validator: (value) => _validateKm(value, l10n),
                ),
              ],
              gap,
              TextFormField(
                controller: _oil,
                decoration: _decoration(l10n.fieldRecommendedOil),
                textInputAction: TextInputAction.next,
              ),
              gap,
              TextFormField(
                controller: _notes,
                decoration: _decoration(l10n.fieldManufacturerNotes),
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Outlined decoration with [label], shared by every field.
  InputDecoration _decoration(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder());
}
