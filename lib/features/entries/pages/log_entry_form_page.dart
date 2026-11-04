import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/router/navigation.dart';
import '../../../data/models/calendar_date.dart';
import '../../../data/models/log_entry.dart';
import '../../../data/models/log_entry_type.dart';
import '../../../data/models/reminder.dart';
import '../../../data/models/mileage_reading.dart';
import '../../../data/models/odometer_checks.dart';
import '../../../data/models/refuel.dart';
import '../../../data/repositories/reminder_closer.dart';
import '../../../data/repositories/repository_exceptions.dart';
import '../../../data/models/vehicle.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/utils/money.dart';
import '../../../shared/utils/unit_formatter.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../reminders/controllers/reminder_list_controller.dart';
import '../../reminders/widgets/reminder_texts.dart';
import '../../mileage/controllers/odometer_update_offer_controller.dart';
import '../../mileage/widgets/odometer_update_offer.dart';
import '../../reports/widgets/segment_texts.dart';
import '../../settings/controllers/settings_controller.dart';
import '../controllers/log_entry_attachments_controller.dart';
import '../controllers/log_entry_form_controller.dart';
import '../controllers/refuel_triangle.dart';
import '../widgets/log_entry_attachments_field.dart';
import '../widgets/log_entry_type_icon.dart';

/// Form that creates a history entry for a vehicle (no [entryId]) or edits
/// one (`Docs/03_features.md`, U3–U5, U10, U22, E1–E3 and the refuel form).
///
/// Built for few taps: type, date (today by default), km with a one-tap
/// "use current km" chip, cost and description, with Save always in the app
/// bar. A refuel of a vehicle that is not electric adds its fields: the
/// fuel (bi-fuel vehicles only), the volume, the price per unit and the
/// amount, linked by [RefuelTriangle], then the full-tank switch and the
/// missed-refuel checkbox.
class LogEntryFormPage extends ConsumerWidget {
  /// Creates the form for the vehicle with [vehicleId]; [entryId] is `null`
  /// to create a new entry.
  const LogEntryFormPage({super.key, required this.vehicleId, this.entryId});

  /// Id of the vehicle, from the path.
  final String vehicleId;

  /// Id of the entry to edit, from the path; `null` when creating.
  final String? entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final title = entryId == null ? l10n.newEntryTitle : l10n.editEntryTitle;
    final key = (vehicleId: vehicleId, entryId: entryId);
    final initial = ref.watch(logEntryFormControllerProvider(key));
    return initial.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EmptyState(icon: Icons.error_outline, message: l10n.loadError),
      ),
      data: (data) {
        final vehicle = data.vehicle;
        if (vehicle == null) {
          return NotFoundPage(message: l10n.vehicleNotFound);
        }
        // An archived vehicle is read-only (reachable only by deep link).
        if (vehicle.isArchived) {
          return NotFoundPage(message: l10n.errorVehicleArchived);
        }
        if (entryId != null && data.entry == null) {
          return NotFoundPage(message: l10n.entryNotFound);
        }
        return _LogEntryForm(
          formKey: key,
          vehicle: vehicle,
          readings: data.readings,
          initial: data.entry,
          title: title,
        );
      },
    );
  }
}

/// The entry form itself, holding the values being typed.
class _LogEntryForm extends ConsumerStatefulWidget {
  const _LogEntryForm({
    required this.formKey,
    required this.vehicle,
    required this.readings,
    required this.initial,
    required this.title,
  });

  final LogEntryFormKey formKey;
  final Vehicle vehicle;
  final List<MileageReading> readings;
  final LogEntry? initial;
  final String title;

  @override
  ConsumerState<_LogEntryForm> createState() => _LogEntryFormState();
}

class _LogEntryFormState extends ConsumerState<_LogEntryForm> {
  final _formKey = GlobalKey<FormState>();
  late final _description =
      TextEditingController(text: widget.initial?.description);

  /// Filled in [didChangeDependencies], where the locale and the units are
  /// known.
  final _km = TextEditingController();
  final _cost = TextEditingController();
  final _volume = TextEditingController();
  final _price = TextEditingController();
  bool _storedValuesFilled = false;

  /// The amount / volume / price of a refuel, in SI: what the three fields
  /// hold, and which of them is computed after an edit.
  late final RefuelTriangle _triangle = RefuelTriangle(
    amountCents: widget.initial?.costCents,
    volume: widget.initial?.refuel?.volume,
  );

