import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/router/navigation.dart';
import '../../../data/catalog/search_text.dart';
import '../../../data/models/calendar_date.dart';
import '../../../data/models/reminder.dart';
import '../../../data/models/reminder_kind.dart';
import '../../../data/models/vehicle.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/utils/unit_formatter.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../../shared/widgets/picker_form_field.dart';
import '../../../shared/widgets/searchable_picker.dart';
import '../../settings/controllers/settings_controller.dart';
import '../../vehicles/controllers/vehicle_tab_controller.dart';
import '../controllers/reminder_form_controller.dart';

/// The form that creates or edits a reminder (`Docs/08_recordatorios.md`):
/// kind (searchable, grouped, filtered by the vehicle), title, recurring or
/// one-shot, the intervals and the anchor (day and odometer of the last
/// time) or the due date, the reminder's own lead, a note and the manual
/// reference.
///
/// In edit mode the reference criterion is editable (it is the owner's
/// data); the applied criterion is changed from the detail page, as a line
/// under the fields says.
class ReminderFormPage extends ConsumerWidget {
  /// Creates the form for the vehicle with [vehicleId]; [reminderId] is
  /// `null` to create a reminder.
  const ReminderFormPage({super.key, required this.vehicleId, this.reminderId});

  /// Id of the vehicle, from the path.
  final String vehicleId;

  /// Id of the reminder to edit, from the path; `null` when creating.
  final String? reminderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final title =
        reminderId == null ? l10n.newReminder : l10n.reminderFormEditTitle;
    final key = (vehicleId: vehicleId, reminderId: reminderId);
    return ref.watch(reminderFormControllerProvider(key)).when(
          loading: () => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: MessageView(
              icon: Icons.error_outline,
              message: l10n.loadError,
            ),
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
            final reminder = data.reminder;
            if (reminderId != null && reminder == null) {
              return NotFoundPage(message: l10n.reminderNotFound);
            }
            // A completed reminder is read-only.
            if (reminder != null && reminder.isCompleted) {
              return NotFoundPage(message: l10n.errorReminderRule);
            }
            return _ReminderForm(
              formKey: key,
              vehicle: vehicle,
              initial: reminder,
              usedKinds: data.usedKinds,
              kindLocked: data.kindLocked,
              title: title,
            );
          },
        );
  }
}

/// The form itself, holding the values being typed.
class _ReminderForm extends ConsumerStatefulWidget {
  const _ReminderForm({
    required this.formKey,
    required this.vehicle,
    required this.initial,
    required this.usedKinds,
    required this.kindLocked,
    required this.title,
  });

  final ReminderFormKey formKey;
  final Vehicle vehicle;
  final Reminder? initial;
  final Set<ReminderKind> usedKinds;

  /// An entry has closed the reminder: kind and mode cannot change.
  final bool kindLocked;
  final String title;

  @override
  ConsumerState<_ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends ConsumerState<_ReminderForm> {
  final _formKey = GlobalKey<FormState>();

  late ReminderKind? _kind = widget.initial?.kind;
  late final _title = TextEditingController(text: widget.initial?.title);

  /// Recurring (`false`) or one-shot (`true`).
  late bool _oneShot = widget.initial?.isOneShot ?? false;

  /// Filled in [didChangeDependencies], in the unit of the moment.
  final _intervalKm = TextEditingController();
  late final _intervalMonths = TextEditingController(
    text: widget.initial?.refIntervalMonths?.toString(),
  );
  final _anchorKm = TextEditingController();
  late final _leadDays =
      TextEditingController(text: widget.initial?.leadDays?.toString());
  final _leadKm = TextEditingController();
  late final _note = TextEditingController(text: widget.initial?.note);
  late final _manualRef =
      TextEditingController(text: widget.initial?.manualRef);
  bool _storedValuesFilled = false;

  /// The anchor day: the reminder's, or today for a new one.
  late CalendarDate _anchorDate =
      widget.initial?.lastDoneDate ?? calendarDateOf(DateTime.now());

  /// The due day of a one-shot reminder; none until chosen.
  late CalendarDate? _dueDate = widget.initial?.dueDate;

  /// The error under the anchor day or the due day.
  String? _dateError;

  /// Whether a save is running; the save button is disabled meanwhile.
  bool _saving = false;

  /// The formatter of the last build, for the validators and the save.
  late UnitFormatter _units;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_storedValuesFilled) {
      final units = readUnitFormatter(context, ref);
      final initial = widget.initial;
      String text(double? km) => km == null ? '' : units.distance.inputText(km);
      _intervalKm.text = text(initial?.refIntervalKm);
      // A new reminder starts from the current reading, as a hint the owner
      // corrects with the real value of the last time.
      _anchorKm.text = initial == null
          ? text(widget.vehicle.currentOdometerKm)
          : text(initial.lastDoneKm);
      _leadKm.text = text(initial?.leadKm);
    }
    _storedValuesFilled = true;
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _intervalKm,
      _intervalMonths,
      _anchorKm,
      _leadDays,
      _leadKm,
      _note,
      _manualRef,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Today's calendar day on the phone.
  CalendarDate get _today => calendarDateOf(DateTime.now());

