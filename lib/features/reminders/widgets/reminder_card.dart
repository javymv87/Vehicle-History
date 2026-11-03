import 'package:flutter/material.dart';

/// The card of the reminder screens (`Docs/07_design_and_theming.md`: one
/// card per question): 16 dp radius on `surfaceContainer`, 16 dp inside,
/// with an optional small upper-case [label] above [child].
class ReminderCard extends StatelessWidget {
  /// Creates the card.
  const ReminderCard({
    super.key,
    this.label,
    this.trailing,
    required this.child,
  });

  /// What the card answers, shown small and upper case; none when `null`.
  final String? label;

  /// Shown at the end of the label row, such as a chip.
  final Widget? trailing;

  /// The content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = this.label;
    final trailing = this.trailing;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null || trailing != null) ...[
            Row(
              children: [
                Expanded(child: CardLabel(label ?? '')),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

/// The small upper-case label of a card or of a value ("LAST TIME").
class CardLabel extends StatelessWidget {
  /// Creates the label for [text].
  const CardLabel(this.text, {super.key});

  /// The label, shown upper case in the language of the app.
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
      ),
    );
  }
}
