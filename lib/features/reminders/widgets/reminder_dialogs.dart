import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/calendar_date.dart';
import '../../../data/models/log_entry.dart';
import '../../../data/models/reminder.dart';
import '../../../data/models/reminder_status.dart';
import '../../../data/models/vehicle.dart';
import '../../../data/repositories/reminder_closer.dart';
import '../../../data/repositories/repository_exceptions.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/utils/money.dart';
import '../../../shared/utils/unit_formatter.dart';
import '../../settings/controllers/settings_controller.dart';
import '../controllers/reminder_actions_controller.dart';
import 'reminder_texts.dart';

// The dialogs of a reminder's detail page. Each validates its fields, shows
// a refusal of the repository inside itself (it stays open), and resolves to
// what was written, or `null` when cancelled.

/// Today's calendar day on the phone.
CalendarDate _today() => calendarDateOf(DateTime.now());

/// The error text shown under a dialog's fields, or nothing.
Widget _errorText(BuildContext context, String? error) {
  if (error == null) return const SizedBox.shrink();
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Text(
      error,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.error,
      ),
    ),
  );
}

/// Opens the "Mark done" dialog of [reminder] on [vehicle]: day (today by
/// default, never later), odometer, cost and description (prefilled with
/// the title). Resolves to the entry created, or `null` when cancelled.
Future<LogEntry?> showMarkDoneDialog(
  BuildContext context, {
  required Reminder reminder,
  required Vehicle vehicle,
}) =>
    showDialog<LogEntry>(
      context: context,
      builder: (context) =>
          _MarkDoneDialog(reminder: reminder, vehicle: vehicle),
    );

class _MarkDoneDialog extends ConsumerStatefulWidget {
  const _MarkDoneDialog({required this.reminder, required this.vehicle});

  final Reminder reminder;
  final Vehicle vehicle;

  @override
  ConsumerState<_MarkDoneDialog> createState() => _MarkDoneDialogState();
}

class _MarkDoneDialogState extends ConsumerState<_MarkDoneDialog> {
  final _formKey = GlobalKey<FormState>();
  CalendarDate _date = _today();
  final _km = TextEditingController();
  final _cost = TextEditingController();
  late final _description = TextEditingController(text: widget.reminder.title);
  late UnitFormatter _units;

  /// A refusal shown under the date, the odometer, or the whole form.
  String? _dateError;
  String? _kmError;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _km.dispose();
    _cost.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Whether the odometer is required: by the entry type (a maintenance
  /// always needs it) or by the reminder's km interval.
  bool get _kmRequired =>
      widget.reminder.kind.markDoneEntryType.requiresKm ||
      widget.reminder.usesKm;

  double? get _typedKm {
    final text = _km.text.trim();
    return text.isEmpty
        ? null
        : _units.distance.parse(text, sameAs: widget.vehicle.currentOdometerKm);
  }

  Future<void> _pickDate() async {
    final today = _today().toLocalDateTime();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.toLocalDateTime(),
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (picked != null && mounted) {
      setState(() {
        _date = calendarDateOf(picked);
        _dateError = null;
      });
    }
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _dateError = null;
      _kmError = null;
      _error = null;
    });
    if (!_formKey.currentState!.validate()) return;
    final km = _typedKm;
    final reminder = widget.reminder;
    // The rules of the close, checked here so their message lands on the
    // field it is about.
    try {
      ReminderCloser.checkEntry(
        reminder,
        vehicleId: reminder.vehicleId,
        type: reminder.kind.markDoneEntryType,
        date: _date,
        km: km,
        today: _today(),
      );
    } on RepositoryException catch (error) {
      final message = closingErrorText(error, reminder, l10n, _units);
      setState(() {
        switch (error) {
          case InvalidFieldException(field: 'date'):
            _dateError = message;
          case InvalidFieldException(field: 'km'):
            _kmError = message;
          default:
            _error = message;
        }
      });
      return;
    }
    final costText = _cost.text.trim();
    setState(() => _saving = true);
    final result =
        await ref.read(reminderActionsControllerProvider.notifier).markDone(
              reminder.id,
              date: _date,
              km: km,
              costCents: costText.isEmpty ? null : tryParseEuroCents(costText),
              description: _description.text,
            );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case ActionSuccess(:final value):
        Navigator.of(context).pop(value);
      case ActionFailure(:final error):
        setState(() => _error = error.message(l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    _units = unitFormatterOf(context, ref);
    final type = widget.reminder.kind.markDoneEntryType;
    final currency =
        NumberFormat.simpleCurrency(locale: l10n.localeName, name: 'EUR');
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.reminderActionMarkDone),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Context(l10n.reminderMarkDoneIntro(type.label(l10n))),
            const SizedBox(height: 16),
            InkWell(
              onTap: _saving ? null : _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.fieldEntryDate,
                  errorText: _dateError,
                  errorMaxLines: 3,
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(l10n.dateValue(_date.toLocalDateTime())),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('mark-done-km'),
              controller: _km,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText:
                    _kmRequired ? l10n.fieldEntryKm : l10n.fieldEntryKmOptional,
                suffixText: _units.distance.symbol,
                errorText: _kmError,
                errorMaxLines: 3,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) {
                  return _kmRequired ? l10n.validationEntryKmRequired : null;
                }
                final km = _typedKm;
                return km == null || km < 0 ? l10n.validationKmInvalid : null;
              },
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
                onPressed: () => setState(
                  () => _km.text = _units.distance
                      .inputText(widget.vehicle.currentOdometerKm),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _cost,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: l10n.fieldEntryCost,
                suffixText: currency.currencySymbol,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(amountCharacters),
              ],
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return null;
                return tryParseEuroCents(text) == null
                    ? l10n.validationCostInvalid
                    : null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _description,
              enabled: !_saving,
              decoration:
                  InputDecoration(labelText: l10n.fieldEntryDescription),
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 4,
            ),
            _errorText(context, _error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          child: Text(l10n.reminderActionMarkDone),
        ),
      ],
    );
  }
}

