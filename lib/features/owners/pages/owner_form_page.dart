import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/router/navigation.dart';
import '../../../data/catalog/country_names.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/calendar_date.dart';
import '../../../data/models/owner.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/not_found_page.dart';
import '../../../shared/widgets/picker_form_field.dart';
import '../../../shared/widgets/searchable_picker.dart';
import '../../../shared/widgets/text_input_dialog.dart';
import '../controllers/owner_form_controller.dart';
import '../widgets/birth_date_field.dart';

/// Form that creates an owner (no [ownerId]) or edits one.
///
/// After a successful save it pops with the id of the saved owner, which is
/// how the vehicle form receives an owner created through "New owner".
class OwnerFormPage extends ConsumerWidget {
  /// Creates the form; [ownerId] is `null` to create a new owner.
  const OwnerFormPage({super.key, this.ownerId});

  /// Id of the owner to edit, from the path; `null` when creating.
  final String? ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final title = ownerId == null ? l10n.newOwnerTitle : l10n.editOwnerTitle;
    final initial = ref.watch(ownerFormControllerProvider(ownerId));
    return initial.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: MessageView(icon: Icons.error_outline, message: l10n.loadError),
      ),
      data: (owner) => ownerId != null && owner == null
          ? NotFoundPage(message: l10n.ownerNotFound)
          : _OwnerForm(ownerId: ownerId, initial: owner, title: title),
    );
  }
}

/// The owner form itself, holding the text being typed.
class _OwnerForm extends ConsumerStatefulWidget {
  const _OwnerForm({
    required this.ownerId,
    required this.initial,
    required this.title,
  });

  final String? ownerId;
  final Owner? initial;
  final String title;

  @override
  ConsumerState<_OwnerForm> createState() => _OwnerFormState();
}

class _OwnerFormState extends ConsumerState<_OwnerForm> {
  final _formKey = GlobalKey<FormState>();
  late final _firstName =
      TextEditingController(text: widget.initial?.firstName);
  late final _lastName = TextEditingController(text: widget.initial?.lastName);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _email = TextEditingController(text: widget.initial?.email);
  late final _notes = TextEditingController(text: widget.initial?.notes);
  late CalendarDate? _birthDate = widget.initial?.birthDate;

  /// Nationality as stored: an ISO 3166-1 alpha-2 code picked from the list,
  /// or free text typed through "Other…".
  late String? _nationality = widget.initial?.nationality;

  /// Whether a save is running; the save button is disabled meanwhile.
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _firstName,
      _lastName,
      _phone,
      _email,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Opens the nationality picker: a country from the list (stored as its
  /// ISO code) or, through "Other…", any text.
  Future<void> _pickNationality() async {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    CountryNames? countries;
    try {
      countries = await ref.read(countryNamesProvider.future);
    } on Exception {
      // The list helps, it never blocks: without it, only "Other…" remains.
      countries = null;
    }
    if (!mounted) return;
    final result = await showSearchablePicker<Country>(
      context: context,
      title: l10n.countryPickerTitle,
      search: (query) => countries?.search(query, language) ?? const [],
      labelOf: (country) => country.name,
      otherLabel: l10n.otherCountry,
    );
    if (!mounted || result == null) return;
    switch (result) {
      case Picked(:final value):
        setState(() => _nationality = value.code);
      case PickedOther(:final query):
        final current = _nationality;
        final typed = await showTextInputDialog(
          context,
          title: l10n.fieldNationality,
          initialText: query.isNotEmpty
              ? query
              : (current != null && countries?.nameOf(current, language) == null
                  ? current
                  : ''),
        );
        if (!mounted || typed == null) return;
        setState(() => _nationality = typed);
    }
  }

  /// Validates the fields and saves through the controller.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final result = await ref
        .read(ownerFormControllerProvider(widget.ownerId).notifier)
        .save(
          OwnerDraft(
            firstName: _firstName.text,
            lastName: _lastName.text,
            birthDate: _birthDate,
            nationality: _nationality,
            phone: _phone.text,
            email: _email.text,
            notes: _notes.text,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case ActionSuccess(:final value):
        showSavedSnackBar(messenger, l10n.ownerSaved);
        context.popOrGo(AppRoutes.owner(value.id), value.id);
      case ActionFailure(:final error):
        showErrorSnackBar(messenger, error.message(l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const gap = SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(l10n.actionSave),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _firstName,
              decoration: _decoration(l10n.fieldFirstName),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofocus: widget.initial == null,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? l10n.validationFirstNameRequired
                  : null,
            ),
            gap,
            TextFormField(
              controller: _lastName,
              decoration: _decoration(l10n.fieldLastName),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            gap,
            BirthDateField(
              value: _birthDate,
              onChanged: (date) => setState(() => _birthDate = date),
            ),
            gap,
            PickerFormField(
              key: const ValueKey('nationality-field'),
              label: l10n.fieldNationality,
              value: switch (_nationality) {
                null => null,
                final stored =>
                  ref.watch(countryNamesProvider).value?.displayNationality(
                            stored,
                            Localizations.localeOf(context).languageCode,
                          ) ??
                      stored,
              },
              onTap: _pickNationality,
              onClear: () => setState(() => _nationality = null),
            ),
            gap,
            TextFormField(
              controller: _phone,
              decoration: _decoration(l10n.fieldPhone),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            gap,
            TextFormField(
              controller: _email,
              decoration: _decoration(l10n.fieldEmail),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            gap,
            TextFormField(
              controller: _notes,
              decoration: _decoration(l10n.fieldNotes),
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 6,
            ),
          ],
        ),
      ),
    );
  }

  /// Outlined decoration with [label], shared by every text field.
  InputDecoration _decoration(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder());
}
