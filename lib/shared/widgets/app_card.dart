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
///
/// An [action] is a 40 dp icon button at the end of the label row ("add"
/// on the attachments card). It does not make the row taller: the button
/// reaches into the card's top padding and the gap, so the label and the
/// content sit where they sit on a card without one, and its icon lines up
/// with the end of the content.
class AppCard extends StatelessWidget {
  /// Creates the card.
  const AppCard({
    super.key,
    this.label,
    this.trailing,
    this.tint,
    this.gap = 8,
    this.padding = const EdgeInsets.all(16),
    this.action,
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

  /// The icon button at the end of the label row; none when `null`.
  final AppCardAction? action;

  /// The content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = this.label;
    final trailing = this.trailing;
    final tint = this.tint;
    final action = this.action;
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
    final resolved = padding.resolve(Directionality.of(context));
    final Widget? labelRow;
    if (action != null) {
      // Room at the end of the label for the button laid over it, so a
      // long label never runs under the icon.
      labelRow = SectionLabel(
        label ?? '',
        trailing: const SizedBox(
          width: AppCardAction.size - AppCardAction.inset,
          height: _labelLineHeight,
        ),
      );
    } else if (label != null || trailing != null) {
      labelRow = SectionLabel(label ?? '', trailing: trailing);
    } else {
      labelRow = null;
    }
    final Widget content = Padding(
      padding: resolved,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (labelRow != null) ...[
            labelRow,
            SizedBox(height: gap),
          ],
          child,
        ],
      ),
    );
    return Container(
      decoration: decoration,
      // Rows with ink inside (a tappable `ListRow`) are clipped to the card.
      clipBehavior: Clip.antiAlias,
      // A transparent Material, so that the ink of a tappable row paints
      // above the card's colour instead of under it.
      child: Material(
        type: MaterialType.transparency,
        child: action == null
            ? content
            : Stack(
                children: [
                  content,
                  // The 40 dp button is laid over the label row, centred on
                  // the label line: it reaches into the top padding and
                  // the gap, so the label and the content stay where they
                  // are on a card without one, and its 24 dp icon ends
                  // where the content ends.
                  PositionedDirectional(
                    top: resolved.top -
                        (AppCardAction.size - _labelLineHeight) / 2,
                    end: (Directionality.of(context) == TextDirection.rtl
                            ? resolved.left
                            : resolved.right) -
                        AppCardAction.inset,
                    child: IconButton(
                      tooltip: action.tooltip,
                      onPressed: action.onPressed,
                      icon: Icon(action.icon),
                      padding: EdgeInsets.zero,
                      // 40 dp, not the 48 dp Material pads a button to.
                      style: const ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      constraints: const BoxConstraints.tightFor(
                        width: AppCardAction.size,
                        height: AppCardAction.size,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The height of one [SectionLabel] line at the default text size, from
/// which an [AppCardAction] is centred on it.
const double _labelLineHeight = 16;

/// The icon button at the end of an [AppCard]'s label row: an [icon], what
/// it does for screen readers and on long press ([tooltip]), and what it
/// runs ([onPressed]).
class AppCardAction {
  /// Creates the action.
  const AppCardAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  /// The size of the button, square.
  static const double size = 40;

  /// The space between the button's edge and its 24 dp icon.
  static const double inset = (size - 24) / 2;

  /// The icon, such as `Icons.add`.
  final IconData icon;

  /// What the button does ("Add attachment").
  final String tooltip;

  /// Runs the action.
  final VoidCallback onPressed;
}
