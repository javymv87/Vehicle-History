import 'package:flutter/material.dart';

/// One row of an archetype list (`Docs/07_design_and_theming.md`,
/// "Arquetipos"): [leading] in a 40 dp circle, the [title], an optional
/// [secondLine] (usually a `StateLine`) and an optional muted [thirdLine],
/// and at the end the [trailing] widgets (chips) stacked and end-aligned.
/// At least 72 dp tall, 16 dp at the sides, no divider; tapping calls
/// [onTap].
class ListRow extends StatelessWidget {
  /// Creates the row.
  const ListRow({
    super.key,
    required this.leading,
    required this.title,
    this.secondLine,
    this.thirdLine,
    this.trailing = const [],
    this.onTap,
  });

  /// What goes in the leading circle, usually an icon.
  final Widget leading;

  /// The first line, in `bodyLarge`.
  final String title;

  /// The second line, such as the state in its colour.
  final Widget? secondLine;

  /// The third line, muted.
  final String? thirdLine;

  /// Chips stacked at the end of the row, 4 dp apart.
  final List<Widget> trailing;

  /// Called when the row is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondLine = this.secondLine;
    final thirdLine = this.thirdLine;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(radius: 20, child: leading),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyLarge),
                    if (secondLine != null) ...[
                      const SizedBox(height: 2),
                      secondLine,
                    ],
                    if (thirdLine != null)
                      Text(
                        thirdLine,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing.isNotEmpty) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (index, chip) in trailing.indexed) ...[
                      if (index > 0) const SizedBox(height: 4),
                      chip,
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
