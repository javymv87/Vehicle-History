import 'package:flutter/material.dart';

/// One read-only value row of an archetype card
/// (`Docs/07_design_and_theming.md`, "Arquetipos"): the [label] muted at the
/// start and the [value] at the end of one line, with no side padding, for
/// use inside an `AppCard`. Long texts wrap on both sides.
class DetailField extends StatelessWidget {
  /// Creates the row showing [label] and [value].
  const DetailField.row({
    super.key,
    required this.label,
    required this.value,
  });

  /// Name of the field.
  final String label;

  /// Value of the field.
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
}
