import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Asks for one line of free text, such as a make that is not in the
/// catalogue.
///
/// Resolves to the trimmed text when the user confirms a non-blank value,
/// or `null` when they cancel.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initialText = '',
  TextCapitalization textCapitalization = TextCapitalization.words,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      initialText: initialText,
      textCapitalization: textCapitalization,
    ),
  );
}

/// The dialog of [showTextInputDialog], holding the text being typed.
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initialText,
    required this.textCapitalization,
  });

  final String title;
  final String initialText;
  final TextCapitalization textCapitalization;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final _text = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Closes with the trimmed text, unless it is blank.
  void _confirm() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        textCapitalization: widget.textCapitalization,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        ListenableBuilder(
          listenable: _text,
          builder: (context, _) => TextButton(
            onPressed: _text.text.trim().isEmpty ? null : _confirm,
            child: Text(l10n.actionOk),
          ),
        ),
      ],
    );
  }
}
