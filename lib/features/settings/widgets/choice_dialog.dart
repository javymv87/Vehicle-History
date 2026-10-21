import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Shows a dialog titled [title] with one radio button per option, the
/// [selected] one checked.
///
/// Tapping an option closes the dialog with it; Cancel, Back or a tap
/// outside close it with `null`. The options scroll when they do not fit,
/// such as with large text on a small phone.
Future<T?> showChoiceDialog<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required T selected,
  required String Function(T option) labelOf,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => _ChoiceDialog<T>(
      title: title,
      options: options,
      selected: selected,
      labelOf: labelOf,
    ),
  );
}

/// The dialog of [showChoiceDialog].
class _ChoiceDialog<T> extends StatelessWidget {
  /// Creates the dialog.
  const _ChoiceDialog({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelOf,
  });

  /// Dialog title, the name of the setting.
  final String title;

  /// The values offered, in order.
  final List<T> options;

  /// The current value, checked when the dialog opens.
  final T selected;

  /// Label of an option.
  final String Function(T option) labelOf;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(title),
      // The list tiles bring their own horizontal padding.
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SingleChildScrollView(
        child: RadioGroup<T>(
          groupValue: selected,
          onChanged: (value) => Navigator.of(context).pop(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                RadioListTile<T>(value: option, title: Text(labelOf(option))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
      ],
    );
  }
}
