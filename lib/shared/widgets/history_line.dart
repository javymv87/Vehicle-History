import 'package:flutter/material.dart';

import 'action_label.dart';

/// One change in a folded history (`Docs/07_design_and_theming.md`,
/// "Colores de acción"): an [ActionLabel] with the action [word] in the
/// colour of its [meaning], then the [rest] of the line in the normal
/// colour and, at the end, an optional [parenthetical] in brackets.
/// Inset 16 dp at the sides and 12 dp below, as the rows of a history.
class HistoryLine extends StatelessWidget {
  /// Creates the line.
  const HistoryLine({
    super.key,
    required this.meaning,
    required this.icon,
    required this.word,
    this.rest = '',
    this.parenthetical,
    this.separator = ' · ',
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 12),
  });

  /// What the action means: decides the colour.
  final ActionMeaning meaning;

  /// The icon of the action.
  final IconData icon;

  /// The name of the action ("Postponed"), in colour.
  final String word;

  /// What follows the word, such as the day and the detail; may be empty.
  final String rest;

  /// A remark shown in brackets after [rest]; none when `null`.
  final String? parenthetical;

  /// Between [word] and [rest].
  final String separator;

  /// The insets of the line.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final parenthetical = this.parenthetical;
    final text = parenthetical == null
        ? rest
        : rest.isEmpty
            ? '($parenthetical)'
            : '$rest ($parenthetical)';
    return Padding(
      padding: padding,
      child: ActionLabel(
        meaning: meaning,
        icon: icon,
        word: word,
        rest: text,
        separator: separator,
      ),
    );
  }
}