/// Opens the "Postpone" dialog of [reminder], whose applied due values are
/// in [due]: a later day and / or odometer, on the axes that have a due
/// value, with a mandatory reason. Resolves to the snoozed reminder, or
/// `null` when cancelled.
Future<Reminder?> showSnoozeDialog(
  BuildContext context, {
  required Reminder reminder,
  required ReminderDue due,
}) =>
    showDialog<Reminder>(
      context: context,
      builder: (context) => _SnoozeDialog(reminder: reminder, due: due),
    );

class _SnoozeDialog extends ConsumerStatefulWidget {
  const _SnoozeDialog({required this.reminder, required this.due});

  final Reminder reminder;
  final ReminderDue due;

  @override
  ConsumerState<_SnoozeDialog> createState() => _SnoozeDialogState();
}

class _SnoozeDialogState extends ConsumerState<_SnoozeDialog> {
  final _formKey = GlobalKey<FormState>();
  late CalendarDate? _until = widget.reminder.snoozeUntilDate;
  final _km = TextEditingController();
  late final _reason =
      TextEditingController(text: widget.reminder.snoozeReason);
  late UnitFormatter _units;
  bool _kmFilled = false;
  String? _dateError;
  String? _error;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final km = widget.reminder.snoozeUntilKm;
    if (!_kmFilled && km != null) {
      _km.text = readUnitFormatter(context, ref).distance.inputText(km);
    }
    _kmFilled = true;
  }

  @override
  void dispose() {
    _km.dispose();
    _reason.dispose();
    super.dispose();
  }

  double? get _typedKm {
    final text = _km.text.trim();
    return text.isEmpty
        ? null
        : _units.distance.parse(text, sameAs: widget.reminder.snoozeUntilKm);
  }

  Future<void> _pickDate() async {
    final due = widget.due.dueDate!;
    final first = due.addDays(1).toLocalDateTime();
    final current = _until?.toLocalDateTime();
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null || current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        _until = calendarDateOf(picked);
        _dateError = null;
      });
    }
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    final due = widget.due;
    String? dateError;
    final until = _until;
    if (until != null && !until.isAfter(due.dueDate!)) {
      dateError = l10n.validationSnoozeNotLater(
        l10n.dateValue(due.dueDate!.toLocalDateTime()),
      );
    } else if (until == null &&
        _km.text.trim().isEmpty &&
        due.dueDate != null) {
      // Without a date axis the odometer field says it instead.
      dateError = l10n.validationSnoozeAxisRequired;
    }
    setState(() {
      _dateError = dateError;
      _error = null;
    });
    final fieldsValid = _formKey.currentState!.validate();
    if (!fieldsValid || dateError != null) return;
    setState(() => _saving = true);
    final result =
        await ref.read(reminderActionsControllerProvider.notifier).snooze(
              widget.reminder.id,
              untilDate: until,
              untilKm: _typedKm,
              reason: _reason.text,
            );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case ActionSuccess(:final value):
        Navigator.of(context).pop(value);
      case ActionFailure(:final error):
        setState(() => _error = error.message(l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    _units = unitFormatterOf(context, ref);
    final due = widget.due;
    final dueKm = due.dueKm;
    final until = _until;
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.reminderActionSnooze),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Context(
              l10n.reminderSnoozeCurrentDue(
                joinParts(l10n, [
                  if (due.dueDate case final date?)
                    l10n.dateValue(date.toLocalDateTime()),
                  if (dueKm != null) _units.distance.format(dueKm),
                ]),
              ),
            ),
            if (due.dueDate != null) ...[
              const SizedBox(height: 16),
              InkWell(
                onTap: _saving ? null : _pickDate,
                child: InputDecorator(
                  isEmpty: until == null,
                  decoration: InputDecoration(
                    labelText: l10n.reminderSnoozeUntilDate,
                    errorText: _dateError,
                    errorMaxLines: 3,
                    suffixIcon: until == null
                        ? const Icon(Icons.calendar_today)
                        : IconButton(
                            tooltip: MaterialLocalizations.of(context)
                                .deleteButtonTooltip,
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _until = null),
                          ),
                  ),
                  child: Text(
                    until == null
                        ? ''
                        : l10n.dateValue(until.toLocalDateTime()),
                  ),
                ),
              ),
            ],
            if (dueKm != null) ...[
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('snooze-km'),
                controller: _km,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: l10n.reminderSnoozeUntilDistance,
                  suffixText: _units.distance.symbol,
                  errorMaxLines: 3,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return due.dueDate == null
                        ? l10n.validationSnoozeAxisRequired
                        : null;
                  }
                  final km = _typedKm;
                  if (km == null) return l10n.validationKmInvalid;
                  return km <= dueKm
                      ? l10n.validationSnoozeNotLater(
                          _units.distance.format(dueKm),
                        )
                      : null;
                },
              ),
            ],
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('snooze-reason'),
              controller: _reason,
              enabled: !_saving,
              decoration: InputDecoration(labelText: l10n.reminderReasonField),
              textCapitalization: TextCapitalization.sentences,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? l10n.validationReasonRequired
                  : null,
            ),
            _errorText(context, _error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          child: Text(l10n.reminderActionSnooze),
        ),
      ],
    );
  }
}

