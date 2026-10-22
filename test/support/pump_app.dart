import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/app.dart';
import 'package:vehicle_history/app/router/app_router.dart';
import 'package:vehicle_history/data/attachments/attachment_staging.dart';
import 'package:vehicle_history/data/data_providers.dart';

import 'catalog_fixtures.dart';
import 'fake_backup.dart';
import 'fake_repositories.dart';
import 'memory_attachment_store.dart';

/// The fakes behind the Backup page, so tests can configure and inspect
/// them.
class BackupFakes {
  /// The settings, where the export writes `last_export_at`.
  final FakeSettingsRepository settings = FakeSettingsRepository();

  /// The export / import service.
  late final FakeBackupService service = FakeBackupService(settings);

  /// The open dialog.
  final FakeBackupFilePicker picker = FakeBackupFilePicker();

  /// The native "save as".
  final FakeNativeFiles nativeFiles = FakeNativeFiles();

  /// The camera, gallery and file pickers of attachments.
  final FakeAttachmentPicker attachmentPicker = FakeAttachmentPicker();

  /// Opens PDF and other attachments.
  final FakeFileOpener fileOpener = FakeFileOpener();

  /// Where staged attachment files go.
  final MemoryAttachmentStore attachmentStore = MemoryAttachmentStore();
}

/// Provider overrides that run the app on [store] instead of a database,
/// with [backup] (fresh fakes by default) behind the Backup page.
List<Override> fakeDataOverrides(FakeStore store, {BackupFakes? backup}) {
  final fakes = backup ?? BackupFakes();
  return [
    databaseReadyProvider.overrideWith((ref) async {}),
    ownerRepositoryProvider.overrideWithValue(FakeOwnerRepository(store)),
    vehicleRepositoryProvider.overrideWithValue(FakeVehicleRepository(store)),
    logEntryRepositoryProvider.overrideWithValue(FakeLogEntryRepository(store)),
    mileageReadingRepositoryProvider
        .overrideWithValue(FakeMileageReadingRepository(store)),
    vehicleCatalogProvider.overrideWith((ref) async => vehicleCatalogFixture()),
    countryNamesProvider.overrideWith((ref) async => countryNamesFixture()),
    settingsRepositoryProvider.overrideWithValue(fakes.settings),
    backupServiceProvider.overrideWithValue(fakes.service),
    backupFilePickerProvider.overrideWithValue(fakes.picker),
    nativeFilesProvider.overrideWithValue(fakes.nativeFiles),
    attachmentRepositoryProvider
        .overrideWithValue(FakeAttachmentRepository(store)),
    attachmentStoreProvider.overrideWithValue(fakes.attachmentStore),
    attachmentStagingProvider
        .overrideWithValue(AttachmentStaging(fakes.attachmentStore)),
    attachmentPickerProvider.overrideWithValue(fakes.attachmentPicker),
    fileOpenerProvider.overrideWithValue(fakes.fileOpener),
  ];
}

/// Pumps the whole app on [store], starting at [location], in English, with
/// [backup] behind the Backup page.
///
/// Returns the [ProviderContainer] so tests can inspect the router.
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  FakeStore store, {
  String location = '/vehicles',
  Locale locale = const Locale('en'),
  BackupFakes? backup,
}) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  final container = ProviderContainer(
    overrides: [
      ...fakeDataOverrides(store, backup: backup),
      routerProvider.overrideWith((ref) {
        final router = buildAppRouter(initialLocation: location);
        ref.onDispose(router.dispose);
        return router;
      }),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const VehicleHistoryApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