  /// The fuel of a refuel: the entry's, or the vehicle's primary one (petrol
  /// on a bi-fuel vehicle); `null` for an electric vehicle.
  late RefuelFuel? _fuel =
      widget.initial?.refuel?.fuel ?? widget.vehicle.fuelType.primaryRefuelFuel;

  /// Whether the refuel filled the tank: on for a new refuel.
  late bool _fullTank = widget.initial?.refuel?.fullTank ?? true;

  /// Whether a refuel before this one was not recorded: off by default.
  late bool _missedPrevious = widget.initial?.refuel?.missedPrevious ?? false;

  /// The formatter of the last build, for the validators and the save.
  late UnitFormatter _units;

  late LogEntryType? _type = widget.initial?.type;

  /// The day of the event: today when creating (U3), never prefilled with
  /// anything else.
  late CalendarDate _date =
      widget.initial?.date ?? calendarDateOf(DateTime.now());

  /// Shown under the date when the type does not allow a future day (E1).
  String? _dateError;

  /// Whether a save is running; the save button is disabled meanwhile.
  bool _saving = false;

  /// The reminder chosen in "Closes the reminder"; `null` for none.
  String? _closesReminderId;

  /// The reminders the field offers, from the last build.
  List<ReminderView> _closable = const [];

  /// Why the chosen reminder refuses this entry, under the field.
  String? _closeError;

  /// The entry types that can close a reminder.
  static const Set<LogEntryType> _closingTypes = {
    LogEntryType.maintenance,
    LogEntryType.repair,
    LogEntryType.legalDue,
    LogEntryType.expense,
  };