/// Opens the "Customise criterion" dialog of the recurring [reminder]: the
/// two applied intervals, each with a "Turn this criterion off" switch,
/// the odometer of the last time when a km axis is added without one (a
/// fact, never assumed), a mandatory reason, and a line saying what
/// changes. Resolves to the overridden reminder, or `null` when cancelled.
Future<Reminder?> showOverrideDialog(
  BuildContext context, {
  required Reminder reminder,
}) =>
    showDialog<Reminder>(
      context: context,
      builder: (context) => _OverrideDialog(reminder: reminder),
    );

class _OverrideDialog extends ConsumerStatefulWidget {
  const _OverrideDialog({required this.reminder});

  final Reminder reminder;

  @override
  ConsumerState<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends ConsumerState<_OverrideDialog> {
  final _formKey = GlobalKey<FormState>();

  /// The starting values: the applied criterion when already overridden,
  /// the reference one otherwise.
  late final double? _startKm = widget.reminder.overrideActive
      ? widget.reminder.appliedIntervalKm
      : widget.reminder.refIntervalKm;
  late final int? _startMonths = widget.reminder.overrideActive
      ? widget.reminder.appliedIntervalMonths
      : widget.reminder.refIntervalMonths;

  /// Whether each axis is turned off; an axis with no starting value
  /// starts off.
  late bool _kmOff = _startKm == null;
  late bool _monthsOff = _startMonths == null;

  final _km = TextEditingController();
  late final _months = TextEditingController(text: _startMonths?.toString());
  final _anchorKm = TextEditingController();
  late final _reason = TextEditingController(
    text: widget.reminder.overrideActive ? widget.reminder.overrideReason : '',
  );
  late UnitFormatter _units;
  bool _kmFilled = false;
  String? _error;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final km = _startKm;
    if (!_kmFilled && km != null) {
      _km.text = readUnitFormatter(context, ref).distance.inputText(km);
    }
    _kmFilled = true;
  }

