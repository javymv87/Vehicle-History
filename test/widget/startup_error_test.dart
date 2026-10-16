import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/app.dart';
import 'package:vehicle_history/app/startup_error_page.dart';
import 'package:vehicle_history/data/data_providers.dart';
import 'package:vehicle_history/data/db/upgrade_safety.dart';
import 'package:vehicle_history/features/vehicles/pages/vehicle_list_page.dart';

/// Pumps the app with a database that fails to open with [error].
Future<void> pumpFailingApp(
  WidgetTester tester,
  Object error, {
  Locale locale = const Locale('en'),
}) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseReadyProvider.overrideWith((ref) => Future.error(error)),
      ],
      child: const VehicleHistoryApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a database newer than the app shows the localised error',
      (tester) async {
    await pumpFailingApp(tester, const DatabaseNewerThanAppException(2, 1));

    expect(find.byType(StartupErrorPage), findsOneWidget);
    expect(find.byType(VehicleListPage), findsNothing);
    expect(find.text('Your data could not be opened'), findsOneWidget);
    expect(
      find.textContaining('saved by a newer version of Vehicle History'),
      findsOneWidget,
    );
    expect(find.textContaining('has not been touched'), findsOneWidget);
  });

  testWidgets('a failed upgrade says the data was not changed', (tester) async {
    await pumpFailingApp(
      tester,
      const MigrationIntegrityException(1, 2, 3),
      locale: const Locale('es'),
    );

    expect(find.text('No se han podido abrir tus datos'), findsOneWidget);
    expect(find.textContaining('No se han modificado'), findsOneWidget);
    expect(find.textContaining('MigrationIntegrityException'), findsOneWidget);
  });
}