  /// The reminder chosen in the field, if it is still offered (a change of
  /// type may leave it out).
  ReminderView? get _closing {
    for (final view in _closable) {
      if (view.reminder.id == _closesReminderId) return view;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The stored cents become text with the separator of the app language,
    // and the stored km text in the unit of the moment.
    final cents = widget.initial?.costCents;
    final km = widget.initial?.km;
    if (!_storedValuesFilled) {
      if (cents != null) {
        _cost.text =
            euroCentsInputText(cents, AppLocalizations.of(context).localeName);
      }
      if (km != null) {
        _km.text = readUnitFormatter(context, ref).distance.inputText(km);
      }
      // An edited refuel: its volume, and the price computed from it.
      _units = readUnitFormatter(context, ref);
      _showTriangleValue(TriangleField.volume);
      _showTriangleValue(TriangleField.price);
    }
    _storedValuesFilled = true;
  }

  @override
  void dispose() {
    _km.dispose();
    _description.dispose();
    _cost.dispose();
    _volume.dispose();
    _price.dispose();
    super.dispose();
  }

  /// Whether the refuel fields are shown: a refuel of a vehicle that is not
  /// electric.
  bool get _showsRefuelFields => _type == LogEntryType.refuel && _fuel != null;

  /// The formatter of the refuel's quantity: litres (or gallons), or kg for
  /// CNG.
  QuantityFormatter get _quantity => _units.fuelQuantity(_fuel!);

  /// The typed volume in SI, or `null` when blank or malformed; the
  /// triangle's own value when the text is exactly how it shows.
  double? _parseVolume(String text) => text.trim().isEmpty || _fuel == null
      ? null
      : _quantity.parse(text, sameAs: _triangle.volume);

  /// Feeds an edit of [field] to the triangle and shows the value it
  /// computed, if any. Called for the user's own typing only (`onChanged`),
  /// so a computed value never triggers another computation.
  void _editTriangle(TriangleField field, num? value) {
    final computed = _triangle.edit(field, value);
    if (computed != null) _showTriangleValue(computed);
  }

  /// Writes the triangle's value of [field] into its text field, in the
  /// unit and the locale of the moment.
  void _showTriangleValue(TriangleField field) {
    final locale = AppLocalizations.of(context).localeName;
    switch (field) {
      case TriangleField.amount:
        final cents = _triangle.amountCents;
        _cost.text = cents == null ? '' : euroCentsInputText(cents, locale);
      case TriangleField.volume:
        final volume = _triangle.volume;
        _volume.text =
            volume == null || _fuel == null ? '' : _quantity.inputText(volume);
      case TriangleField.price:
        final price = _triangle.price;
        final fuel = _fuel;
        _price.text = price == null || fuel == null
            ? ''
            : unitPriceInputText(
                _units.unitPriceToDisplay(fuel, price),
                locale,
              );
    }
  }

  /// Switches the fuel of a bi-fuel refuel and shows its volume and price
  /// again in the units of the new fuel (litres or kg).
  void _selectFuel(RefuelFuel fuel) {
    setState(() => _fuel = fuel);
    _showTriangleValue(TriangleField.volume);
    _showTriangleValue(TriangleField.price);
  }

  /// The types offered: the selectable ones, plus the entry's own type when
  /// editing one the form no longer offers.
  List<LogEntryType> get _offeredTypes {
    final type = widget.initial?.type;
    return [
      ...LogEntryType.selectable,
      if (type != null && !LogEntryType.selectable.contains(type)) type,
    ];
  }

  /// Whether the km is required for the selected type. Without a type yet,
  /// the field is shown as optional; validation catches the type first.
  bool get _kmRequired => _type?.requiresKm ?? false;

  /// Copies the vehicle's current odometer into the km field (U4), in the
  /// unit of the moment.
  void _useCurrentKm() {
    setState(
      () => _km.text =
          _units.distance.inputText(widget.vehicle.currentOdometerKm),
    );
  }

  /// The typed reading in km, or the current odometer itself when the text
  /// is exactly how it shows (the chip), so rounding never changes it.
  double? _parseKm(String text) =>
      _units.distance.parse(text, sameAs: widget.vehicle.currentOdometerKm);

  /// Opens the Material date picker on the selected day.
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.toLocalDateTime(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = calendarDateOf(picked);
        _dateError = null;
      });
    }
  }

  /// Today's calendar day on the phone.
  CalendarDate get _today => calendarDateOf(DateTime.now());

  /// The date error, or `null`: only legal deadlines, expenses and notes
  /// may be dated after today (E1).
  String? _validateDate(AppLocalizations l10n) {
    final type = _type;
    if (type == null || type.allowsFutureDate || !_date.isAfter(_today)) {
      return null;
    }
    return l10n.validationEntryDateFuture;
  }

  /// Checks the reading: a whole number ≥ 0 in the chosen unit, required
  /// for some types (U10).
  String? _validateKm(String? value, AppLocalizations l10n) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return _kmRequired ? l10n.validationEntryKmRequired : null;
    }
    final km = _parseKm(text);
    if (km == null || km < 0) return l10n.validationKmInvalid;
    return null;
  }

  /// Checks the optional volume of a refuel: a number ≥ 0 in its unit.
  String? _validateVolume(String? value, AppLocalizations l10n) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final volume = _parseVolume(text);
    return volume == null || volume < 0 ? l10n.validationVolumeInvalid : null;
  }

  /// Checks the optional price per unit: ≥ 0 with at most three decimals.
  String? _validatePrice(String? value, AppLocalizations l10n) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    return tryParseUnitPrice(text) == null ? l10n.validationPriceInvalid : null;
  }

  /// Asks before saving a refuel whose price or quantity looks unusual
  /// (`RefuelChecks`); `true` to save. Never refuses.
  Future<bool> _confirmUnusualRefuel(
    AppLocalizations l10n, {
    required double? volume,
    required int? costCents,
  }) async {
    final fuel = _fuel;
    if (!_showsRefuelFields || fuel == null) return true;
    final price = costCents != null && volume != null && volume > 0
        ? costCents / 100 / volume
        : _triangle.price;
    final warnings = RefuelChecks.warningsFor(quantity: volume, price: price);
    if (warnings.isEmpty) return true;
    final lines = [
      for (final warning in warnings)
        switch (warning) {
          RefuelWarning.unusualPrice =>
            l10n.refuelCheckPrice(_units.formatUnitPrice(fuel, price!)),
          RefuelWarning.largeQuantity =>
            l10n.refuelCheckVolume(_quantity.format(volume!)),
        },
    ];
    return confirmAction(
      context,
      title: l10n.refuelCheckTitle,
      message: lines.join('\n'),
      confirmLabel: l10n.actionSaveAnyway,
    );
  }

  /// Checks the optional cost: ≥ 0 with at most two decimals (U5, U10).
  String? _validateCost(String? value, AppLocalizations l10n) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    return tryParseEuroCents(text) == null ? l10n.validationCostInvalid : null;
  }

  /// Validates the fields, asks about a suspicious km (E2) and saves
  /// through the controller; then offers to update the odometer (E3).
  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final dateError = _validateDate(l10n);
    setState(() => _dateError = dateError);
    final fieldsValid = _formKey.currentState!.validate();
    if (!fieldsValid || dateError != null) return;
    final kmText = _km.text.trim();
    final costText = _cost.text.trim();
    final km = kmText.isEmpty ? null : _parseKm(kmText);
    final currentKm = widget.vehicle.currentOdometerKm;
    final lastReadingDate = widget.readings.firstOrNull?.date;

    // E2: more km than a reading taken on a later day is almost surely a
    // typo, since the odometer never goes backwards. Ask, never block.
    final conflicting = laterReadingBelowEntryKm(
      entryKm: km,
      entryDate: _date,
      readings: widget.readings,
    );
    if (conflicting != null) {
      final confirmed = await confirmAction(
        context,
        title: l10n.entryKmAboveOdometerTitle,
        message: l10n.entryKmAboveOdometerMessage(
          _units.distance.format(conflicting.km),
          conflicting.date.toLocalDateTime(),
        ),
        confirmLabel: l10n.actionSaveAnyway,
      );
      if (!confirmed || !mounted) return;
    }
    // The rules of the close, checked first so their message lands under
    // the reminder field and nothing is saved.
    final closing = _closing;
    if (closing != null) {
      try {
        ReminderCloser.checkEntry(
          closing.reminder,
          vehicleId: widget.vehicle.id,
          type: _type!,
          date: _date,
          km: km,
          today: _today,
        );
      } on RepositoryException catch (error) {
        setState(
          () => _closeError =
              closingErrorText(error, closing.reminder, l10n, _units),
        );
        return;
      }
    }
    final volume = _showsRefuelFields ? _parseVolume(_volume.text) : null;
    final costCents = costText.isEmpty ? null : tryParseEuroCents(costText);
    if (!await _confirmUnusualRefuel(
          l10n,
          volume: volume,
          costCents: costCents,
        ) ||
        !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    // Captured now: the offer's "Update" runs after this form is gone.
    final router = GoRouter.of(context);
    final units = _units;
    final offer = ref.read(odometerUpdateOfferControllerProvider.notifier);
    final attachments =
        ref.read(logEntryAttachmentsControllerProvider(widget.formKey));
    final form =
        ref.read(logEntryFormControllerProvider(widget.formKey).notifier);
    setState(() => _saving = true);
    final result = await form.save(
      LogEntryDraft(
        date: _date,
        type: _type!,
        km: km,
        description: _description.text,
        costCents: costCents,
        refuel: _showsRefuelFields
            ? RefuelDetails(
                fuel: _fuel!,
                volume: volume,
                fullTank: _fullTank,
                missedPrevious: _missedPrevious,
              )
            : null,
        addedAttachments: attachments.staged,
        removedAttachmentIds: attachments.removedIds,
        closesReminderId: closing?.reminder.id,
      ),
    );
    if (!mounted) return;
    // What a refuel means for the consumption, said in the same snackbar.
    final role = result is ActionSuccess<LogEntry>
        ? await form.refuelRoleOf(result.value)
        : null;
    if (!mounted) return;
    setState(() => _saving = false);
    final refuelSummary =
        role == null ? null : refuelRoleText(role, l10n, units, quiet: true);
    switch (result) {
      case ActionSuccess(:final value):
        final entryKm = value.km;
        if (entryKm != null &&
            shouldOfferOdometerUpdate(
              entryKm: entryKm,
              entryDate: value.date,
              currentOdometerKm: currentKm,
              lastReadingDate: lastReadingDate,
              today: _today,
            )) {
          showOdometerUpdateOffer(
            messenger: messenger,
            router: router,
            l10n: l10n,
            units: units,
            offer: offer,
            vehicleId: value.vehicleId,
            date: value.date,
            km: entryKm,
            currentKm: currentKm,
            refuelSummary: refuelSummary,
          );
        } else if (refuelSummary != null) {
          showOfferSnackBar(
            messenger,
            l10n.refuelSavedWithSummary(refuelSummary),
            actionLabel: l10n.actionView,
            onAction: () =>
                router.push(AppRoutes.entry(value.vehicleId, value.id)),
          );
        } else {
          showSavedSnackBar(messenger, l10n.entrySaved);
        }
        context.popOrGo(AppRoutes.vehicle(value.vehicleId), value.id);
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    _units = unitFormatterOf(context, ref);
    final currency =
        NumberFormat.simpleCurrency(locale: l10n.localeName, name: 'EUR');
    const gap = SizedBox(height: 16);
    final type = _type;
    final editedId = widget.initial?.id;
    // An edited entry that already closed a reminder shows it, read-only:
    // the anchor is changed from the reminder, there is no unlinking.
    final closed = editedId == null
        ? const <Reminder>[]
        : ref.watch(entryClosedRemindersProvider(editedId)).value ??
            const <Reminder>[];
    _closable = type != null && _closingTypes.contains(type) && closed.isEmpty
        ? ref
                .watch(
                  closableRemindersProvider(
                    (vehicleId: widget.vehicle.id, type: type),
                  ),
                )
                .value ??
            const []
        : const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            // Not while files are still being copied into the form.
            onPressed: _saving ||
                    ref
                        .watch(
                          logEntryAttachmentsControllerProvider(widget.formKey),
                        )
                        .busy
                ? null
                : _save,
            child: Text(l10n.actionSave),
          ),
        ],
        // Saving moves the picked files into place, which can take a moment.
        bottom: _saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: Form(
        key: _formKey,
        // A Column, not a lazy ListView: Form.validate only checks fields
        // that are built.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TypeChoice(
                types: _offeredTypes,
                selected: _type,
                onChanged: (type) => setState(() {
                  _type = type;
                  _dateError = null;
                  _closeError = null;
                }),
              ),
              gap,
              _DateField(date: _date, error: _dateError, onTap: _pickDate),
              gap,
              TextFormField(
                key: const ValueKey('entry-km-field'),
                controller: _km,
                decoration: InputDecoration(
                  labelText: _kmRequired
                      ? l10n.fieldEntryKm
                      : l10n.fieldEntryKmOptional,
                  suffixText: _units.distance.symbol,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
                validator: (value) => _validateKm(value, l10n),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ActionChip(
                  avatar: const Icon(Icons.speed),
                  label: Text(
                    l10n.useCurrentKm(
                      _units.distance.format(widget.vehicle.currentOdometerKm),
                    ),
                  ),
                  onPressed: _useCurrentKm,
                ),
              ),
              if (_showsRefuelFields) ...[
                if (widget.vehicle.fuelType.hasFuelChoice) ...[
                  gap,
                  _FuelChoice(
                    fuels: widget.vehicle.fuelType.refuelFuels,
                    selected: _fuel!,
                    onChanged: _selectFuel,
                  ),
                ],
                gap,
                TextFormField(
                  key: const ValueKey('entry-volume-field'),
                  controller: _volume,
                  decoration: InputDecoration(
                    labelText: _fuel!.quantity == FuelQuantity.mass
                        ? l10n.fieldRefuelMass
                        : l10n.fieldRefuelVolume,
                    helperText: l10n.refuelVolumeHelp,
                    helperMaxLines: 2,
                    suffixText: _quantity.symbol,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(amountCharacters),
                  ],
                  textInputAction: TextInputAction.next,
                  onChanged: (text) =>
                      _editTriangle(TriangleField.volume, _parseVolume(text)),
                  validator: (value) => _validateVolume(value, l10n),
                ),
                gap,
                TextFormField(
                  key: const ValueKey('entry-price-field'),
                  controller: _price,
                  decoration: InputDecoration(
                    labelText: l10n.fieldRefuelPrice,
                    suffixText: _units.unitPriceSymbol(_fuel!),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(amountCharacters),
                  ],
                  textInputAction: TextInputAction.next,
                  onChanged: (text) {
                    final shown = tryParseUnitPrice(text);
                    _editTriangle(
                      TriangleField.price,
                      shown == null
                          ? null
                          : _units.unitPriceToSI(_fuel!, shown),
                    );
                  },
                  validator: (value) => _validatePrice(value, l10n),
                ),
              ],
              gap,
              TextFormField(
                key: const ValueKey('entry-cost-field'),
                controller: _cost,
                decoration: InputDecoration(
                  labelText: _showsRefuelFields
                      ? l10n.fieldRefuelAmount
                      : l10n.fieldEntryCost,
                  suffixText: currency.currencySymbol,
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(amountCharacters),
                ],
                textInputAction: TextInputAction.next,
                onChanged: (text) => _editTriangle(
                  TriangleField.amount,
                  text.trim().isEmpty ? null : tryParseEuroCents(text),
                ),
                validator: (value) => _validateCost(value, l10n),
              ),
              if (_showsRefuelFields) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const ValueKey('entry-full-tank-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.fieldRefuelFullTank),
                  value: _fullTank,
                  onChanged: (value) => setState(() => _fullTank = value),
                ),
                CheckboxListTile(
                  key: const ValueKey('entry-missed-checkbox'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l10n.fieldRefuelMissed),
                  subtitle: Text(l10n.refuelMissedHelp),
                  value: _missedPrevious,
                  onChanged: (value) =>
                      setState(() => _missedPrevious = value ?? false),
                ),
              ],
              if (closed.isNotEmpty) ...[
                gap,
                for (final reminder in closed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_available),
                    title: Text(l10n.entryClosedReminder(reminder.title)),
                    subtitle: Text(l10n.entryClosedReminderHint),
                  ),
              ] else if (_closable.isNotEmpty) ...[
                gap,
                DropdownButtonFormField<String?>(
                  // A new type offers other reminders: start again.
                  key: ValueKey('entry-closes-reminder-$type'),
                  initialValue: _closing?.reminder.id,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.entryClosesReminder,
                    helperText: l10n.entryClosesReminderHelp,
                    helperMaxLines: 2,
                    errorText: _closeError,
                    errorMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(l10n.entryClosesReminderNone),
                    ),
                    for (final view in _closable)
                      DropdownMenuItem(
                        value: view.reminder.id,
                        child: Text(
                          view.reminder.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() {
                    _closesReminderId = id;
                    _closeError = null;
                  }),
                ),
              ],
              gap,
              TextFormField(
                key: const ValueKey('entry-description-field'),
                controller: _description,
                decoration: InputDecoration(
                  labelText: l10n.fieldEntryDescription,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                textCapitalization: TextCapitalization.sentences,
                minLines: 3,
                maxLines: 8,
              ),
              gap,
              LogEntryAttachmentsField(formKey: widget.formKey),
            ],
          ),
        ),
      ),
    );
  }
}

