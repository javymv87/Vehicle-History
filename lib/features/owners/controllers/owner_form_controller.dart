import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/calendar_date.dart';
import '../../../data/models/owner.dart';
import '../../../shared/utils/action_result.dart';

/// The values typed into the owner form, before they are saved.
///
/// Text is passed as typed: the repository trims it and stores blank optional
/// fields as `null`.
class OwnerDraft {
  /// Creates a draft from the form fields.
  const OwnerDraft({
    required this.firstName,
    this.lastName,
    this.birthDate,
    this.nationality,
    this.phone,
    this.email,
    this.notes,
  });

  /// First name. Required.
  final String firstName;

  /// Last name.
  final String? lastName;

  /// Birth date chosen with the date picker.
  final CalendarDate? birthDate;

  /// Nationality.
  final String? nationality;

  /// Phone number.
  final String? phone;

  /// Email address.
  final String? email;

  /// Free notes.
  final String? notes;
}

/// State of the owner form: the owner being edited, or `null` when creating.
///
/// Loaded once when the form opens, so the fields do not change under the
/// user while they type. When editing an id that matches no live owner the
/// state is also `null`; the page tells the two cases apart by its id.
class OwnerFormController extends AsyncNotifier<Owner?> {
  /// Creates the controller for the owner with [ownerId], or for a new owner
  /// when it is `null`.
  OwnerFormController(this.ownerId);

  /// Id of the owner being edited; `null` when creating.
  final String? ownerId;

  @override
  Future<Owner?> build() async {
    final id = ownerId;
    if (id == null) return null;
    return ref.watch(ownerRepositoryProvider).getById(id);
  }

  /// Creates or updates the owner from [draft].
  ///
  /// Returns the saved owner, or the reason it was not saved.
  Future<ActionResult<Owner>> save(OwnerDraft draft) {
    final repository = ref.read(ownerRepositoryProvider);
    final id = ownerId;
    return runAction(
      () => id == null
          ? repository.create(
              firstName: draft.firstName,
              lastName: draft.lastName,
              birthDate: draft.birthDate,
              nationality: draft.nationality,
              phone: draft.phone,
              email: draft.email,
              notes: draft.notes,
            )
          : repository.update(
              id,
              firstName: draft.firstName,
              lastName: draft.lastName,
              birthDate: draft.birthDate,
              nationality: draft.nationality,
              phone: draft.phone,
              email: draft.email,
              notes: draft.notes,
              // The form has no photo field yet: keep the stored one.
              photoPath: state.value?.photoPath,
            ),
    );
  }
}

/// The [OwnerFormController] for an owner id (`null` to create one).
final ownerFormControllerProvider = AsyncNotifierProvider.autoDispose
    .family<OwnerFormController, Owner?, String?>(OwnerFormController.new);
