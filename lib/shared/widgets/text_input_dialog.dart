import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Asks for one line of free text, such as a make that is not in the
/// catalogue.
///
/// Resolves to the trimmed text when the user confirms a non-blank value,
/// or `null` when they cancel. With [allowEmpty] (an optional value, such
/// as a caption) a blank value can be confirmed too, as `''`.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initialText = '',
  TextCapitalization textCapitalization = TextCapitalization.words,
  bool allowEmpty = false,
  String? label,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      initialText: initialText,
      textCapitalization: textCapitalization,
      allowEmpty: allowEmpty,
      label: label,
    ),
  );
}

/// The dialog of [showTextInputDialog], holding the text being typed.
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initialText,
    required this.textCapitalization,
    required this.allowEmpty,
    required this.label,
  });

  final String title;
  final String initialText;
  final TextCapitalization textCapitalization;
  final bool allowEmpty;
  final String? label;

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

  /// Closes with the trimmed text, unless it is blank and blank is not
  /// allowed.
  void _confirm() {
    final text = _text.text.trim();
    if (text.isEmpty && !widget.allowEmpty) return;
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
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
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
            onPressed: _text.text.trim().isEmpty && !widget.allowEmpty
                ? null
                : _confirm,
            child: Text(l10n.actionOk),
          ),
        ),
      ],
    );
  }
}