  @override
  void dispose() {
    _km.dispose();
    _months.dispose();
    _anchorKm.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// Whether the odometer of the last time must be asked: a km axis on a
  /// reminder that has no km anchor yet.
  bool get _needsAnchorKm => !_kmOff && widget.reminder.lastDoneKm == null;

  double? get _typedKm => _kmOff || _km.text.trim().isEmpty
      ? null
      : _units.distance.parse(_km.text.trim(), sameAs: _startKm);

  int? get _typedMonths =>
      _monthsOff ? null : int.tryParse(_months.text.trim());

  /// "From … to …" for the summary line, with the values typed so far.
  String _summary(AppLocalizations l10n) {
    final reminder = widget.reminder;
    final from = reminder.overrideActive
        ? appliedCriterionText(reminder, l10n, _units)
        : referenceCriterionText(reminder, l10n, _units);
    final to = criterionText(
      km: _typedKm,
      months: _typedMonths,
      disabledKm: _kmOff && reminder.refIntervalKm != null,
      disabledMonths: _monthsOff && reminder.refIntervalMonths != null,
      l10n: l10n,
      units: _units,
    );
    return l10n.reminderOverrideSummary(from, to);
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = null);
    if (_kmOff && _monthsOff) {
      setState(() => _error = l10n.validationOneAxisRequired);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final anchorText = _anchorKm.text.trim();
    setState(() => _saving = true);
    final result = await ref
        .read(reminderActionsControllerProvider.notifier)
        .overrideCriterion(
          widget.reminder.id,
          appliedKm: _typedKm,
          appliedMonths: _typedMonths,
          reason: _reason.text,
          anchorKm: _needsAnchorKm && anchorText.isNotEmpty
              ? _units.distance.parse(anchorText)
              : null,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case ActionSuccess(:final value):
        Navigator.of(context).pop(value);
      case ActionFailure(:final error):
        setState(() => _error = error.message(l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    _units = unitFormatterOf(context, ref);
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.reminderActionCustomise),
      content: Form(
        key: _formKey,
        // The summary line follows every keystroke.
        onChanged: () => setState(() {}),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Context(() {
              final reminder = widget.reminder;
              final reference = criterionText(
                km: reminder.refIntervalKm,
                months: reminder.refIntervalMonths,
                sentence: false,
                l10n: l10n,
                units: _units,
              );
              return reminder.source == ReminderSource.generated
                  ? l10n.reminderManufacturerCriterion(reference)
                  : l10n.reminderReferenceLine(reference);
            }()),
            const SizedBox(height: 16),
            _AxisRow(
              switchKey: const ValueKey('override-km-off'),
              off: _kmOff,
              onChanged:
                  _saving ? null : (value) => setState(() => _kmOff = value),
              field: TextFormField(
                key: const ValueKey('override-km'),
                controller: _km,
                enabled: !_saving && !_kmOff,
                decoration: InputDecoration(
                  labelText: l10n.reminderFieldIntervalDistance,
                  suffixText: _units.distance.symbol,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (_kmOff) return null;
                  final km = _typedKm;
                  return km == null || km <= 0
                      ? l10n.validationWholeNumberAboveZero
                      : null;
                },
              ),
            ),
            if (_needsAnchorKm)
              TextFormField(
                key: const ValueKey('override-anchor-km'),
                controller: _anchorKm,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: l10n.reminderFieldAnchorDistance,
                  helperText: l10n.reminderAnchorKmNeededHelp,
                  helperMaxLines: 3,
                  suffixText: _units.distance.symbol,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) {
                    return l10n.validationReminderAnchorKmRequired;
                  }
                  final km = _units.distance.parse(text);
                  return km == null || km < 0 ? l10n.validationKmInvalid : null;
                },
              ),
            const SizedBox(height: 8),
            _AxisRow(
              switchKey: const ValueKey('override-months-off'),
              off: _monthsOff,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _monthsOff = value),
              field: TextFormField(
                key: const ValueKey('override-months'),
                controller: _months,
                enabled: !_saving && !_monthsOff,
                decoration: InputDecoration(
                  labelText: l10n.reminderFieldIntervalMonths,
                  suffixText: l10n.unitMonthsSuffix,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (_monthsOff) return null;
                  final months = _typedMonths;
                  return months == null || months <= 0
                      ? l10n.validationWholeNumberAboveZero
                      : null;
                },
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('override-reason'),
              controller: _reason,
              enabled: !_saving,
              decoration: InputDecoration(labelText: l10n.reminderReasonField),
              textCapitalization: TextCapitalization.sentences,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? l10n.validationReasonRequired
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              _summary(l10n),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            _errorText(context, _error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          child: Text(l10n.reminderActionCustomise),
        ),
      ],
    );
  }
}

/// The muted sentence of context at the top of a reminder dialog.
class _Context extends StatelessWidget {
  const _Context(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// One axis of the customise dialog: its [field] and, at the end, a "No
/// limit" switch that turns the axis off.
class _AxisRow extends StatelessWidget {
  const _AxisRow({
    required this.switchKey,
    required this.off,
    required this.onChanged,
    required this.field,
  });

  final Key switchKey;
  final bool off;
  final ValueChanged<bool>? onChanged;
  final Widget field;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: field),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.reminderDisableAxis, style: theme.textTheme.labelSmall),
            Switch(key: switchKey, value: off, onChanged: onChanged),
          ],
        ),
      ],
    );
  }
}
