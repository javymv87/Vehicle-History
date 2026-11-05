import 'package:flutter/material.dart';

/// One read-only field of a detail page: a small label above its value.
///
/// Optionally shows a [note] below the value, such as an explanation of how
/// the value can be changed. [DetailField.row] is the value row of an
/// archetype card (`Docs/07_design_and_theming.md`, "Arquetipos"): the
/// label muted at the start and the value at the end of one line.
class DetailField extends StatelessWidget {
  /// Creates a field showing [label] above [value].
  const DetailField({
    super.key,
    required this.label,
    required this.value,
    this.note,
  }) : inRow = false;

  /// Creates a value row: [label] muted at the start, [value] at the end,
  /// with no side padding, for use inside an `AppCard`. Long texts wrap on
  /// both sides.
  const DetailField.row({
    super.key,
    required this.label,
    required this.value,
  })  : note = null,
        inRow = true;

  /// Name of the field.
  final String label;

  /// Value of the field.
  final String value;

  /// Optional explanation under the value; never in a row.
  final String? note;

  /// Whether the label and the value share one line.
  final bool inRow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (inRow) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyLarge),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note!,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ],
      ),
    );
  }
}
