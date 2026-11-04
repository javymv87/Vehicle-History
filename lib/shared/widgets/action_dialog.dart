import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The dialog of one action (`Docs/07_design_and_theming.md`,
/// "Arquetipos"; `Docs/08_recordatorios.md`, "Diálogos"): the [title] is
/// the verb, an optional muted [contextLine] comes first, then the
/// [fields], the [reason] field last, an optional muted [note] under it
/// and the [error] of a refusal; the primary button repeats the verb
/// ([confirmLabel]) and the secondary one is Cancel.
///
/// The fields are wrapped in a [Form] keyed by [formKey], so the caller
/// validates them with it; [onFormChanged] follows every keystroke. The
/// spacing above the first field and between fields is the caller's (it
/// differs by dialog); the dialog adds 8 dp above [reason], 16 dp above
/// [note] and 16 dp above [error]. While [busy], both buttons are
/// disabled.
class ActionDialog extends StatelessWidget {
  /// Creates the dialog.
  const ActionDialog({
    super.key,
    required this.title,
    this.contextLine,
    this.formKey,
    this.onFormChanged,
    required this.fields,
    this.reason,
    this.note,
    this.error,
    required this.confirmLabel,
    required this.onConfirm,
    this.busy = false,
  });

  /// The verb of the action, as the title.
  final String title;

  /// The muted sentence of context at the top; none when `null`.
  final String? contextLine;

  /// The key of the [Form] around the fields.
  final GlobalKey<FormState>? formKey;

  /// Called by the [Form] on every change of a field.
  final VoidCallback? onFormChanged;

  /// The fields, with their spacing.
  final List<Widget> fields;

  /// The reason field, always last; none when `null`.
  final Widget? reason;

  /// A muted line after the fields, such as what the action changes.
  final String? note;

  /// The refusal shown under the fields; none when `null`.
  final String? error;

  /// The label of the primary button, the verb again.
  final String confirmLabel;

  /// Runs the action.
  final VoidCallback onConfirm;

  /// Whether the action is running: the buttons are disabled meanwhile.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final contextLine = this.contextLine;
    final reason = this.reason;
    final note = this.note;
    final error = this.error;
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Form(
        key: formKey,
        onChanged: onFormChanged,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (contextLine != null) Text(contextLine, style: muted),
            ...fields,
            if (reason != null) ...[const SizedBox(height: 8), reason],
            if (note != null) ...[
              const SizedBox(height: 16),
              Text(note, style: muted),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  error,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: busy ? null : onConfirm,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
