import 'package:flutter/material.dart';

import 'app_card.dart';
import 'section_label.dart';
import 'state_line.dart';

/// One axis of a two-axis [StatusCard]: its label, its due value and what
/// is left.
class StatusAxis {
  /// Creates the axis.
  const StatusAxis({
    required this.label,
    required this.value,
    this.remaining,
  });

  /// The axis, shown as a small upper-case label ("BY KM").
  final String label;

  /// The due value, in `headlineSmall` and the state colour.
  final String value;

  /// What is left, muted; none when `null`.
  final String? remaining;
}

/// The card that answers "how is this?" (`Docs/07_design_and_theming.md`,
/// "Patrón para un estado: la tarjeta teñida"): an [AppCard] tinted with
/// the state, the state [word] with its [icon] on the first line, then the
/// decisive [value] as a hero figure with an optional muted [line] under
/// it; or, with [StatusCard.twoAxes], two columns side by side, each an
/// axis with its value and what is left.
class StatusCard extends StatelessWidget {
  /// Creates the card with one hero [value].
  const StatusCard({
    super.key,
    required this.tint,
    required this.icon,
    required this.word,
    required String this.value,
    this.line,
  }) : axes = null;

  /// Creates the card with two [axes] side by side.
  const StatusCard.twoAxes({
    super.key,
    required this.tint,
    required this.icon,
    required this.word,
    required List<StatusAxis> this.axes,
  })  : value = null,
        line = null;

  /// The state the card is tinted with.
  final AppCardTint tint;

  /// The icon of the state.
  final IconData icon;

  /// The state word ("Overdue").
  final String word;

  /// The hero value; `null` in the two-axis variant.
  final String? value;

  /// The muted line under the hero value; none when `null`.
  final String? line;

  /// The two axes; `null` in the hero variant.
  final List<StatusAxis>? axes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = appCardTintColor(tint, theme);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final axes = this.axes;
    final line = this.line;
    final Widget body;
    if (axes != null) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, axis) in axes.indexed) ...[
            if (index > 0) const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionLabel(axis.label),
                  Text(
                    axis.value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (axis.remaining case final remaining?)
                    Text(remaining, style: muted),
                ],
              ),
            ),
          ],
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value!,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (line != null) Text(line, style: muted),
        ],
      );
    }
    return AppCard(
      tint: tint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StateLine.heading(icon: icon, text: word, color: color),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}
