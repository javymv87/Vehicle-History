import 'package:flutter/widgets.dart';

import '../../../data/models/odometer_checks.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/unit_formatter.dart';
import '../../../shared/widgets/feedback.dart';

/// Asks "are you sure?" before saving a reading of [km] far above the last
/// reading, [lastKm] (`Docs/04_maintenance_logic.md`: a probable typo is
/// confirmed, never refused).
///
/// Resolves to `true` without asking when the jump is not big, so callers
/// can always await it before saving. [km] and [lastKm] are in km, as the
/// rule compares them; the message shows the difference and the friendly
/// threshold in the unit of [units].
Future<bool> confirmBigOdometerJump(
  BuildContext context, {
  required UnitFormatter units,
  required double km,
  required double lastKm,
}) async {
  if (!isBigOdometerJump(km: km, lastKm: lastKm)) return true;
  final l10n = AppLocalizations.of(context);
  return confirmAction(
    context,
    title: l10n.bigJumpTitle,
    message: l10n.bigJumpMessage(
      units.distance.format(km - lastKm),
      units.bigOdometerJumpThreshold,
    ),
    confirmLabel: l10n.actionSaveAnyway,
  );
}
