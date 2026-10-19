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
import '../../../data/models/mileage_reading.dart';
import '../../../data/models/odometer_checks.dart';
import '../../../data/models/vehicle.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/utils/money.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../mileage/controllers/odometer_update_offer_controller.dart';
import '../../mileage/widgets/odometer_update_offer.dart';
import '../controllers/log_entry_form_controller.dart';
import '../widgets/log_entry_type_icon.dart';

/// Form that creates a history entry for a vehicle (no [entryId]) or edits
/// one (`Docs/03_features.md`, U3–U5, U10 and E1–E3).
///
/// Built for few taps: type, date (today by default), km with a one-tap
/// "use current km" chip, cost and description, with Save always in the app
/// bar.
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
        body: MessageView(icon: Icons.error_outline, message: l10n.loadError),
      ),
      data: (data) {
        final vehicle = data.vehicle;
        if (vehicle == null) {
          return NotFoundPage(message: l10n.vehicleNotFound);
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
  late final _km = TextEditingController(text: widget.initial?.km?.toString());
  late final _description =
      TextEditingController(text: widget.initial?.description);

  /// Filled in [didChangeDependencies], where the locale is known.
  final _cost = TextEditingController();
  bool _costFilled = false;

  late LogEntryType? _type = widget.initial?.type;

  /// The day of the event: today when creating (U3), never prefilled with
  /// anything else.
  late CalendarDate _date =
      widget.initial?.date ?? calendarDateOf(DateTime.now());

  /// Shown under the date when the type does not allow a future day (E1).
  String? _dateError;

  /// Whether a save is running; the save button is disabled meanwhile.
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The stored cents become text with the separator of the app language.
    final cents = widget.initial?.costCents;
    if (!_costFilled && cents != null) {
      _cost.text =
          euroCentsInputText(cents, AppLocalizations.of(context).localeName);
    }
    _costFilled = true;
  }

  @override
  void dispose() {
    _km.dispose();
    _description.dispose();
    _cost.dispose();
    super.dispose();
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

  /// Copies the vehicle's current odometer into the km field (U4).
  void _useCurrentKm() {
    setState(() => _km.text = '${widget.vehicle.currentOdometerKm}');
  }

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

  /// Checks the km: a whole number ≥ 0, required for some types (U10).
  String? _validateKm(String? value, AppLocalizations l10n) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return _kmRequired ? l10n.validationEntryKmRequired : null;
    }
    final km = int.tryParse(text);
    if (km == null || km < 0) return l10n.validationKmInvalid;
    return null;
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
    final km = kmText.isEmpty ? null : int.parse(kmText);
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
          conflicting.km,
          conflicting.date.toLocalDateTime(),
        ),
        confirmLabel: l10n.actionSaveAnyway,
      );
      if (!confirmed || !mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    // Captured now: the offer's "Update" runs after this form is gone.
    final router = GoRouter.of(context);
    final offer = ref.read(odometerUpdateOfferControllerProvider.notifier);
    setState(() => _saving = true);
    final result = await ref
        .read(logEntryFormControllerProvider(widget.formKey).notifier)
        .save(
          LogEntryDraft(
            date: _date,
            type: _type!,
            km: km,
            description: _description.text,
            costCents: costText.isEmpty ? null : tryParseEuroCents(costText),
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
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
            offer: offer,
            vehicleId: value.vehicleId,
            date: value.date,
            km: entryKm,
            currentKm: currentKm,
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
    final currency =
        NumberFormat.simpleCurrency(locale: l10n.localeName, name: 'EUR');
    const gap = SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(l10n.actionSave),
          ),
        ],
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
                    l10n.useCurrentKm(widget.vehicle.currentOdometerKm),
                  ),
                  onPressed: _useCurrentKm,
                ),
              ),
              gap,
              TextFormField(
                key: const ValueKey('entry-cost-field'),
                controller: _cost,
                decoration: InputDecoration(
                  labelText: l10n.fieldEntryCost,
                  suffixText: currency.currencySymbol,
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(amountCharacters),
                ],
                textInputAction: TextInputAction.next,
                validator: (value) => _validateCost(value, l10n),
              ),
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
