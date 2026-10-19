import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

// Feedback helpers implementing the toast rules of `Docs/03_features.md`:
// brief confirmation on save, Undo for a few seconds on delete, explicit and
// long-lasting messages on error.

/// How long the brief "saved" confirmation stays on screen.
const Duration savedSnackBarDuration = Duration(seconds: 2);

/// How long the "Undo" action stays available after a delete.
const Duration undoSnackBarDuration = Duration(seconds: 6);

/// How long an error message stays on screen unless closed earlier.
const Duration errorSnackBarDuration = Duration(seconds: 10);

/// Shows the brief confirmation [message] after a save.
void showSavedSnackBar(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: savedSnackBarDuration),
    );
}

/// Shows [message] after a delete, with an "Undo" action that calls [onUndo].
///
/// [messenger] must be the app-wide messenger captured before the page that
/// deleted the item is popped, so the snackbar survives the navigation.
void showUndoSnackBar(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  String message, {
  required VoidCallback onUndo,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: undoSnackBarDuration,
        // A snackbar with an action persists by default; this one must
        // disappear once the undo window is over.
        persist: false,
        action: SnackBarAction(label: l10n.actionUndo, onPressed: onUndo),
      ),
    );
}

/// Shows an error [message] long enough to be read, with a close button.
void showErrorSnackBar(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: errorSnackBarDuration,
        showCloseIcon: true,
      ),
    );
}

/// Asks the user to confirm a delete.
///
/// Resolves to `true` only when the user taps the delete button, which is
/// drawn in the error colour like every destructive action (U19).
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return confirmAction(
    context,
    title: title,
    message: message,
    confirmLabel: AppLocalizations.of(context).actionDelete,
    destructive: true,
  );
}

/// Shows an explicit, blocking explanation that stays until dismissed.
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionOk),
        ),
      ],
    ),
  );
}

/// How long an offer, such as "Update the odometer?", stays on screen.
const Duration offerSnackBarDuration = Duration(seconds: 8);

/// Shows [message] with one action, [actionLabel], that calls [onAction].
///
/// For an optional next step offered after a save (`Docs/03_features.md`,
/// E3): it disappears on its own and nothing happens if it is ignored.
void showOfferSnackBar(
  ScaffoldMessengerState messenger,
  String message, {
  required String actionLabel,
  required VoidCallback onAction,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: offerSnackBarDuration,
        // A snackbar with an action persists by default; an offer must not.
        persist: false,
        action: SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
}

/// Asks the user to confirm an action, such as a very large odometer jump
/// that looks wrong but is allowed, or a permanent delete.
///
/// Resolves to `true` only when the user taps [confirmLabel]; cancel is the
/// safe default. When [destructive] is true, [confirmLabel] is drawn in the
/// error colour (U19).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final errorColor = Theme.of(context).colorScheme.error;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      // Long messages with very large text scroll instead of overflowing.
      scrollable: true,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        TextButton(
          style: destructive
              ? TextButton.styleFrom(foregroundColor: errorColor)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
