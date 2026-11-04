import 'package:flutter/material.dart';

import '../../app/theme/status_colors.dart';

/// How an [AppChip] is tinted.
enum AppChipVariant {
  /// The theme's neutral chip: `surfaceContainerHighest` with
  /// `onSurfaceVariant`.
  neutral,

  /// Something to look at: the due-soon amber at low opacity.
  warning,

  /// Plain information: the primary colour at low opacity.
  info,
}

/// A small chip beside a row or a card label ("Custom", "Postponed", "Less
/// strict"): `labelSmall` on a 8 dp-radius container, with an optional
/// leading [icon] described by [iconLabel] for screen readers.
class AppChip extends StatelessWidget {
  /// Creates the chip.
  const AppChip({
    super.key,
    required this.label,
    this.icon,
    this.iconLabel,
    this.variant = AppChipVariant.neutral,
  });

  /// The text of the chip.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// What [icon] means, for screen readers.
  final String? iconLabel;

  /// The tint of the chip.
  final AppChipVariant variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = this.icon;
    final (Color color, Color background) = switch (variant) {
      AppChipVariant.neutral => (
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.surfaceContainerHighest,
        ),
      AppChipVariant.warning =>
        _tinted(theme.extension<StatusColors>()!.dueSoon),
      AppChipVariant.info => _tinted(theme.colorScheme.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color, semanticLabel: iconLabel),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  /// [color] as the foreground over itself at 14 % opacity.
  static (Color, Color) _tinted(Color color) =>
      (color, color.withValues(alpha: 0.14));
}
