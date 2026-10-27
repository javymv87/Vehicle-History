import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/router/navigation.dart';
import '../../../data/models/calendar_date.dart';
import '../../../data/models/mileage_reading.dart';
import '../../../data/models/vehicle.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../vehicles/controllers/vehicle_tab_controller.dart';
import '../controllers/mileage_reading_form_controller.dart';
import '../widgets/big_jump_confirmation.dart';

/// Form that adds an odometer reading to a vehicle (no [readingId]), or
/// corrects its sole reading (`Docs/03_features.md`, U13–U14).
///
/// Km and date only. A new reading is bounded by the last one: at least its
/// km, on its day or later, and never after today.
class MileageReadingFormPage extends ConsumerWidget {
  /// Creates the form for the vehicle with [vehicleId]; [readingId] is
  /// `null` to add a reading.
  const MileageReadingFormPage({
    super.key,
    required this.vehicleId,
    this.readingId,
  });

  /// Id of the vehicle, from the path.
  final String vehicleId;

  /// Id of the reading to correct, from the path; `null` when adding.
  final String? readingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final title = readingId == null
        ? l10n.newMileageReadingTitle
        : l10n.editMileageReadingTitle;
    final key = (vehicleId: vehicleId, readingId: readingId);
    final initial = ref.watch(mileageReadingFormControllerProvider(key));
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
        // An archived vehicle is read-only (reachable only by deep link).
        if (vehicle.isArchived) {
          return NotFoundPage(message: l10n.errorVehicleArchived);
        }
        if (readingId != null && data.editing == null) {
          return NotFoundPage(message: l10n.readingNotCorrectable);
        }
        return _MileageReadingForm(
          formKey: key,
          vehicle: vehicle,
          lastReading: data.lastReading,
          editing: data.editing,
          title: title,
        );
      },
    );
  }
}

/// The reading form itself, holding the values being typed.
class _MileageReadingForm extends ConsumerStatefulWidget {
  const _MileageReadingForm({
    required this.formKey,
    required this.vehicle,
    required this.lastReading,
    required this.editing,
    required this.title,
  });

  final MileageReadingFormKey formKey;
  final Vehicle vehicle;
  final MileageReading? lastReading;
  final MileageReading? editing;
  final String title;

  @override
  ConsumerState<_MileageReadingForm> createState() =>
      _MileageReadingFormState();
}

class _MileageReadingFormState extends ConsumerState<_MileageReadingForm> {
  final _formKey = GlobalKey<FormState>();

  /// Empty when adding: the km is never prefilled with a guess.
  late final _km = TextEditingController(text: widget.editing?.km.toString());

  /// Today when adding (U13); the reading's own day when correcting.
  late CalendarDate _date =
      widget.editing?.date ?? calendarDateOf(DateTime.now());

  /// Shown under the date when it is out of range.
  String? _dateError;

  /// Whether a save is running; the save button is disabled meanwhile.
  bool _saving = false;

  /// Whether this form corrects the sole reading instead of adding one.
  bool get _correcting => widget.editing != null;

  /// The reading a new one must not go below; none when correcting, since
  /// the sole reading has nothing before it.
  MileageReading? get _lowerBound => _correcting ? null : widget.lastReading;

  @override
  void dispose() {
    _km.dispose();
    super.dispose();
  }

  /// Today's calendar day on the phone.
  CalendarDate get _today => calendarDateOf(DateTime.now());

  /// Opens the Material date picker, limited to [last reading day, today].
  Future<void> _pickDate() async {
    final first = _lowerBound?.date.toLocalDateTime() ?? DateTime(1900);
    final last = _today.toLocalDateTime();
    var initial = _date.toLocalDateTime();
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null && mounted) {
      setState(() {
        _date = calendarDateOf(picked);
        _dateError = null;
      });
    }
  }

  /// Checks the km: a whole number ≥ 0, not below the last reading.
  String? _validateKm(String? value, AppLocalizations l10n) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return l10n.validationKmRequired;
    final km = int.tryParse(text);
    if (km == null || km < 0) return l10n.validationKmInvalid;
    final bound = _lowerBound;
    if (bound != null && km < bound.km) {
      return l10n.validationReadingKmBelowLast(bound.km);
    }
    return null;
  }

  /// The date error, or `null`: never after today, never before the last
  /// reading.
  String? _validateDate(AppLocalizations l10n) {
    final bound = _lowerBound;
    final outOfRange =
        _date.isAfter(_today) || (bound != null && _date.isBefore(bound.date));
    return outOfRange ? l10n.validationReadingDateOutOfRange : null;
  }

  /// Validates, asks about a big jump, and saves through the controller.
  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final dateError = _validateDate(l10n);
    setState(() => _dateError = dateError);
    final fieldsValid = _formKey.currentState!.validate();
    if (!fieldsValid || dateError != null) return;

    final km = int.parse(_km.text.trim());
    final bound = _lowerBound;
    if (bound != null) {
      final confirmed =
          await confirmBigOdometerJump(context, km: km, lastKm: bound.km);
      if (!confirmed || !mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final result = await ref
        .read(mileageReadingFormControllerProvider(widget.formKey).notifier)
        .save(date: _date, km: km);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case ActionSuccess(:final value):
        showSavedSnackBar(messenger, l10n.readingSaved);
        context.popOrGo(
          AppRoutes.vehicle(widget.vehicle.id, tab: VehicleTab.mileage),
          value.id,
        );
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bound = _lowerBound;
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('reading-km-field'),
                controller: _km,
                autofocus: !_correcting,
                decoration: InputDecoration(
                  labelText: l10n.fieldReadingKm,
                  helperText: bound == null
                      ? null
                      : l10n.lastReadingHint(
                          bound.km,
                          bound.date.toLocalDateTime(),
                        ),
                  helperMaxLines: 2,
                  errorMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.done,
                validator: (value) => _validateKm(value, l10n),
              ),
              const SizedBox(height: 16),
              InkWell(
                key: const ValueKey('reading-date-field'),
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.fieldReadingDate,
                    errorText: _dateError,
                    errorMaxLines: 3,
                    border: const OutlineInputBorder(),
                    suffixIcon: const Icon(Icons.calendar_today),
                  ),
                  child: Text(l10n.dateValue(_date.toLocalDateTime())),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
