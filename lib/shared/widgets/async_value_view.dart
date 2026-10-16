import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

/// Builds the right widget for each state of an [AsyncValue].
///
/// While loading for the first time it shows a progress indicator; on error
/// a localised message. When the value reloads because the data changed, the
/// previous data stays on screen instead of flashing the indicator.
class AsyncValueView<T> extends StatelessWidget {
  /// Shows [value], building the data state with [data].
  const AsyncValueView({super.key, required this.value, required this.data});

  /// The state to show.
  final AsyncValue<T> value;

  /// Builds the widget for the loaded data.
  final Widget Function(T data) data;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnReload: true,
      data: data,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => MessageView(
        icon: Icons.error_outline,
        message: AppLocalizations.of(context).loadError,
      ),
    );
  }
}

/// A centred icon and message, optionally with an action button below.
///
/// Used for empty lists, not-found pages and load errors.
class MessageView extends StatelessWidget {
  /// Creates the view showing [icon] and [message].
  const MessageView({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  /// Icon above the message.
  final IconData icon;

  /// The message.
  final String message;

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
