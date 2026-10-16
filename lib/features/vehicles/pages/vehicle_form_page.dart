import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/router/navigation.dart';
import '../../../data/catalog/vehicle_catalog.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/fuel_type.dart';
import '../../../data/models/vehicle.dart';
import '../../../data/models/vehicle_kind.dart';
import '../../../data/repositories/vehicle_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../../shared/widgets/picker_form_field.dart';
import '../../../shared/widgets/searchable_picker.dart';
import '../../../shared/widgets/text_input_dialog.dart';
import '../../../shared/widgets/vehicle_kind_icon.dart';
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
  late final _year =
      TextEditingController(text: widget.initial?.modelYear?.toString());
  late final _version = TextEditingController(text: widget.initial?.version);
  late final _nickname = TextEditingController(text: widget.initial?.nickname);
  final _km = TextEditingController();
  late final _oil =
      TextEditingController(text: widget.initial?.recommendedEngineOil);
  late final _notes =
      TextEditingController(text: widget.initial?.manufacturerNotes);

  /// Model typed by hand, used while the make is not from the catalogue.
  late final _customModel = TextEditingController(
    text: widget.initial?.makeSlug == null ? widget.initial?.model : null,
  );

  late VehicleIdentity _identity = VehicleIdentity.of(widget.initial);
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
    for (final controller in [
      _plate,
      _year,
      _version,
      _nickname,
      _km,
      _oil,
      _notes,
      _customModel,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Applies a new identity; the typed model follows it when it is cleared.
  void _setIdentity(VehicleIdentity identity) {
    setState(() {
      _identity = identity;
      if (identity.model == null) _customModel.clear();
    });
  }

  /// The catalogue, or an empty one if it cannot be loaded: the list helps,
  /// it never blocks, so a missing catalogue still allows typing by hand.
  Future<VehicleCatalog> _catalog() async {
    try {
      return await ref.read(vehicleCatalogProvider.future);
    } on Exception {
      return VehicleCatalog(release: '', makesByKind: const {});
    }
  }

  /// Opens the make picker for the current kind.
  Future<void> _pickMake() async {
    final l10n = AppLocalizations.of(context);
    final catalog = await _catalog();
    if (!mounted) return;
    final kind = _identity.kind;
    final featured = catalog.featuredCount(kind);
    final result = await showSearchablePicker<CatalogMake>(
      context: context,
      title: l10n.makePickerTitle,
      search: (query) => catalog.searchMakes(kind, query),
      labelOf: (make) => make.name,
      otherLabel: l10n.otherMake,
      headers: {
        if (featured > 0) 0: l10n.pickerPopularMakes,
        if (featured > 0 && featured < catalog.makes(kind).length)
          featured: l10n.pickerAllMakes,
      },
    );
    if (!mounted || result == null) return;
    switch (result) {
      case Picked(:final value):
        _setIdentity(_identity.withCatalogMake(value));
      case PickedOther(:final query):
        final typed = await showTextInputDialog(
          context,
          title: l10n.fieldMake,
          initialText: query.isNotEmpty
              ? query
              : (_identity.hasCatalogMake ? '' : _identity.make ?? ''),
        );
        if (!mounted || typed == null) return;
        _setIdentity(_identity.withCustomMake(typed));
    }
  }

  /// Opens the model picker for the current catalogue make.
  Future<void> _pickModel() async {
    final l10n = AppLocalizations.of(context);
    final makeSlug = _identity.makeSlug;
    if (makeSlug == null) return;
    final catalog = await _catalog();
    if (!mounted) return;
    final kind = _identity.kind;
    final result = await showSearchablePicker<CatalogModel>(
      context: context,
      title: l10n.modelPickerTitle,
      search: (query) => catalog.searchModels(kind, makeSlug, query),
      labelOf: (model) => model.name,
      otherLabel: l10n.otherModel,
    );
    if (!mounted || result == null) return;
    switch (result) {
      case Picked(:final value):
        _setIdentity(_identity.withCatalogModel(value));
      case PickedOther(:final query):
        final typed = await showTextInputDialog(
          context,
          title: l10n.fieldModel,
          initialText: query.isNotEmpty
              ? query
              : (_identity.modelSlug == null ? _identity.model ?? '' : ''),
          textCapitalization: TextCapitalization.sentences,
        );
        if (!mounted || typed == null) return;
        _setIdentity(_identity.withCustomModel(typed));
    }
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
            identity: _identity,
            modelYear: int.tryParse(_year.text.trim()),
            version: _version.text,
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

  /// Checks the optional model year: from the first car to next year.
  String? _validateYear(String? value, AppLocalizations l10n) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final maxYear = DateTime.now().year + 1;
    final year = int.tryParse(text);
    if (year == null || year < minModelYear || year > maxYear) {
      return l10n.validationModelYearInvalid(minModelYear, maxYear);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final owners = ref.watch(ownerListProvider);
    // Starts loading the catalogue while the user looks at the form.
    ref.watch(vehicleCatalogProvider);
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
          // A Column, not a lazy ListView: Form.validate only checks fields
          // that are built, and this form is longer than a phone screen.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _KindChoice(
                  selected: _identity.kind,
                  onChanged: (kind) => _setIdentity(_identity.withKind(kind)),
                ),
                gap,
                PickerFormField(
                  key: const ValueKey('make-field'),
                  label: l10n.fieldMake,
                  value: _identity.make,
                  onTap: _pickMake,
                  validator: (value) =>
                      value == null ? l10n.validationMakeRequired : null,
                ),
                gap,
                if (_identity.make != null && !_identity.hasCatalogMake)
                  TextFormField(
                    key: const ValueKey('custom-model-field'),
                    controller: _customModel,
                    decoration: _decoration(l10n.fieldModel),
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    onChanged: (text) =>
                        _identity = _identity.withCustomModel(text),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? l10n.validationModelRequired
                        : null,
                  )
                else
                  PickerFormField(
                    key: const ValueKey('model-field'),
                    label: l10n.fieldModel,
                    value: _identity.model,
                    hint: _identity.make == null ? l10n.chooseMakeFirst : null,
                    enabled: _identity.hasCatalogMake,
                    onTap: _pickModel,
                    validator: (value) =>
                        value == null ? l10n.validationModelRequired : null,
                  ),
                gap,
                TextFormField(
                  controller: _year,
                  decoration: _decoration(l10n.fieldModelYear),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  textInputAction: TextInputAction.next,
                  validator: (value) => _validateYear(value, l10n),
                ),
                gap,
                TextFormField(
                  controller: _version,
                  decoration: _decoration(l10n.fieldVersion).copyWith(
                    hintText: l10n.fieldVersionHint,
                  ),
                  textInputAction: TextInputAction.next,
                ),
                gap,
                TextFormField(
                  controller: _plate,
                  decoration: _decoration(l10n.fieldPlate),
                  forceErrorText: _plateError,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_plateError != null) setState(() => _plateError = null);
                  },
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? l10n.validationPlateRequired
                      : null,
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
                gap,
                TextFormField(
                  controller: _nickname,
                  decoration: _decoration(l10n.fieldNickname),
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Outlined decoration with [label], shared by every field.
  InputDecoration _decoration(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder());
}

/// The vehicle kind choice: one segment per kind, icon above label.
class _KindChoice extends StatelessWidget {
  const _KindChoice({required this.selected, required this.onChanged});

  final VehicleKind selected;
  final ValueChanged<VehicleKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.fieldKind,
      container: true,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<VehicleKind>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
          ),
          segments: [
            for (final kind in VehicleKind.values)
              ButtonSegment(
                value: kind,
                tooltip: kind.label(l10n),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(kind.icon),
                    const SizedBox(height: 4),
                    // Scaled down rather than cut, so the longest labels
                    // ("Ciclomotore") stay whole on narrow phones and with
                    // large text.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(kind.label(l10n), maxLines: 1),
                    ),
                  ],
                ),
              ),
          ],
          selected: {selected},
          onSelectionChanged: (selection) => onChanged(selection.single),
        ),
      ),
    );
  }
}
