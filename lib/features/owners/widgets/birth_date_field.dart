import 'package:flutter/material.dart';

import '../../../data/models/calendar_date.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/calendar_date_conversion.dart';

/// Optional birth date field: shows the date formatted for the locale and
/// opens the Material date picker when tapped.
class BirthDateField extends StatelessWidget {
  /// Creates the field showing [value]; [onChanged] receives the new date,
  /// or `null` when the user clears it.
  const BirthDateField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// The selected date, if any.
  final CalendarDate? value;

  /// Called with the picked date, or `null` when cleared.
  final ValueChanged<CalendarDate?> onChanged;

  /// Earliest selectable birth date.
  static final DateTime _firstDate = DateTime(1900);

  /// Opens the date picker and reports the picked day.
  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: value?.toLocalDateTime() ?? today,
      firstDate: _firstDate,
      lastDate: today,
      // Birth dates are usually decades back: start from the year grid.
      initialDatePickerMode:
          value == null ? DatePickerMode.year : DatePickerMode.day,
    );
    if (picked != null) onChanged(calendarDateOf(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final date = value;
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.fieldBirthDate,
          border: const OutlineInputBorder(),
          suffixIcon: date == null
              ? const Icon(Icons.calendar_today)
              : IconButton(
                  tooltip: l10n.birthDateClear,
                  icon: const Icon(Icons.clear),
                  onPressed: () => onChanged(null),
                ),
        ),
        child: Text(
          date == null
              ? l10n.birthDatePick
              : l10n.dateValue(date.toLocalDateTime()),
        ),
      ),
    );
  }
}
