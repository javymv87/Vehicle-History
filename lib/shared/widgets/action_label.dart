import 'package:flutter/material.dart';

import '../../app/theme/status_colors.dart';

/// What an action means, which decides its colour across the app
/// (`Docs/07_design_and_theming.md`, "Colores de acción"): an action is
/// painted by its meaning, never by its name.
enum ActionMeaning {
  /// Something comes into being: created, loaded from the manual. Primary.
  born,

  /// Something is fulfilled or comes back: closed, marked done, completed,
  /// restored from the Trash. The green of "up to date".
  fulfilled,

  /// Something is put off: postponed, postponement removed. The amber of
  /// "due soon".
  deferred,

  /// The rule changes: customised, reference restored, edited. Tertiary.
  ruleChanged,

  /// Something goes away: deleted. Error.
  gone,
}

/// The colour of [meaning] in [theme].
Color actionColor(ActionMeaning meaning, ThemeData theme) {
  final scheme = theme.colorScheme;
  final status = theme.extension<StatusColors>()!;
  return switch (meaning) {
    ActionMeaning.born => scheme.primary,
    ActionMeaning.fulfilled => status.ok,
    ActionMeaning.deferred => status.dueSoon,
    ActionMeaning.ruleChanged => scheme.tertiary,
    ActionMeaning.gone => scheme.error,
  };
}

/// One action in a line: its [icon] and its [word] in the colour of its
/// [meaning] and a medium weight, then the [rest] of the line in the normal
/// text colour, joined by [separator]. Never the colour alone.
class ActionLabel extends StatelessWidget {
  /// Creates the label.
  const ActionLabel({
    super.key,
    required this.meaning,
    required this.icon,
    required this.word,
    this.rest = '',
    this.separator = ' · ',
    this.style,
  });

  /// What the action means: decides the colour.
  final ActionMeaning meaning;

  /// The icon of the action.
  final IconData icon;

  /// The name of the action ("Postponed"), in colour.
  final String word;

  /// What follows the word, such as the day and the detail; may be empty.
  final String rest;

  /// Between [word] and [rest].
  final String separator;

  /// The text style of the line; `bodyMedium` when `null`.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = actionColor(meaning, theme);
    final base = style ?? theme.textTheme.bodyMedium;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: base,
              children: [
                TextSpan(
                  text: word,
                  style: TextStyle(color: color, fontWeight: FontWeight.w500),
                ),
                if (rest.isNotEmpty) TextSpan(text: '$separator$rest'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
