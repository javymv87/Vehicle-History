import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/catalog/vehicle_catalog.dart';
import '../../../data/data_providers.dart';
import '../../../data/models/fuel_type.dart';
import '../../../data/models/vehicle.dart';
import '../../../data/models/vehicle_kind.dart';
import '../../../shared/utils/action_result.dart';

/// What the vehicle is: kind, make and model, as chosen in the form.
///
/// Immutable; every change returns a new value and applies the picker rules
/// of `Docs/03_features.md`: changing the kind clears make and model (the
/// catalogue lists differ per kind), and changing the make clears the model.
/// A make or model typed by hand has no slug.
class VehicleIdentity {
  /// Creates an identity. Normally built by [VehicleIdentity.of] and the
  /// `with…` methods.
  const VehicleIdentity({
    required this.kind,
    this.make,
    this.makeSlug,
    this.model,
    this.modelSlug,
  });

  /// The identity of [vehicle], or an empty car when creating.
  factory VehicleIdentity.of(Vehicle? vehicle) => vehicle == null
      ? const VehicleIdentity(kind: VehicleKind.car)
      : VehicleIdentity(
          kind: vehicle.kind,
          make: vehicle.make,
          makeSlug: vehicle.makeSlug,
          model: vehicle.model,
          modelSlug: vehicle.modelSlug,
        );

  /// The vehicle kind.
  final VehicleKind kind;

  /// Make name as shown; `null` until chosen.
  final String? make;

  /// Catalogue id of [make]; `null` when typed by hand or not chosen.
  final String? makeSlug;

  /// Model name as shown; `null` until chosen.
  final String? model;

  /// Catalogue id of [model]; `null` when typed by hand or not chosen.
  final String? modelSlug;

  /// Whether the make comes from the catalogue, so the model can be picked
  /// from that make's list. With a typed make, the model is typed too.
  bool get hasCatalogMake => makeSlug != null;

  /// Switches to [kind]. A different kind clears make and model.
  VehicleIdentity withKind(VehicleKind kind) =>
      kind == this.kind ? this : VehicleIdentity(kind: kind);

  /// Picks [make] from the catalogue. A different make clears the model.
  VehicleIdentity withCatalogMake(CatalogMake make) => make.slug == makeSlug
      ? this
      : VehicleIdentity(kind: kind, make: make.name, makeSlug: make.slug);

  /// Sets a make typed by hand. A different make clears the model.
  VehicleIdentity withCustomMake(String name) {
    final clean = name.trim();
    if (makeSlug == null && clean == make) return this;
    return VehicleIdentity(kind: kind, make: clean);
  }

  /// Picks [model] from the catalogue list of the current make.
  VehicleIdentity withCatalogModel(CatalogModel model) => VehicleIdentity(
        kind: kind,
        make: make,
        makeSlug: makeSlug,
        model: model.name,
        modelSlug: model.slug,
      );

  /// Sets a model typed by hand; blank clears it.
  VehicleIdentity withCustomModel(String name) {
    final clean = name.trim();
    return VehicleIdentity(
      kind: kind,
      make: make,
      makeSlug: makeSlug,
      model: clean.isEmpty ? null : clean,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VehicleIdentity &&
      other.kind == kind &&
      other.make == make &&
      other.makeSlug == makeSlug &&
      other.model == model &&
      other.modelSlug == modelSlug;

  @override
  int get hashCode => Object.hash(kind, make, makeSlug, model, modelSlug);

  @override
  String toString() => 'VehicleIdentity(${kind.name}, $make [$makeSlug], '
      '$model [$modelSlug])';
}

/// The values typed into the vehicle form, before they are saved.
///
/// Text is passed as typed: the repository trims it, upper-cases the plate
/// and stores blank optional fields as `null`.
class VehicleDraft {
  /// Creates a draft from the form fields.
  const VehicleDraft({
    required this.plate,
    required this.identity,
    this.modelYear,
    this.version,
    this.nickname,
    required this.ownerId,
    required this.fuelType,
    this.currentOdometerKm,
    this.recommendedEngineOil,
    this.manufacturerNotes,
  });

  /// Licence plate. Required.
  final String plate;

  /// Kind, make and model.
  final VehicleIdentity identity;

  /// Optional model year.
  final int? modelYear;

  /// Optional version and trim.
  final String? version;

  /// Optional friendly name.
  final String? nickname;

  /// Id of the selected owner.
  final String ownerId;

  /// Selected fuel type.
  final FuelType fuelType;

  /// Current odometer reading. Required when creating, ignored when editing:
  /// after creation it changes only through the odometer feature.
  final double? currentOdometerKm;

  /// Engine oil recommended by the manufacturer.
  final String? recommendedEngineOil;

  /// Other manufacturer notes.
  final String? manufacturerNotes;
}

/// State of the vehicle form: the vehicle being edited, or `null` when
/// creating.
///
/// Loaded once when the form opens, so the fields do not change under the
/// user while they type. When editing an id that matches no live vehicle the
/// state is also `null`; the page tells the two cases apart by its id.
class VehicleFormController extends AsyncNotifier<Vehicle?> {
  /// Creates the controller for the vehicle with [vehicleId], or for a new
  /// vehicle when it is `null`.
  VehicleFormController(this.vehicleId);

  /// Id of the vehicle being edited; `null` when creating.
  final String? vehicleId;

  @override
  Future<Vehicle?> build() async {
    final id = vehicleId;
    if (id == null) return null;
    return ref.watch(vehicleRepositoryProvider).getById(id);
  }

  /// Creates or updates the vehicle from [draft].
  ///
  /// Returns the saved vehicle, or the reason it was not saved (for example
  /// [ActionError.duplicatePlate]).
  Future<ActionResult<Vehicle>> save(VehicleDraft draft) {
    final repository = ref.read(vehicleRepositoryProvider);
    final id = vehicleId;
    final identity = draft.identity;
    return runAction(() {
      if (id != null) {
        return repository.update(
          id,
          plate: draft.plate,
          kind: identity.kind,
          make: identity.make,
          makeSlug: identity.makeSlug,
          model: identity.model,
          modelSlug: identity.modelSlug,
          modelYear: draft.modelYear,
          version: draft.version,
          nickname: draft.nickname,
          ownerId: draft.ownerId,
          fuelType: draft.fuelType,
          recommendedEngineOil: draft.recommendedEngineOil,
          manufacturerNotes: draft.manufacturerNotes,
          // The form has no photo field yet: keep the stored one.
          photoPath: state.value?.photoPath,
        );
      }
      final km = draft.currentOdometerKm;
      if (km == null) {
        throw ArgumentError.notNull('draft.currentOdometerKm');
      }
      return repository.create(
        plate: draft.plate,
        kind: identity.kind,
        make: identity.make,
        makeSlug: identity.makeSlug,
        model: identity.model,
        modelSlug: identity.modelSlug,
        modelYear: draft.modelYear,
        version: draft.version,
        nickname: draft.nickname,
        ownerId: draft.ownerId,
        currentOdometerKm: km,
        fuelType: draft.fuelType,
        recommendedEngineOil: draft.recommendedEngineOil,
        manufacturerNotes: draft.manufacturerNotes,
      );
    });
  }
}

/// The [VehicleFormController] for a vehicle id (`null` to create one).
final vehicleFormControllerProvider = AsyncNotifierProvider.autoDispose
    .family<VehicleFormController, Vehicle?, String?>(
  VehicleFormController.new,
);
