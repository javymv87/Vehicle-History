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
/// Resolves to `true` only when the user taps the delete button.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.actionDelete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
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