  /// Parses a distance typed in the chosen unit to km; the stored [sameAs]
  /// itself when the text is exactly how it shows.
  double? _distance(TextEditingController controller, double? sameAs) {
    final text = controller.text.trim();
    return text.isEmpty ? null : _units.distance.parse(text, sameAs: sameAs);
  }

  /// Opens the grouped, searchable kind picker: the kinds that apply to the
  /// vehicle, every kind with "Show all", never one already used on the
  /// vehicle; "Other…" is pinned and takes a free title.
  Future<void> _pickKind() async {
    final l10n = AppLocalizations.of(context);
    final vehicle = widget.vehicle;
    List<ReminderKind> available({required bool all}) => [
          for (final kind in ReminderKind.values)
            if (kind != ReminderKind.other &&
                !widget.usedKinds.contains(kind) &&
                (all || kind.appliesTo(vehicle.kind, vehicle.fuelType)))
              kind,
        ];
    List<ReminderKind> matching(List<ReminderKind> kinds, String query) {
      final folded = foldForSearch(query.trim());
      if (folded.isEmpty) return kinds;
      return [
        for (final kind in kinds)
          if (foldForSearch(kind.label(l10n)).contains(folded)) kind,
      ];
    }

    final result = await showSearchablePicker<ReminderKind>(
      context: context,
      title: l10n.reminderKindPickerTitle,
      search: (query) => matching(available(all: false), query),
      searchAll: (query) => matching(available(all: true), query),
      showAllLabel: l10n.reminderKindShowAll,
      labelOf: (kind) => kind.label(l10n),
      sectionOf: (kind) => kind.group.label(l10n),
      otherLabel: l10n.reminderKindOther,
    );
    if (!mounted) return;
    switch (result) {
      case Picked(:final value):
        _setKind(value, value.label(l10n));
      case PickedOther(:final query):
        _setKind(ReminderKind.other, query);
      case null:
        break;
    }
  }

  /// Sets [kind] and prefills the title with [title] unless the owner
  /// already typed one of their own.
  void _setKind(ReminderKind kind, String title) {
    final l10n = AppLocalizations.of(context);
    final current = _title.text.trim();
    final previous = _kind;
    setState(() {
      if (current.isEmpty || current == previous?.label(l10n)) {
        _title.text = title;
      }
      _kind = kind;
    });
  }

