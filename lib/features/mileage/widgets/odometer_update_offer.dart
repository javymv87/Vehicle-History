import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/calendar_date.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/feedback.dart';
import '../controllers/odometer_update_offer_controller.dart';
import 'big_jump_confirmation.dart';

/// Shows the offer to update the odometer to [km] after an entry was saved
/// (`Docs/03_features.md`, E3), replacing the plain "Entry saved".
///
/// Tapping "Update" adds a reading with the entry's [date] and [km] through
/// [offer], after the big-jump confirmation against [currentKm] when it
/// applies. The entry form is gone by then, so every dependency is captured
/// before it pops: the app-wide [messenger], [router] (whose navigator
/// shows the confirmation dialog) and the kept-alive [offer] controller.
void showOdometerUpdateOffer({
  required ScaffoldMessengerState messenger,
  required GoRouter router,
  required AppLocalizations l10n,
  required OdometerUpdateOfferController offer,
  required String vehicleId,
  required CalendarDate date,
  required int km,
  required int currentKm,
}) {
  showOfferSnackBar(
    messenger,
    l10n.updateOdometerOffer(km),
    actionLabel: l10n.actionUpdate,
    onAction: () async {
      final dialogContext =
          router.routerDelegate.navigatorKey.currentState?.overlay?.context;
      if (dialogContext == null || !dialogContext.mounted) return;
      final confirmed = await confirmBigOdometerJump(
        dialogContext,
        km: km,
        lastKm: currentKm,
      );
      if (!confirmed) return;
      final result =
          await offer.accept(vehicleId: vehicleId, date: date, km: km);
      switch (result) {
        case ActionSuccess():
          showSavedSnackBar(messenger, l10n.readingSaved);
        case ActionFailure(:final error):
          showErrorSnackBar(messenger, error.message(l10n));
      }
    },
  );
}
