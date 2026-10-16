import 'package:flutter/material.dart';

/// A read-only form field that shows a chosen value and opens a picker when
/// tapped.
///
/// The value is owned by the parent, which passes it back as [value] and
/// validates it through [validator] (called with [value]). Looks like the
/// outlined text fields around it.
class PickerFormField extends StatelessWidget {
  /// Creates the field.
  const PickerFormField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.hint,
    this.validator,
    this.onClear,
    this.enabled = true,
  });

  /// Floating label, e.g. "Make".
  final String label;

  /// The chosen value as shown to the user; `null` when nothing is chosen.
  final String? value;

  /// Text shown while nothing is chosen.
  final String? hint;

  /// Opens the picker.
  final VoidCallback onTap;

  /// Checks [value] when the form is validated.
  final FormFieldValidator<String>? validator;

  /// When set and a value is chosen, a clear button calls it. For optional
  /// fields only.
  final VoidCallback? onClear;

  /// Whether the field can be tapped.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);
    final current = value;
    return FormField<String>(
      validator: validator == null ? null : (_) => validator!(value),
      builder: (state) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          isEmpty: current == null,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            enabled: enabled,
            border: const OutlineInputBorder(),
            errorText: state.errorText,
            suffixIcon: current != null && onClear != null
                ? IconButton(
                    tooltip: materialL10n.clearButtonTooltip,
                    icon: const Icon(Icons.clear),
                    onPressed: onClear,
                  )
                : const Icon(Icons.arrow_drop_down),
          ),
          child: current == null ? null : Text(current),
        ),
      ),
    );
  }
}
