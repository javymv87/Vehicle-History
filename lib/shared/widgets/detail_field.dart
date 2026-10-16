import 'package:flutter/material.dart';

/// One read-only field of a detail page: a small label above its value.
///
/// Optionally shows a [note] below the value, such as an explanation of how
/// the value can be changed.
class DetailField extends StatelessWidget {
  /// Creates a field showing [label] and [value].
  const DetailField({
    super.key,
    required this.label,
    required this.value,
    this.note,
  });

  /// Name of the field.
  final String label;

  /// Value of the field.
  final String value;

  /// Optional explanation under the value.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
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
