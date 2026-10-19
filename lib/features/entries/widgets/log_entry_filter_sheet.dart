import 'package:flutter/material.dart';

import '../../../data/models/calendar_date.dart';
import '../../../data/models/log_entry_filter.dart';
import '../../../data/models/log_entry_type.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import 'log_entry_type_icon.dart';

/// Opens the history filters in a bottom sheet, starting from [current].
///
/// Resolves to the filter to apply, or `null` when the sheet is dismissed
/// without "Apply" (nothing changes then).
Future<LogEntryFilter?> showLogEntryFilterSheet(
  BuildContext context,
  LogEntryFilter current,
) {
  return showModalBottomSheet<LogEntryFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _FilterSheet(initial: current),
  );
}

/// The content of the filter sheet: date range, types and text.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});

  final LogEntryFilter initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late CalendarDate? _from = widget.initial.from;
  late CalendarDate? _to = widget.initial.to;
  late final Set<LogEntryType> _types = {...widget.initial.types};
  late final _text = TextEditingController(text: widget.initial.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Opens the Material date range picker on the current range.
  Future<void> _pickDates() async {
    final from = _from;
    final to = _to;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      initialDateRange: from != null && to != null
          ? DateTimeRange(
              start: from.toLocalDateTime(),
              end: to.toLocalDateTime(),
            )
          : null,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = calendarDateOf(picked.start);
      _to = calendarDateOf(picked.end);
    });
  }

  /// Closes the sheet with the chosen filter.
  void _apply() {
    Navigator.of(context).pop(
      LogEntryFilter(
        from: _from,
        to: _to,
        types: Set.unmodifiable(_types),
        text: _text.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final from = _from;
    final to = _to;
    final hasDates = from != null || to != null;
    // Padding for the keyboard, so the text field and Apply stay visible.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.filtersTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text(l10n.filterDates, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    hasDates
                        ? l10n.dateRangeValue(
                            (from ?? to)!.toLocalDateTime(),
                            (to ?? from)!.toLocalDateTime(),
                          )
                        : l10n.filterAnyDate,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                if (hasDates)
                  IconButton(
                    tooltip: l10n.filterClearDates,
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _from = _to = null),
                  ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: _pickDates,
                icon: const Icon(Icons.date_range),
                label: Text(l10n.filterChooseDates),
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.filterTypes, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final type in LogEntryType.selectable)
                  FilterChip(
                    avatar: Icon(type.icon),
                    label: Text(type.label(l10n)),
                    selected: _types.contains(type),
                    // The avatar already identifies the type; the check mark
                    // would replace it.
                    showCheckmark: false,
                    onSelected: (selected) => setState(() {
                      selected ? _types.add(type) : _types.remove(type);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              decoration: InputDecoration(
                labelText: l10n.filterText,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _apply(),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _apply, child: Text(l10n.filterApply)),
          ],
        ),
      ),
    );
  }
}
