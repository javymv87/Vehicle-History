import 'package:flutter/material.dart';

/// A line that says a state in its colour, always with an icon
/// (`Docs/07_design_and_theming.md`: never the colour alone): the icon,
/// then [text] in [color].
///
/// The default is the second line of a list row (16 dp icon, `bodyMedium`);
/// [StateLine.heading] is the first line of a status card (20 dp icon,
/// `titleSmall` at weight 600).
class StateLine extends StatelessWidget {
  /// Creates the line of a list row.
  const StateLine({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  })  : iconSize = 16,
        iconTopPadding = 1,
        gap = 4,
        heading = false;

  /// Creates the heading line of a status card.
  const StateLine.heading({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  })  : iconSize = 20,
        iconTopPadding = 0,
        gap = 8,
        heading = true;

  /// The icon of the state.
  final IconData icon;

  /// The state and whatever follows it on the line.
  final String text;

  /// The colour of the state, for the icon and the text.
  final Color color;

  /// The size of [icon].
  final double iconSize;

  /// Space above the icon, to centre a small icon on the first text line.
  final double iconTopPadding;

  /// Space between the icon and the text.
  final double gap;

  /// Whether the text is a heading (`titleSmall`, weight 600) rather than
  /// a row line (`bodyMedium`).
  final bool heading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = heading
        ? theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          )
        : theme.textTheme.bodyMedium?.copyWith(color: color);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: iconTopPadding),
          child: Icon(icon, size: iconSize, color: color),
        ),
        SizedBox(width: gap),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
