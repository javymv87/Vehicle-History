import 'package:flutter/material.dart';

/// The small upper-case label of a card or of a value ("LAST TIME",
/// "BY KM"): `labelSmall`, letter-spacing 0.8, in `onSurfaceVariant`. It
/// names the question a card answers, never repeats what the value says
/// (`Docs/07_design_and_theming.md`, "Una tarjeta por pregunta").
///
/// With [trailing], the label fills the row and the trailing widget (such
/// as a chip) sits at its end.
class SectionLabel extends StatelessWidget {
  /// Creates the label for [text].
  const SectionLabel(this.text, {super.key, this.trailing});

  /// The label, shown upper case in the language of the app.
  final String text;

  /// Shown at the end of the row; the label alone when `null`.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailing = this.trailing;
    final label = Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
      ),
    );
    if (trailing == null) return label;
    return Row(children: [Expanded(child: label), trailing]);
  }
}
