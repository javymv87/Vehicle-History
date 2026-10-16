import 'package:flutter/material.dart';

import '../../../data/models/owner.dart';
import '../../../l10n/app_localizations.dart';

/// Owner field of the vehicle form: a picker of the existing owners plus a
/// "New owner" entry that opens the owner form.
///
/// When no owner exists yet there is nothing to pick, so the field shows the
/// "New owner" button directly. Selection is owned by the parent, which
/// passes it back as [selectedOwnerId].
class OwnerPickerField extends StatelessWidget {
  /// Creates the field.
  const OwnerPickerField({
    super.key,
    required this.owners,
    required this.selectedOwnerId,
    required this.onSelected,
    required this.onNewOwner,
  });

  /// The live owners to pick from.
  final List<Owner> owners;

  /// Id of the selected owner, if any.
  final String? selectedOwnerId;

  /// Called when the user picks an existing owner.
  final ValueChanged<String> onSelected;

  /// Called when the user asks to create a new owner.
  final VoidCallback onNewOwner;

  /// Value of the "New owner" entry; no UUID can ever be equal to it.
  static const String _newOwnerValue = '#new-owner';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String? validate(String? _) =>
        selectedOwnerId == null ? l10n.validationOwnerRequired : null;

    if (owners.isEmpty) {
      return FormField<String>(
        validator: validate,
        builder: (state) => InputDecorator(
          decoration: InputDecoration(
            labelText: l10n.fieldOwner,
            border: const OutlineInputBorder(),
            errorText: state.errorText,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onNewOwner,
              icon: const Icon(Icons.person_add),
              label: Text(l10n.newOwnerTitle),
            ),
          ),
        ),
      );
    }

    // The new owner may not be in the list yet for a moment after it is
    // created; the dropdown must never be given a value it has no item for.
    final selected =
        owners.any((o) => o.id == selectedOwnerId) ? selectedOwnerId : null;
    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: l10n.fieldOwner,
        border: const OutlineInputBorder(),
      ),
      validator: validate,
      items: [
        for (final owner in owners)
          DropdownMenuItem(
            value: owner.id,
            child: Text(owner.fullName, overflow: TextOverflow.ellipsis),
          ),
        DropdownMenuItem(
          value: _newOwnerValue,
          child: Row(
            children: [
              const Icon(Icons.person_add),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  l10n.newOwnerTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        if (value == _newOwnerValue) {
          onNewOwner();
        } else {
          onSelected(value);
        }
      },
    );
  }
}
