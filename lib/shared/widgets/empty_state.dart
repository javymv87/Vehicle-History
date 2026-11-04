import 'package:flutter/material.dart';

/// A centred icon and message, optionally with a muted [detail] line and
/// an action button below (`Docs/07_design_and_theming.md`, "Arquetipos").
///
/// Used for empty lists, not-found pages and load errors.
class EmptyState extends StatelessWidget {
  /// Creates the view showing [icon] and [message].
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.detail,
    this.action,
  });

  /// Icon above the message.
  final IconData icon;

  /// The message.
  final String message;

  /// Optional muted line under the message.
  final String? detail;

  /// Optional button below the message.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable so that very large system text never overflows.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (detail case final detail?) ...[
              const SizedBox(height: 4),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
