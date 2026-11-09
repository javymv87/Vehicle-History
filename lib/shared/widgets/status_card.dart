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
/// decisive [value] as a hero figure, an optional grid of [facts] and an
/// optional muted [line] under it; or, with [StatusCard.twoAxes], two
/// columns side by side, each an axis with its value and what is left.
///
/// A detail that answers "what is this?" rather than "how is it?" (the
/// vehicle's odometer, an entry) leaves out the [tint], and the [word] and
/// [icon] with it: a plain card whose hero is in the normal colour. When
/// the hero is a text rather than a figure (an entry's description),
/// [textValue] sets it in `titleLarge`, so a long text does not dominate.
class StatusCard extends StatelessWidget {
  /// Creates the card with one hero [value].
  const StatusCard({
    super.key,
    this.tint,
    this.icon,
    this.word,
    required String this.value,
    this.textValue = false,
    this.facts = const [],
    this.line,
  })  : axes = null,
        assert(
          (icon == null) == (word == null),
          'The state word and its icon go together: never the colour alone',
        ),
        assert(
          tint == null || word != null,
          'A tinted card says its state in words',
        );

  /// Creates the card with two [axes] side by side.
  const StatusCard.twoAxes({
    super.key,
    required AppCardTint this.tint,
    required IconData this.icon,
    required String this.word,
    required List<StatusAxis> this.axes,
  })  : value = null,
        textValue = false,
        facts = const [],
        line = null;

  /// The state the card is tinted with; a plain card when `null`.
  final AppCardTint? tint;

  /// The icon of the state; none (with [word]) when `null`.
  final IconData? icon;

  /// The state word ("Overdue"); no state line when `null`.
  final String? word;

  /// The hero value; `null` in the two-axis variant.
  final String? value;

  /// Whether [value] is a text (`titleLarge`) rather than a figure
  /// (`headlineMedium`).
  final bool textValue;

  /// Rows of values under the hero, each row split in equal columns
  /// ("1 Oct 2026 | 10,600 km | €63.00"); a value carries its own unit, so
  /// no label repeats it. Empty rows are skipped.
  final List<List<String>> facts;

  /// The muted line under the hero value and the facts; none when `null`.
  final String? line;

  /// The two axes; `null` in the hero variant.
  final List<StatusAxis>? axes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = this.tint;
    final color = tint == null
        ? theme.colorScheme.onSurface
        : appCardTintColor(tint, theme);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final axes = this.axes;
    final line = this.line;
    final icon = this.icon;
    final word = this.word;
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
      final rows = [
        for (final row in facts)
          if (row.isNotEmpty) row,
      ];
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value!,
            style: (textValue
                    ? theme.textTheme.titleLarge
                    : theme.textTheme.headlineMedium)
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
          for (final (index, row) in rows.indexed) ...[
            SizedBox(height: index == 0 ? 12 : 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (column, fact) in row.indexed) ...[
                  if (column > 0) const SizedBox(width: 12),
                  Expanded(
                    child: Text(fact, style: theme.textTheme.titleMedium),
                  ),
                ],
                // A short row keeps the columns of the longest one.
                for (var i = row.length; i < _columnsOf(rows); i++) ...[
                  const SizedBox(width: 12),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ],
            ),
          ],
          if (line != null) ...[
            if (rows.isNotEmpty) const SizedBox(height: 8),
            Text(line, style: muted),
          ],
        ],
      );
    }
    return AppCard(
      tint: tint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null && word != null) ...[
            StateLine.heading(icon: icon, text: word, color: color),
            const SizedBox(height: 8),
          ],
          body,
        ],
      ),
    );
  }

  /// The number of columns of the widest row of [rows].
  static int _columnsOf(List<List<String>> rows) => rows.fold(
        0,
        (widest, row) => row.length > widest ? row.length : widest,
      );
}
