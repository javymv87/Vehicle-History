import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/router/app_routes.dart';
import 'package:vehicle_history/features/owners/pages/owner_detail_page.dart';
import 'package:vehicle_history/features/owners/pages/owner_form_page.dart';
import 'package:vehicle_history/features/owners/pages/owner_list_page.dart';
import 'package:vehicle_history/features/vehicles/pages/vehicle_detail_page.dart';
import 'package:vehicle_history/features/vehicles/pages/vehicle_form_page.dart';
import 'package:vehicle_history/features/vehicles/pages/vehicle_list_page.dart';
import 'package:vehicle_history/shared/widgets/not_found_page.dart';

import '../support/fake_repositories.dart';
import '../support/pump_app.dart';

void main() {
  late FakeStore store;
  late String ownerId;
  late String vehicleId;

  setUp(() {
    store = FakeStore();
    ownerId = store.addOwner('Mario').id;
    vehicleId = store.addVehicle('AB123CD', ownerId: ownerId).id;
  });

  final routes = <String, (String Function(String, String), Type)>{
    '/': ((_, __) => '/', VehicleListPage),
    'vehicles': ((_, __) => AppRoutes.vehicles, VehicleListPage),
    'vehicles/new': ((_, __) => AppRoutes.newVehicle, VehicleFormPage),
    'vehicles/:id': ((_, v) => AppRoutes.vehicle(v), VehicleDetailPage),
    'vehicles/:id/edit': ((_, v) => AppRoutes.editVehicle(v), VehicleFormPage),
    'owners': ((_, __) => AppRoutes.owners, OwnerListPage),
    'owners/new': ((_, __) => AppRoutes.newOwner, OwnerFormPage),
    'owners/:id': ((o, _) => AppRoutes.owner(o), OwnerDetailPage),
    'owners/:id/edit': ((o, _) => AppRoutes.editOwner(o), OwnerFormPage),
  };

  for (final MapEntry(key: name, value: (path, page)) in routes.entries) {
    testWidgets('$name builds its page', (tester) async {
      await pumpApp(tester, store, location: path(ownerId, vehicleId));

      expect(find.byType(page), findsOneWidget);
      expect(find.byType(NotFoundPage), findsNothing);
    });
  }

  const unknownIds = {
    'vehicle detail': '/vehicles/unknown',
    'vehicle edit': '/vehicles/unknown/edit',
    'owner detail': '/owners/unknown',
    'owner edit': '/owners/unknown/edit',
  };
  for (final MapEntry(key: name, value: location) in unknownIds.entries) {
    testWidgets('$name with an unknown id shows not found', (tester) async {
      await pumpApp(tester, store, location: location);

      expect(find.byType(NotFoundPage), findsOneWidget);
      expect(find.text('Not found'), findsOneWidget);
    });
  }

  testWidgets('a deleted vehicle shows not found', (tester) async {
    store.deletedVehicles.add(vehicleId);
    await pumpApp(tester, store, location: AppRoutes.vehicle(vehicleId));

    expect(
      find.text('This vehicle does not exist or has been deleted.'),
      findsOneWidget,
    );
  });

  testWidgets('an unknown path shows not found, with a way home',
      (tester) async {
    await pumpApp(tester, store, location: '/nowhere');

    expect(find.text('This page does not exist.'), findsOneWidget);
    await tester.tap(find.text('Go to vehicles'));
    await tester.pumpAndSettle();
    expect(find.byType(VehicleListPage), findsOneWidget);
  });
}