/// The entry type choice (U3): one chip per type, icon and label, one tap.
///
/// A form field, so "type required" is validated with the other fields.
class _TypeChoice extends StatelessWidget {
  const _TypeChoice({
    required this.types,
    required this.selected,
    required this.onChanged,
  });

  final List<LogEntryType> types;
  final LogEntryType? selected;
  final ValueChanged<LogEntryType> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return FormField<LogEntryType>(
      // Rebuilt with the selection, so validation sees the current value.
      key: ValueKey(selected),
      initialValue: selected,
      validator: (value) =>
          value == null ? l10n.validationEntryTypeRequired : null,
      builder: (field) => Semantics(
        label: l10n.fieldEntryType,
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.fieldEntryType, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final type in types)
                  ChoiceChip(
                    avatar: Icon(type.icon),
                    label: Text(type.label(l10n)),
                    selected: type == selected,
                    // The avatar already identifies the type; the check
                    // mark would replace it.
                    showCheckmark: false,
                    onSelected: (_) => onChanged(type),
                  ),
              ],
            ),
            if (field.errorText case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 12),
                child: Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The fuel of a refuel on a bi-fuel vehicle: one segment per fuel the
/// vehicle allows, petrol first.
class _FuelChoice extends StatelessWidget {
  const _FuelChoice({
    required this.fuels,
    required this.selected,
    required this.onChanged,
  });

  final List<RefuelFuel> fuels;
  final RefuelFuel selected;
  final ValueChanged<RefuelFuel> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.fieldRefuelFuel,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SegmentedButton<RefuelFuel>(
          key: const ValueKey('entry-fuel-choice'),
          segments: [
            for (final fuel in fuels)
              ButtonSegment(value: fuel, label: Text(fuel.label(l10n))),
          ],
          selected: {selected},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.single),
        ),
      ],
    );
  }
}

/// The required entry date: the day formatted for the locale, opening the
/// Material date picker when tapped.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.date,
    required this.error,
    required this.onTap,
  });

  final CalendarDate date;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.fieldEntryDate,
          errorText: error,
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(l10n.dateValue(date.toLocalDateTime())),
      ),
    );
  }
}
