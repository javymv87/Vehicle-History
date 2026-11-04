import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'empty_state.dart';

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
      error: (error, stackTrace) => EmptyState(
        icon: Icons.error_outline,
        message: AppLocalizations.of(context).loadError,
      ),
    );
  }
}
