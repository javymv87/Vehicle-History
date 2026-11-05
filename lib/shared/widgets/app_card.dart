import 'package:flutter/material.dart';

import '../../app/theme/status_colors.dart';
import 'section_label.dart';

/// The state a card can be tinted with (`Docs/07_design_and_theming.md`,
/// "Patrón para un estado: la tarjeta teñida"): the three deadline states
/// of [StatusColors], or a neutral tint for something settled, such as a
/// completed reminder.
enum AppCardTint {
  /// Nothing pending: the ok green.
  ok,

  /// Approaching: the due-soon amber.
  dueSoon,

  /// Already passed: the overdue red.
  overdue,

  /// Settled, with no urgency: `onSurfaceVariant`.
  neutral,
}

/// The foreground colour of [tint] in [theme]: the colour of its text and
/// icons, from which [AppCard] derives the container and the outline.
Color appCardTintColor(AppCardTint tint, ThemeData theme) {
  final status = theme.extension<StatusColors>()!;
  return switch (tint) {
    AppCardTint.ok => status.ok,
    AppCardTint.dueSoon => status.dueSoon,
    AppCardTint.overdue => status.overdue,
    AppCardTint.neutral => theme.colorScheme.onSurfaceVariant,
  };
}

/// The card of the archetype screens (`Docs/07_design_and_theming.md`, "Una
/// tarjeta por pregunta" and "Arquetipos"): 16 dp radius, 16 dp inside,
/// on `surfaceContainer`; with a [tint], the state colour at low opacity as
/// the container (10 %) and the outline (35 %), the text and icons in the
/// colour itself.
///
/// An optional small upper-case [label] names the question the card
/// answers, with [trailing] (such as a chip) at the end of its row; [gap]
/// separates that row from [child]. The child is stretched to the card's
/// width. [padding] is 16 dp all round; a card holding a full-width row
/// (a `ListRow`, a `ListTile`) passes less, and the row's ink stays inside
/// the rounded card.
class AppCard extends StatelessWidget {
  /// Creates the card.
  const AppCard({
    super.key,
    this.label,
    this.trailing,
    this.tint,
    this.gap = 8,
    this.padding = const EdgeInsets.all(16),
    required this.child,
  });

  /// What the card answers, shown small and upper case; none when `null`.
  final String? label;

  /// Shown at the end of the label row, such as a chip.
  final Widget? trailing;

  /// The state the card is tinted with; a plain card when `null`.
  final AppCardTint? tint;

  /// Space between the label row and [child], when there is a label row.
  final double gap;

  /// Space between the card's edge and its content.
  final EdgeInsetsGeometry padding;

  /// The content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = this.label;
    final trailing = this.trailing;
    final tint = this.tint;
    final BoxDecoration decoration;
    if (tint == null) {
      decoration = BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      );
    } else {
      final color = appCardTintColor(tint, theme);
      decoration = BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(16),
      );
    }
    return Container(
      padding: padding,
      decoration: decoration,
      // Rows with ink inside (a tappable `ListRow`) are clipped to the card.
      clipBehavior: Clip.antiAlias,
      // A transparent Material, so that the ink of a tappable row paints
      // above the card's colour instead of under it.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (label != null || trailing != null) ...[
              SectionLabel(label ?? '', trailing: trailing),
              SizedBox(height: gap),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