  /// Opens the date picker for the anchor day (never after today) or the
  /// due day (any day).
  Future<void> _pickDate({required bool due}) async {
    final today = _today.toLocalDateTime();
    final current = (due ? _dueDate : _anchorDate)?.toLocalDateTime();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          current == null || (!due && current.isAfter(today)) ? today : current,
      firstDate: DateTime(1900),
      lastDate: due ? DateTime(2100) : today,
    );
    if (picked != null && mounted) {
      setState(() {
        if (due) {
          _dueDate = calendarDateOf(picked);
        } else {
          _anchorDate = calendarDateOf(picked);
        }
        _dateError = null;
      });
    }
  }

  /// The error of the anchor day or the due day, or `null`.
  String? _validateDate(AppLocalizations l10n) {
    if (_oneShot) {
      return _dueDate == null ? l10n.validationDueDateRequired : null;
    }
    return _anchorDate.isAfter(_today) ? l10n.validationDateNotFuture : null;
  }

  /// A km interval: empty, or a whole number above 0 in the chosen unit.
  String? _validateIntervalKm(String? value, AppLocalizations l10n) {
    if ((value ?? '').trim().isEmpty) return null;
    final km = _distance(_intervalKm, widget.initial?.refIntervalKm);
    return km == null || km <= 0 ? l10n.validationWholeNumberAboveZero : null;
  }

  /// A months interval: empty, or a whole number above 0; at least one of
  /// the two intervals is required.
  String? _validateIntervalMonths(String? value, AppLocalizations l10n) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return _intervalKm.text.trim().isEmpty
          ? l10n.validationReminderIntervalRequired
          : null;
    }
    final months = int.tryParse(text);
    return months == null || months <= 0
        ? l10n.validationWholeNumberAboveZero
        : null;
  }

  /// The anchor odometer: required with a km interval, a whole number ≥ 0.
  String? _validateAnchorKm(String? value, AppLocalizations l10n) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return _intervalKm.text.trim().isEmpty
          ? null
          : l10n.validationReminderAnchorKmRequired;
    }
    final km = _distance(_anchorKm, _anchorSameAs);
    return km == null || km < 0 ? l10n.validationKmInvalid : null;
  }

  /// The stored value the anchor field round-trips to.
  double? get _anchorSameAs =>
      widget.initial?.lastDoneKm ??
      (widget.initial == null ? widget.vehicle.currentOdometerKm : null);

  /// An optional lead: empty, or a whole number ≥ 0.
  String? _validateLead(String? value, AppLocalizations l10n) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final number = int.tryParse(text);
    return number == null || number < 0 ? l10n.validationWholeNumber : null;
  }

  /// Validates the fields and saves through the controller.
  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final dateError = _validateDate(l10n);
    setState(() => _dateError = dateError);
    if (!_formKey.currentState!.validate() || dateError != null) return;
    final kind = _kind!;
    final messenger = ScaffoldMessenger.of(context);
    final form =
        ref.read(reminderFormControllerProvider(widget.formKey).notifier);
    final intervalKm = _distance(_intervalKm, widget.initial?.refIntervalKm);
    final draft = ReminderDraft(
      kind: kind,
      title: _title.text,
      note: _note.text,
      manualRef: _manualRef.text,
      refIntervalKm: _oneShot ? null : intervalKm,
      refIntervalMonths:
          _oneShot ? null : int.tryParse(_intervalMonths.text.trim()),
      dueDate: _oneShot ? _dueDate : null,
      lastDoneDate: _oneShot ? null : _anchorDate,
      lastDoneKm: _oneShot ? null : _distance(_anchorKm, _anchorSameAs),
      leadDays: int.tryParse(_leadDays.text.trim()),
      leadKm: _distance(_leadKm, widget.initial?.leadKm),
    );
    setState(() => _saving = true);
    final result = await form.save(draft);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case ActionSuccess(:final value):
        showSavedSnackBar(messenger, l10n.reminderSaved);
        context.popOrGo(
          AppRoutes.vehicle(value.vehicleId, tab: VehicleTab.reminders),
          value.id,
        );
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    _units = unitFormatterOf(context, ref);
    final theme = Theme.of(context);
    const gap = SizedBox(height: 16);
    final kind = _kind;
    final distanceField = InputDecoration(
      suffixText: _units.distance.symbol,
      border: const OutlineInputBorder(),
    );
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
              PickerFormField(
                key: const ValueKey('reminder-kind-field'),
                label: l10n.reminderFieldKind,
                value: kind?.label(l10n),
                onTap: _pickKind,
                enabled: !widget.kindLocked,
                validator: (value) =>
                    value == null ? l10n.validationReminderKindRequired : null,
              ),
              gap,
              TextFormField(
                key: const ValueKey('reminder-title-field'),
                controller: _title,
                decoration: InputDecoration(
                  labelText: l10n.reminderFieldTitle,
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) => (value ?? '').trim().isEmpty
                    ? l10n.validationReminderTitleRequired
                    : null,
              ),
              gap,
              SegmentedButton<bool>(
                key: const ValueKey('reminder-mode'),
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.repeat),
                    label: Text(l10n.reminderModePeriodic),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.event),
                    label: Text(l10n.reminderModeOneShot),
                  ),
                ],
                selected: {_oneShot},
                onSelectionChanged: widget.kindLocked
                    ? null
                    : (selection) => setState(() {
                          _oneShot = selection.single;
                          _dateError = null;
                        }),
              ),
              if (widget.kindLocked) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.reminderKindLockedHint,
                  key: const ValueKey('reminder-kind-locked'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              gap,
              if (_oneShot)
                _DateField(
                  key: const ValueKey('reminder-due-date'),
                  label: l10n.reminderFieldDueDate,
                  date: _dueDate,
                  error: _dateError,
                  onTap: () => _pickDate(due: true),
                )
              else ...[
                TextFormField(
                  key: const ValueKey('reminder-interval-km'),
                  controller: _intervalKm,
                  decoration: distanceField.copyWith(
                    labelText: l10n.reminderFieldIntervalDistance,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  // The months field and the anchor depend on this one.
                  onChanged: (_) => setState(() {}),
                  validator: (value) => _validateIntervalKm(value, l10n),
                ),
                gap,
                TextFormField(
                  key: const ValueKey('reminder-interval-months'),
                  controller: _intervalMonths,
                  decoration: InputDecoration(
                    labelText: l10n.reminderFieldIntervalMonths,
                    suffixText: l10n.unitMonthsSuffix,
                    helperText: l10n.reminderIntervalHelp,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) => _validateIntervalMonths(value, l10n),
                ),
                gap,
                _DateField(
                  key: const ValueKey('reminder-anchor-date'),
                  label: l10n.reminderFieldAnchorDate,
                  date: _anchorDate,
                  error: _dateError,
                  onTap: () => _pickDate(due: false),
                ),
                gap,
                TextFormField(
                  key: const ValueKey('reminder-anchor-km'),
                  controller: _anchorKm,
                  decoration: distanceField.copyWith(
                    labelText: l10n.reminderFieldAnchorDistance,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) => _validateAnchorKm(value, l10n),
                ),
              ],
              gap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('reminder-lead-days'),
                      controller: _leadDays,
                      decoration: InputDecoration(
                        labelText: l10n.reminderFieldLeadDays,
                        hintText: l10n.reminderLeadUseGlobal,
                        suffixText: l10n.unitDaysSuffix,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) => _validateLead(value, l10n),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('reminder-lead-km'),
                      controller: _leadKm,
                      decoration: distanceField.copyWith(
                        labelText: l10n.reminderFieldLeadDistance,
                        hintText: l10n.reminderLeadUseGlobal,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) => _validateLead(value, l10n),
                    ),
                  ),
                ],
              ),
              gap,
              TextFormField(
                controller: _note,
                decoration: InputDecoration(
                  labelText: l10n.reminderFieldNote,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 6,
              ),
              gap,
              TextFormField(
                controller: _manualRef,
                decoration: InputDecoration(
                  labelText: l10n.reminderFieldManualRef,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (widget.initial != null) ...[
                gap,
                Text(
                  l10n.reminderAppliedHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable date field with its error, as in the entry form.
class _DateField extends StatelessWidget {
  const _DateField({
    super.key,
    required this.label,
    required this.date,
    required this.error,
    required this.onTap,
  });

  final String label;
  final CalendarDate? date;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final date = this.date;
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        isEmpty: date == null,
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(date == null ? '' : l10n.dateValue(date.toLocalDateTime())),
      ),
    );
  }
}
