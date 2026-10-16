import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../l10n/app_localizations.dart';
import 'async_value_view.dart';

/// Full page shown when the item named in the path does not exist, or when
/// the path itself is unknown.
///
/// Never a crash: a deep link to a deleted vehicle ends up here.
class NotFoundPage extends StatelessWidget {
  /// Creates the page showing [message].
  const NotFoundPage({super.key, required this.message});

  /// What was not found.
  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notFoundTitle)),
      body: MessageView(
        icon: Icons.search_off,
        message: message,
        action: FilledButton.tonal(
          onPressed: () => context.go(AppRoutes.vehicles),
          child: Text(l10n.goToVehicles),
        ),
      ),
    );
  }
}
