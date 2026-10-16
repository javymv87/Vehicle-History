import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../controllers/owner_list_controller.dart';
import '../widgets/owner_tile.dart';

/// The owner list, second destination of the navigation bar.
///
/// The "add" button is provided by the home shell.
class OwnerListPage extends ConsumerWidget {
  /// Creates the owner list page.
  const OwnerListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ownersTitle)),
      body: AsyncValueView(
        value: ref.watch(ownerListProvider),
        data: (owners) => owners.isEmpty
            ? MessageView(
                icon: Icons.people_outline,
                message: l10n.ownerListEmpty,
                action: FilledButton.icon(
                  onPressed: () => context.push(AppRoutes.newOwner),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addOwner),
                ),
              )
            : ListView.builder(
                // Room at the bottom so the last row clears the add button.
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: owners.length,
                itemBuilder: (context, index) {
                  final owner = owners[index];
                  return OwnerTile(
                    owner: owner,
                    onTap: () => context.push(AppRoutes.owner(owner.id)),
                  );
                },
              ),
      ),
    );
  }
}
