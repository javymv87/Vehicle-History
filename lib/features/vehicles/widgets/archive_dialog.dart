import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/archive_reason.dart';
import '../../../data/models/calendar_date.dart';
import '../../../data/models/mileage_reading.dart';
import '../../../data/models/vehicle.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../mileage/widgets/big_jump_confirmation.dart';
import '../controllers/vehicle_archive_controller.dart';

/// Opens the archive dialog of [vehicle] (`Docs/03_features.md`, "Archivo"):
/// reason, day, optional final km prefilled with [lastReading] and an
/// optional note. Resolves to the archived vehicle, or `null` when
/// cancelled.
///
/// The final km is an odometer reading: the dialog checks it as the "Update
/// km" form does (a whole number, not below the last reading, on a day
/// between the last reading and today), asks about a big jump, and shows
/// the repository's refusal inside the dialog, which stays open.
Future<Vehicle?> showArchiveDialog(
  BuildContext context, {
  required Vehicle vehicle,
  required MileageReading? lastReading,
}) {
  return showDialog<Vehicle>(
    context: context,
    builder: (context) =>
        _ArchiveDialog(vehicle: vehicle, lastReading: lastReading),
  );
}

/// The archive dialog itself, holding the values being typed.
class _ArchiveDialog extends ConsumerStatefulWidget {
  const _ArchiveDialog({required this.vehicle, required this.lastReading});

  final Vehicle vehicle;
  final MileageReading? lastReading;

  @override
  ConsumerState<_ArchiveDialog> createState() => _ArchiveDialogState();
}

class _ArchiveDialogState extends ConsumerState<_ArchiveDialog> {
  final _formKey = GlobalKey<FormState>();

  /// The reason, `none` until chosen.
  ArchiveReason _reason = ArchiveReason.none;

  /// The archive day, today by default.
  CalendarDate _date = calendarDateOf(DateTime.now());

  /// Prefilled with the last reading: archiving then records it again on
  /// the archive day, which marks the closing of the odometer history.
  late final _km = TextEditingController(
    text: widget.lastReading?.km.toString(),
  );

  final _note = TextEditingController();

  /// Shown under the date when it is out of range.
  String? _dateError;

  /// The repository's refusal, shown above the buttons.
  String? _error;

  /// Whether the archive is running; the buttons are disabled meanwhile.
  bool _saving = false;

  @override
  void dispose() {
    _km.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Today's calendar day on the phone.
  CalendarDate get _today => calendarDateOf(DateTime.now());

  /// The typed km, or `null` when the field is empty (no reading then).
  int? get _typedKm {
    final text = _km.text.trim();
    return text.isEmpty ? null : int.tryParse(text);
  }

  /// Opens the Material date picker, limited to today at the latest.
  Future<void> _pickDate() async {
    final last = _today.toLocalDateTime();
    var initial = _date.toLocalDateTime();
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: last,
    );
    if (picked != null && mounted) {
      setState(() {
        _date = calendarDateOf(picked);
        _dateError = null;
      });
    }
  }

  /// Checks the km as the reading form does: empty is allowed (no reading),
  /// otherwise a whole number ≥ 0 and not below the last reading.
  String? _validateKm(String? value, AppLocalizations l10n) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final km = int.tryParse(text);
    if (km == null || km < 0) return l10n.validationKmInvalid;
    final last = widget.lastReading;
    if (last != null && km < last.km) {
      return l10n.validationReadingKmBelowLast(last.km);
    }
    return null;
  }

  /// The date error, or `null`: never after today, and with a km, never
  /// before the last reading (the reading rule).
  String? _validateDate(AppLocalizations l10n) {
    final last = widget.lastReading;
    final withReading = _km.text.trim().isNotEmpty;
    final outOfRange = _date.isAfter(_today) ||
        (withReading && last != null && _date.isBefore(last.date));
    return outOfRange ? l10n.validationReadingDateOutOfRange : null;
  }

  /// Validates, asks about a big jump, and archives through the controller.
  Future<void> _archive() async {
    final l10n = AppLocalizations.of(context);
    final dateError = _validateDate(l10n);
    setState(() {
      _dateError = dateError;
      _error = null;
    });
    final fieldsValid = _formKey.currentState!.validate();
    if (!fieldsValid || dateError != null) return;

    final km = _typedKm;
    final last = widget.lastReading;
    if (km != null && last != null) {
      final confirmed =
          await confirmBigOdometerJump(context, km: km, lastKm: last.km);
      if (!confirmed || !mounted) return;
    }

    setState(() => _saving = true);
    final result =
        await ref.read(vehicleArchiveControllerProvider.notifier).archive(
              widget.vehicle.id,
              reason: _reason,
              date: _date,
              km: km,
              note: _note.text,
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
    final theme = Theme.of(context);
    final error = _error;
    return AlertDialog(
      // Long forms with very large text scroll instead of overflowing.
      scrollable: true,
      title: Text(l10n.archiveDialogTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.archiveDialogIntro),
            const SizedBox(height: 16),
            DropdownButtonFormField<ArchiveReason>(
              initialValue: _reason,
              decoration: InputDecoration(labelText: l10n.fieldArchiveReason),
              items: [
                for (final reason in ArchiveReason.values)
                  DropdownMenuItem(
                    value: reason,
                    child: Text(reason.label(l10n)),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (reason) => setState(() => _reason = reason!),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _saving ? null : _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.fieldArchiveDate,
                  errorText: _dateError,
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(l10n.dateValue(_date.toLocalDateTime())),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _km,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: l10n.fieldArchivedKm,
                helperText: l10n.archivedKmHelp,
                helperMaxLines: 3,
                suffixText: 'km',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) => _validateKm(value, l10n),
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _note,
              enabled: !_saving,
              decoration: InputDecoration(labelText: l10n.fieldArchiveNote),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              minLines: 1,
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(
                error,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _archive,
          child: Text(l10n.archiveAction),
        ),
      ],
    );
  }
}
