# CLAUDE.md — Vehicle-History development guide

This file is the operating manual for any AI assistant or developer working on
this repository. Read it **before** writing or changing code.

The conceptual documentation in [`Docs/`](Docs/) (Spanish) is the **source of
truth** for product decisions. This file is the source of truth for **technical
rules and conventions**. If code and `Docs/` disagree, `Docs/` wins — report the
discrepancy instead of silently choosing.

---

## 1. Project identity

| Item | Value |
| --- | --- |
| App display name | `Vehicle History` |
| Repository | `Vehicle-History` |
| Dart package name | `vehicle_history` |
| Application id | `io.github.javymv87.vehicle_history` — fixed at `flutter create`, never change after publishing |
| Platform priority | Android first; iOS must stay possible (no Android-only APIs without an abstraction) |
| Users | Single user per device. No accounts, no multi-user, no server |
| Data location | On device. Cloud is used for backup only, never as the live store |
| Licence | None — all rights reserved. Deliberate decision, not an open point |

---

## 2. Tech stack

Flutter · Material 3 · Riverpod · `go_router` · Drift through `drift_flutter`
(SQLite) · `googleapis` (Google Drive) · `google_sign_in` / `flutter_appauth` ·
`flutter_secure_storage` · `flutter_local_notifications` · `gen_l10n` · `intl`
· `file_picker` · `archive` · `image_picker` · `open_filex`

Toolchain reference (recorded at scaffold time): **Flutter 3.44.8** (stable
channel) · **Dart 3.12.2**. The version is pinned for this repository in
`.fvmrc` through [FVM](https://fvm.app): run every local command as
`fvm flutter ...` / `fvm dart ...`, never with a bare global `flutter` /
`dart`, which may be a different version.

Added in step 6 for the backup package: `file_picker` (the system "save
as" / "open" dialogs, Android Storage Access Framework, so the app needs no
storage permission and the user picks Downloads, Drive or any provider) and
`archive` (builds and reads the `.zip` in pure Dart, so the package format is
unit-tested without a device). The app version for the manifest is the
constant `appVersion` (`lib/shared/constants/app_version.dart`), kept equal
to `pubspec.yaml` by a test, rather than another plugin.

Added in step 8 for attachments: `image_picker` (camera and gallery photos,
resized on the phone to at most 2000 × 2000 px at JPEG quality 85; Android
13+ photo picker, so no storage permission; `CAMERA` is declared in the
manifest and requested by the plugin) and `open_filex` (opens a PDF or other
attachment with the phone's app through its own `FileProvider`; pinned to
`4.7.0`, 5.0.0 being under two weeks old). The manifest removes, with
`tools:node="remove"`, the `READ_EXTERNAL_STORAGE` / `READ_MEDIA_*`
permissions `open_filex` declares: the app only opens files in its own
private directory. `file_picker` is still used for picking files and the
package to import, but **no longer for saving**: saving goes through the
native channel below. No image, thumbnail, share or permission library:
thumbnails are `Image.file` with `cacheWidth`.

Added in step 9 for the Google Drive copy (mode 1; mode 2 came in step
9b, below):
`googleapis` 17.0.0 (Drive v3: metadata queries, resumable upload,
streamed download), `google_sign_in` 7.2.0 (Credential Manager account
picker + Identity `AuthorizationClient` for the scope), its implementations
pinned by the two-week rule (`google_sign_in_android: 7.2.17`,
`google_sign_in_ios: 6.3.6`), `google_sign_in_platform_interface` 3.1.0
(asked directly for a token by the stored email, so no account sheet at
every start) and `http` 1.6.0 (the bearer-token client). No
`googleapis_auth` / extension package, no `connectivity_plus`, no
WorkManager. The manifest declares `INTERNET` (Flutter's template has it
only in the debug / profile manifests) and `ACCESS_NETWORK_STATE`.

Added in step 9b for mode 2 of the Drive link: `flutter_appauth` 12.1.0
(AppAuth-Android 0.11.1: Authorization Code + PKCE S256 in a Custom Tab,
token refresh; `appAuthRedirectScheme` in `android/app/build.gradle.kts`
is the reversed Android client id) and `flutter_secure_storage` 11.2.0
(the refresh token only, AES-GCM with an Android Keystore-wrapped key).
`res/xml/backup_rules.xml` and `data_extraction_rules.xml` keep its two
`shared_prefs` files (`FlutterSecureStorage.xml`,
`FlutterSecureKeyStorage.xml`) out of Android's own backup and device
transfer; everything else is backed up as before. Android has no
ephemeral Custom Tab through these plugins, so the browser may keep the
Google session (the UI says so once after linking). `MainActivity` has
**no** `android:taskAffinity=""` (Flutter's template adds it): with it,
Google's redirect lands in a new task where AppAuth has no pending request
and the sign-in never returns to the app.

**Native channel** (`MainActivity.kt`, Android only, wrapped by
`NativeFiles` in `lib/data/platform/native_files.dart`, faked in tests):
`vehicle_history/files` with `saveFile(sourcePath, suggestedName,
mimeType)` — `ACTION_CREATE_DOCUMENT`, then a copy to the chosen `Uri`
through `contentResolver.openOutputStream` in 64 KB chunks off the main
thread, answering `saved` / `cancelled` / an error —,
`saveFilesToFolder(files)` — `ACTION_OPEN_DOCUMENT_TREE`, then each file
copied the same way into a new document of the folder
(`DocumentsContract.createDocument`, which renames rather than overwrites),
answering the number saved or `null` when cancelled —,
`shareFiles(files)` — copies under their names to `cache/share/<n>/`,
then `ACTION_SEND` / `ACTION_SEND_MULTIPLE` through `ShareFileProvider`, a
`FileProvider` subclass (so it never merges with the one `open_filex`
declares) whose `res/xml/share_paths.xml` exposes `cache/share/` only — and
`freeBytes(path)` (`StatFs`). A `files` argument is a list of
`{path, name, mimeType}` (`NativeFile`). Used for the backup package and
for "Save to…" / "Share" of attachments, which can be too large to pass
through a channel as bytes. A second channel, `vehicle_history/network`
(`NetworkState`, `lib/data/platform/network_state.dart`), answers
`networkState()` = `none` / `metered` / `unmetered`
(`ConnectivityManager.isActiveNetworkMetered`) for the mobile-data setting
of the automatic Drive copy. CI does not build Android: compile it with
`fvm flutter build apk --debug` after touching it.

Dependencies are added **one at a time, on explicit request**. Never add a
package as a side effect of implementing a feature. Naming a package in this
section records the decision; it does not authorise adding it to
`pubspec.yaml` before it is actually used.

**Two-week rule for versions.** A dependency version (new package, upgrade,
or the version of a pinned tool or data source) must have been published on
pub.dev **at least 14 days earlier**; check the release date on pub.dev
(`https://pub.dev/api/packages/<name>` lists `published` per version). When
the newest version is younger, pin the newest one that is old enough with an
exact constraint (`archive: 4.3.0`, chosen in step 7: 4.4.0 and later were
under two weeks old), and relax the pin once a newer one qualifies.

### Drift and schema migrations

Drift is wired through `drift_flutter`, not through a hand-rolled
`NativeDatabase`. Code generation runs via `build_runner`; the generated
`*.g.dart` files are gitignored and regenerated by CI.

Migrations are mandatory **from the first schema version**, not retrofitted
later. Every schema change bumps `schemaVersion`, adds a step to the migration
strategy, and commits the `drift_dev` schema dump under `drift_schemas/`.
Migration tests run against those dumps.

The reason is not tidiness. The local database is the only copy of data the
user cannot recreate: there is no server to re-sync from, and the Drive backup
may be older than the last change. A broken migration is permanent data loss.

Settled for the database (schema v9: `owners`, `vehicles`, `audit_log`,
`log_entries`, `mileage_readings`, `settings`, `attachments`; v2 added the
vehicle kind, make / model, model year and version; v3 added `log_entries`;
v4 added `mileage_readings` with one initial reading per vehicle; v5 added
`deleted_at` for the Trash; v6 added `settings`; v7 added `attachments`;
v8 added the archive columns of `vehicles`; v9 made the four distance
columns `REAL`):

- **Workflow.** `build.yaml` configures `drift_dev` (`databases`,
  `schema_dir: drift_schemas/`, `test_dir: test/drift/`); every schema
  change follows "Upgrade safety" below. At v1 `make-migrations` only writes
  the dump (the steps file and `migration_test.dart` appear from v2); the
  verifier helpers under `test/drift/vehicle_history/generated/` come from
  `dart run drift_dev schema generate`.
- **Timestamps as text.** `store_date_time_values_as_text: true` in
  `build.yaml`, set from v1: changing it later is a data migration.
- **Foreign keys** are enabled with `PRAGMA foreign_keys = ON` in
  `beforeOpen` (SQLite leaves them off). `vehicles.owner_id` →
  `owners.id`, `log_entries.vehicle_id` → `vehicles.id` and
  `mileage_readings.vehicle_id` → `vehicles.id`, all
  `ON DELETE RESTRICT`.
- **Soft delete.** Main tables carry `deleted` (default `false`) and
  `deleted_at` (nullable UTC timestamp, v5), shared with `id`,
  `created_at`, `updated_at` through the `TechnicalColumns` mixin. Every
  soft delete sets both (`deleted_at = now`), every restore clears both.
  Every read filters `deleted = 0` unless the method name says otherwise;
  delete means soft delete. The audit log is append-only and has no flag.
  Child rows of a soft-deleted parent are **not** cascaded: the entries of a
  deleted vehicle keep their own flag, and the `log_entries` and
  `mileage_readings` reads also require a live vehicle, so they come back
  when the vehicle is restored.
- **Trash and physical delete (v5).** Soft-deleted vehicles are the Trash
  (`VehicleRepository.watchTrashed`, with live entry / reading counts).
  `TrashDao` is the only code that removes rows from disk: `purgeVehicle`
  deletes the vehicle's readings and entries (whatever their flags) and then
  the vehicle, in one transaction. Callers: `VehicleRepository.purge` /
  `purgeAllTrashed` (user action) and `TrashCleanupService`, run once per
  app start by `databaseReadyProvider` after the open
  (`runStartupCleanupSafely`: a failure is logged, rolled back and never
  blocks the start). The cleanup removes, at `deleted_at` ≤ now − 30 days
  (`trashRetention`): trashed vehicles with their children; deleted entries
  and readings of live vehicles; deleted owners referenced by no vehicle
  row; deleted attachments outside the Trash. Every vehicle and owner
  removed, and (since 0.8.1) every entry, reading and attachment the
  cleanup removes on its own, gets a `purge` audit row in the same
  transaction; what goes with a removed parent gets none (the parent's row
  covers it). An owner
  with vehicles in the Trash cannot be deleted
  (`OwnerHasTrashedVehiclesException`).
- **Audit log from v1.** Every repository write adds its `audit_log` row in
  the same transaction. Operations: `create`, `update`, `delete`, `restore`
  (Undo after a delete). `operation` and `entity_type` are plain
  text with no CHECK, so a new code only needs its converter
  (`AuditOperationConverter`, `AuditEntityTypeConverter`; `logEntry` came
  this way in v3, `mileageReading` in v4, operation `purge` in v5, operation
  `import` with entity `database` in v6, entity `attachment` in v7,
  operations `archive` and `reactivate` in v8), not a schema change; an older build that meets an unknown code throws when
  reading the audit log.
- **Location.** `vehicle_history.sqlite` lives in the **application support
  directory** (`getApplicationSupportDirectory`, passed to `drift_flutter`
  as `DriftNativeOptions.databaseDirectory`), never in the documents
  directory, which iOS shows in the Files app and backs up to iCloud. Photo
  paths (future) are stored **relative to the same directory**.
- **Startup.** `databaseReadyProvider` empties the app's cache
  (`wipeTemporaryDirectorySafely`, before the database opens: picker copies
  and share copies only), opens the database (running any migration), then
  runs the 30-day Trash cleanup and the attachment sweep, before the router
  is shown; an opening failure, such as `DatabaseNewerThanAppException`, shows
  the localised full-screen `StartupErrorPage` and nothing reads data.
- **Attachments (v7)** (`Docs/02_data_model.md`, "Attachment"): one row
  ↔ one file `attachments/<id>.<ext>` under the application support
  directory, never in public storage. Picked files are staged by
  `AttachmentStaging` in `attachments_tmp/<session>/` (wiped on cancel and at
  every start) and moved in with the row in one transaction
  (`AttachmentWriter.runWithMovedFiles`). Files are physically deleted only
  by the 30-day cleanup, the vehicle purge and the orphan sweep at start; a
  row whose file is missing is kept. `pickAndStage` calls
  `PickedFile.deleteSource` once a file is staged or refused, so the
  plugin's own cache copy goes at once; whatever is left goes with the cache
  at the next start. Photos are named `IMG_yyyyMMdd_HHmmss[_n].<ext>`
  (`photoFileName`, local time). Selection mode (U29) is the auto-disposed
  `attachmentSelectionProvider` family keyed by `AttachmentTarget`, shown by
  `AttachmentSelectionAppBar` on the three pages that list attachments;
  several are deleted with `AttachmentRepository.deleteMany` and brought
  back by one `restoreMany`, each all-or-nothing in one transaction.
- **No SQLCipher.** The database lives in the app sandbox, protected by
  Android file-based encryption. Owner data leaves the device only through
  the Drive backup, so encrypting the **backup file** is evaluated in the
  backup step. A deliberate decision, open to revision.
- **CHECK constraints** are written in the table's `customConstraints`, not
  with `Column.check`, whose self-referencing getter trips the
  `recursive_getters` lint. Exception: a column added by
  `ALTER TABLE … ADD COLUMN` carries its CHECK as the column's
  `customConstraint('NULL CHECK (…)')` (e.g. `vehicles.model_year`), since a
  table constraint cannot be added without recreating the table.
- **History entries** (`log_entries`) are one table for every type. The
  km-required rule per type lives in `LogEntryType.requiresKm` and is
  enforced by the repository as well as the form. Filters: date range and
  types in SQL (indexes `(vehicle_id, entry_date)`, `(vehicle_id, type)`),
  text in Dart through `LogEntryFilter.matchesText` / `foldForSearch`, since
  SQLite ignores neither accents nor non-ASCII case. `LogEntryFilter.matches`
  is the reference both paths are tested against.
- **Future dates** of entries: only `legalDue`, `expense` and `note`
  (`LogEntryType.allowsFutureDate`); work types must be dated today or
  earlier, in the form and the repository. "Today" is
  `CalendarDate.localDayOf` of the injected UTC clock (`localToday`), the
  one explicit timestamp → day conversion.
- **Odometer readings** (`mileage_readings`, v4) are independent of the
  entries: an entry's km never writes a reading by itself; the only bridge
  is the explicit "Update" offer after saving an entry
  (`shouldOfferOdometerUpdate`). Every vehicle has at least one live
  reading, its initial one (the oldest, no flag column): inserted by
  `DriftVehicleRepository.create` in the same transaction, and for existing
  vehicles, deleted ones included, by the v3 → v4 migration
  (`AppDatabase.insertInitialReadings`, no audit row). The last reading is
  the greatest `(reading_date, created_at)`. `vehicles.current_odometer_km`
  is a cache always equal to the last live reading's km: every reading
  write (`create`, `updateInitial`, `deleteLast`, `restore`) updates it in
  the same transaction, without touching the vehicle's `updated_at`. Rules
  (`MileageReadingRepository`): a new reading is on or after the last day,
  never after today, with km ≥ the last; only the last reading is
  deletable, never the initial one; Undo only while it would again be the
  last; correcting only while it is the sole reading. Refusals are
  `InvalidFieldException` reasons or `MileageReadingRuleException`. A jump
  above `bigOdometerJumpKm` (50 000) is accepted by the repository and
  confirmed by the UI (`odometer_checks.dart`). The entry form warns, never
  blocks, when an entry has more km than the first reading of a later day
  (`laterReadingBelowEntryKm`).
- **Archived vehicles (v8)** (`Docs/02_data_model.md`, "Archivo de
  vehículos"): `vehicles.archived_at` (a **`CalendarDate`**, `yyyy-MM-dd`,
  never an instant), `archive_reason` (`ArchiveReason` codes through
  `ArchiveReasonConverter`), `archive_note`, `archived_km`
  (`NULL CHECK (archived_km >= 0)`), all `NULL` while active. *Active* =
  `deleted = 0 AND archived_at IS NULL`: the one expression
  `VehiclesDao.isActive`, behind `watchActive` (the main list) and, negated
  over live rows, `watchArchived`; step 11 reuses it. `getById` /
  `watchById` / `watchByOwner` return archived vehicles too.
  `VehicleRepository.archive` runs in one transaction: with a km it first
  calls `MileageReadingRepository.create` (a nested drift transaction, so
  the reading rules refuse the whole archive), then writes the four columns
  and the `archive` audit row; `reactivate` clears them (`reactivate` row)
  and leaves every reading alone. **Read-only guard:** the entry, reading
  and attachment repositories check `vehicleStateOf`
  (`lib/data/db/vehicle_state.dart`, one shared query; `targetStateOf` for
  attachment targets) before every write and throw
  `VehicleArchivedException` (`ActionError.vehicleArchived`); only
  `delete`, `restore`, `reactivate`, the Trash purge, the startup cleanup
  and the import bypass it (they never go through those writes). UI:
  `vehicleReadOnlyProvider` / `attachmentTargetReadOnlyProvider` hide every
  add / edit / delete affordance; the vehicle page's overflow menu holds
  Archive or Reactivate plus Move to Trash; the archived list is
  `/vehicles/archived` (declared before `/:id`); the forms refuse an
  archived vehicle reached by deep link.
- **Make and model** are stored as the display name (always) plus an
  optional catalogue slug (`make_slug`, `model_slug`; `null` when typed by
  hand). The name is the source of truth for display; the slug only matches
  the catalogue.
- **Settings (v6)** are the key / value table `settings` (`key` text PK,
  `value` nullable text, `updated_at` UTC), with no `deleted` flag and no
  audit rows. Keys are `SettingKey` values with explicit codes
  (`last_export_at`, `language`, `theme`, since step 9 the `drive_…` keys
  and since step 11 the five `unit_…` keys of
  `Docs/06_settings_and_i18n.md`). Each key has a `SettingScope`
  that decides what **every import** does with it: `shared` comes from the
  package, `device` (`drive_account`, `drive_auth_mode`,
  `drive_device_id`, `drive_mobile_data`) keeps the phone's value,
  `syncPoint`
  (`drive_sync_*`) is cleared (`BackupService._openImported`); the
  `unit_…` keys are `shared` like `language` and `theme`, so an import
  brings the package's units. `SettingsRepository` has `read`, `write`,
  `watch`, `watchMany`, `writeMany` (one transaction), plus typed accessors
  (`watchLastExportAt`, `writeLastExportAt`, `watchLanguage` /
  `writeLanguage`, `watchThemeMode` / `writeThemeMode`,
  `watchUnitPreferences` / `writeUnitPreferences` and one `write…Unit` per
  quantity). `language` and `theme` hold the
  stable codes of `AppLanguage` (`system`, `it`, `es`, `en`) and
  `AppThemeMode` (`system`, `light`, `dark`, named so because `AppTheme`
  holds the themes), `lib/data/models/app_preferences.dart`; absent or
  unknown means `system`.
- **Language and theme providers**
  (`features/settings/controllers/settings_controller.dart`):
  `languageSettingProvider` / `themeSettingProvider` stream the stored value
  only once `databaseReadyProvider` is `AsyncData`, so at start the app
  shows the device language and theme until the database is open (no wrong
  language after the splash), and during the reopen after an import they
  keep their previous value, then follow the imported rows (they depend on
  `appDatabaseProvider` through the repository). A read error is logged and
  swallowed (`handleError`), which leaves them without a value = `system`.
  `appLocaleProvider` (`Locale?`, `null` = device) and
  `appThemeModeProvider` (`ThemeMode`) feed `MaterialApp.locale` /
  `themeMode`; `SettingsController` writes. Formatting follows the chosen
  locale because it goes through `Localizations.localeOf` /
  `l10n.localeName`, never `Intl.defaultLocale`.
- **Units of measurement (step 11, schema v9)**
  (`Docs/06_settings_and_i18n.md`, "Unidades de medida"; the rule is in
  §11, "Physical quantities"). The four distance columns
  (`mileage_readings.km`, `log_entries.km`, `vehicles.current_odometer_km`,
  `vehicles.archived_km`) are `REAL` / `double` since v9, so a value typed
  in miles is stored as its exact km; the v8 → v9 step recreates the three
  tables with `TableMigration` and copies every row as it is. The five
  units are `UnitPreferences` (`lib/data/models/units.dart`: the unit enums
  with their codes and conversion factors, the derived `UnitPreset`, and
  the friendly display thresholds such as `friendlyBigOdometerJump`, the
  only place such thresholds live). `UnitFormatter`
  (`lib/shared/utils/unit_formatter.dart`) builds one `QuantityFormatter`
  per quantity (`format` with symbol, `formatValue`, `symbol`, `parse` to
  SI with either decimal separator, `inputText` for an edit field,
  `toDisplay` / `toSI`); symbols are ARB strings. Widgets get it through
  `unitFormatterOf(context, ref)` in `build` (it watches the kept
  `unitPreferencesProvider`, next to the language and theme providers) and
  `readUnitFormatter` in callbacks and `didChangeDependencies`. Distance
  fields accept whole numbers in the chosen unit, show the symbol as
  `suffixText` and parse with `sameAs:` the reading they are compared
  against, so re-typing a shown value never falls below it by rounding.
  Domain rules compare in km; dialogs show converted values and the
  friendly threshold (`bigOdometerJumpThreshold`). Settings: the
  `UnitsSection` of the Settings page (preset segments, one radio-dialog
  tile per quantity, the volume / consumption mismatch hint).

- **`last_modified_at`** of the manifest (`BackupDao.lastModifiedAt`, the
  version stamp of the step-9 guard) is the latest `updated_at` of owners,
  vehicles, entries, readings and attachments (deleted rows included) and
  the latest `purge` audit row, compared as ISO-8601 UTC text. Settings and
  `import` audit rows never count. Every physical deletion must write a
  `purge` row in its transaction, or the stamp could go backwards.
- **`last_export_at` and the package:** `BackupService.exportPackage`
  writes it (the export instant) **before** `VACUUM INTO`, so the package
  carries its own export date and an import shows it. If the package is not
  saved (dialog cancelled or save failed) the controller calls
  `discardExport`, which puts the previous value back (kept in
  `ExportedPackage.previousLastExportAt`); a failure inside the export puts
  it back itself. The Backup page never shows an export that left no file.
- **Backup package** (`lib/data/backup/`, `Docs/05_sync_and_storage.md`): a
  zip with `manifest.json`, `vehicle_history.sqlite` (a `VACUUM INTO` copy
  through `BackupDao`) and `attachments/` with the file of **every**
  attachment row, live or deleted; `format_version` stays 1, the manifest
  has `counts.attachments` and `attachments_bytes` (0 when missing, as in a
  step-6 package). **Never in memory:** `writeBackupPackage` streams the
  files into a temporary zip with `archive`'s `ZipFileEncoder`, the
  controller saves it through `NativeFiles.saveFile` and then deletes it
  (`deleteExport`); an import copies the picked file (streamed) next to the
  database and `BackupPackageReader` reads the zip's index, inflating one
  entry at a time to disk. Only `attachments/<plain name>` entries are
  accepted (`isAttachmentEntryName`). `BackupService` does the file work
  next to the database file, behind `BackupFiles` and
  `DatabaseFileInspector` (which opens a foreign file with no migration and
  lists its attachment paths). A newer schema or format, a damaged file or
  too little free space (`freeBytes`) is rejected; an older schema is
  migrated by `runSafeUpgrade`; files missing from the package are tolerated
  and reported (`ImportPreview.missingFiles`). Every rejection
  (`BackupRejectedException`) happens before anything is touched.
- **Import safety net:** the referenced attachment files are unpacked to
  `attachments.import.tmp/`; the previous import's `pre_import` material is
  set aside (`*.pre_import.previous*`); `VACUUM INTO` →
  `vehicle_history.pre_import.sqlite`, close, `attachments/` →
  `attachments.pre_import/`, the unpacked directory → `attachments/`, the
  database file replaced (deleting the old `-wal` / `-shm`), a new
  connection opened (migration, startup cleanup, `import` audit row), and
  only then the previous material deleted (only the latest is kept). Any
  failure after the copy puts back **both** the database (from `pre_import`,
  checked to open) and the attachments directory
  (`BackupImportFailedException`); if even that fails,
  `BackupRestoreFailedException` and the material stays. Temporary files
  (`*.tmp`) never start with `vehicle_history.pre_v`, so the pre-upgrade
  rotation never touches them.
- **Closing and reopening at runtime:** `AppDatabase.close` is idempotent
  and closes the connection without waiting for the stream queries: drift's
  own close waits for every stream's done event, which a listener paused by
  Riverpod (a screen that is not visible) never takes, so it could hang.
  After an import (success or failure, not a rejection) the controller
  invalidates `appDatabaseProvider` and awaits `databaseReadyProvider`: a new
  `AppDatabase` opens the file, the cleanup runs as on any start, and every
  repository and screen provider rebuilds on the new connection (the router
  shows the progress indicator meanwhile). Anything that outlives this
  captures its messenger and `GoRouter` before the import starts.

- **Google Drive copy (step 9)** (`lib/data/drive/`,
  `Docs/05_sync_and_storage.md`). `DriveAuthService` links the account
  in one mode and hands out access tokens (`DriveTokenProvider`):
  `GoogleDriveAuthService` is mode 1 (google_sign_in, **no token stored**),
  `ManualDriveAuthService` mode 2 (flutter_appauth, the refresh token in
  `RefreshTokenStore` / `SecureRefreshTokenStore`, access token in memory,
  `invalid_grant` → token deleted + `DriveAuthorizationRequiredException`,
  unlink revokes at Google then deletes in any case, a failed revocation is
  `DriveRevocationFailedException`). The mode is `DriveAccount.mode`, stored
  as `drive_auth_mode` (absent = `system`); `DriveSyncService.link(mode:)`
  refuses another mode while one is linked, `unlink` returns `false` when
  the revocation failed; `DriveAuthRouter` gives the Drive client the
  tokens of the linked account's mode. Tokens are never logged (event names
  and error codes only); `DriveHttpClient` adds the bearer token and on a
  401 gets a fresh one and resends once (bodies up to 16 MB are buffered for
  that, so a 4 MB chunk of a resumable upload survives an expiry).
  `DriveBackupClient` finds packages by `appProperties` (`vh_role=backup`,
  scope `drive.file`, visible folder "Vehicle History" found the same way),
  uploads resumable and downloads streamed. Every upload carries
  `upload_id`, `last_modified_at`, `schema_version`, `app_version`,
  `device_id` and the counts (`CloudBackup.propertiesOf`). The last common
  point lives in the `drive_sync_*` settings (`DriveSettings` extension) and
  is written only after Drive confirmed an upload or after a successful
  restore (stamp read after the reopen). `evaluateSync` (`sync_guard.dart`)
  is the pure guard: `noAccount`, `noCloudCopy`, `cloudTooNew`,
  `noCommonPoint`, `aligned` (also when stamps and counts are equal:
  `sameContent`, recorded as the new point), `localChanged`,
  `cloudChanged`, `diverged`. `DriveSyncService` orchestrates link /
  unlink (both clear the point), check, upload (re-lists first and stops
  with `DriveCloudChangedException` if the latest copy is not the expected
  one; never over a newer schema; keeps the last `driveKeptCopies` = 3),
  and restore of the latest copy through `BackupService.importPackage`.
  `runStartupAutoUpload` is the **only automatic action**: once per start
  (`DriveController.runAtStartup`, from `DriveStartup` in the app builder,
  after `databaseReadyProvider`), upload only for `localChanged` /
  `noCloudCopy`, on an unmetered network unless `drive_mobile_data`; no
  retries, a failure shows in the status line until the next start. Right
  after linking an account with no copy, the first upload runs at once.
  The status reaches the UI as `DriveViewState` (kept-alive
  `driveControllerProvider`); `cloudChanged` / `diverged` show the home
  banner (`DriveBanner` in `HomeShell`). `BackupLock`
  (`backupLockProvider`, independent of the connection) lets one backup
  operation (export, import, upload, restore) run at a time; the startup
  upload skips if busy. The Drive package is built by
  `BackupService.buildDrivePackage`, which does not touch
  `last_export_at`. No encryption of the cloud package (Google account
  security; decided in step 9). Google Cloud: OAuth clients Android
  (package + SHA-1 of the fixed key) and Web (`driveServerClientId` in
  `drive_config.dart`, public; its secret is never used or committed).

### Upgrade safety

A new app version must **never** lose or corrupt data written by an older
one. `AppDatabase` runs every upgrade through `runSafeUpgrade`
(`lib/data/db/upgrade_safety.dart`), which enforces the mechanics; these rules
cover the rest, for every schema change:

1. Bump `schemaVersion` and run `dart run drift_dev make-migrations`.
2. Write the step in the generated `stepByStep(...)` of
   `app_database.steps.dart` and use it as `AppDatabase._schemaSteps`.
3. Commit the new dump under `drift_schemas/` and every non-`.g.dart` file
   the command writes. CI re-runs `make-migrations` and fails on any diff.
4. Fill in the data-integrity test
   (`test/drift/vehicle_history/data_integrity_test.dart`): realistic rows
   written at the old version must all be intact at the new one.
5. **Never destructive**: no drop-and-recreate, no `deleteEverything`, no
   reset on mismatch. Renames, type changes and dropped columns use Drift's
   table-recreation migration (`TableMigration`), which copies the data. New
   columns are nullable or have a default.

What `runSafeUpgrade` guarantees:

- **Pre-upgrade copy.** Before any upgrade (`from < to`) the database is
  copied with SQLite's `VACUUM INTO` to `vehicle_history.pre_v<from>.sqlite`
  next to it; only the latest copy is kept. `VACUUM INTO` yields a
  consistent file from the open connection (WAL content included), which a
  plain file copy cannot guarantee. No copy on a fresh install.
- **Atomic and checked.** The steps, `PRAGMA foreign_key_check` and the new
  `user_version` run in one transaction, with foreign keys off during the
  steps. Any foreign key violation fails the upgrade: everything rolls back
  and the copy is kept.
- **Downgrade refused.** A file newer than the app (`from > to`) throws
  `DatabaseNewerThanAppException` and is left untouched, never "fixed".

### Bundled reference data

Two read-only data sets ship as committed assets, built by scripts in `tool/`
and never fetched at runtime. Each script pins its source release; refreshing
means running it with a newer tag that is **at least two weeks old**, then
updating the pin in the script, the spot-check test and this section.

- **Vehicle catalogue** — `assets/catalog/vehicle_catalog.json`, from
  [VehiclesDB](https://github.com/vehiclesdb/vehiclesdb) release
  **`v2026.09.1`** (CC BY 4.0), built by
  `fvm dart run tool/build_vehicle_catalog.dart [tag]`. Kinds `car`, `van`,
  `motorcycle`, `moped`; per make: `slug`, `name`, a popularity score, and
  models as `[slug, name, globalDecile?]`. `VehicleCatalog`
  (`lib/data/catalog/`) does the ordering (20 most popular makes, then
  alphabetical; models by decile, then alphabetical) and the case- and
  accent-insensitive search. The script also writes `ATTRIBUTION.md` and
  `LICENSE.md` next to the asset; CC BY requires the visible credit, which
  is in About (`showAppAboutDialog`) and on the licence page
  (`registerDataLicenses`, `lib/app/data_licenses.dart`). Never edit the
  asset by hand: a missing model is covered by "Other model…".
- **Country names** — `assets/countries/country_names.json`, from
  [Unicode CLDR](https://github.com/unicode-org/cldr-json) release
  **`48.2.3`** (Unicode License v3), built by
  `fvm dart run tool/build_country_names.dart [tag]`: the 249 ISO 3166-1
  alpha-2 codes with names in `en`, `es`, `it`. Read through `CountryNames`.
  The owner's nationality is stored as the code, or as typed text through
  "Other…".

Tests use small fixtures (`test/support/catalog_fixtures.dart`) through
`vehicleCatalogProvider` / `countryNamesProvider` overrides; only the
spot-check tests read the real assets.

Line endings: `.gitattributes` stores every text file with LF (`* text=auto
eol=lf`), Windows scripts with CRLF and images, fonts and keystores as binary,
so a Windows checkout produces the same bytes as CI.

Releases: the Android `versionCode` (the build number after `+` in
`pubspec.yaml`) must increase with every release. **Version convention:**
every merged roadmap step bumps the minor version and the build number
together (step 6 = `0.6.0+6`, then `0.7.0+7`, …), and updates `appVersion`
(`lib/shared/constants/app_version.dart`) in the same change; a test fails if
they differ.

Signing (Android): `android/app/build.gradle.kts` loads
`android/key.properties` **if present** and signs **both `debug` and
`release`** with that fixed key, so every build installs over the previous
one (a different signature forces an uninstall, which deletes the data). The
keystore lives outside the repository (`C:\Keys\vehicle-history-release.jks`
on the owner's PC); `key.properties` and every `*.jks` / `*.keystore` are
git-ignored. Never read, print or commit them, and never ask for their
passwords. Without the file (CI, another PC) the build falls back to the
default debug signing and still succeeds. Release keeps the default minify /
shrink settings; obfuscation is not enabled.

---

## 3. Non-negotiable rules

1. **English code.** Identifiers, file names, branch names and commit messages
   are always in English.
2. **English comments, always.** Every class, public method and non-obvious
   field carries a `///` doc comment. Inline comments wherever the logic is not
   self-evident. No undocumented code lands in the repository.
3. **Framework and language best practices, always.** Effective Dart naming and
   style, `const` constructors where possible, `dart format` on everything,
   zero `flutter analyze` warnings, idiomatic Flutter widget composition. If a
   request conflicts with a best practice, say so *before* implementing it.
4. **No hard-coded user-facing strings.** Everything visible to the user is
   externalised for localisation (IT / ES / EN).
5. **Stop and ask.** When a requirement is ambiguous or a decision is not
   covered by `Docs/`, stop and ask. Do not invent product behaviour.
6. **Ship through the full cycle.** When a task is finished and every
   quality gate (§8) is green, the assistant runs the whole cycle described
   in §10: commit on the working branch, push it, open the PR, wait for
   `analyze-and-test`, squash-merge, delete the branch. Commits use English
   Conventional Commits in the imperative mood with **no AI attribution** (no
   `Co-Authored-By` trailer, no "Generated with" line). Hard limits: never
   push to `main` directly, never force-push, never rewrite pushed history,
   never bypass the ruleset (no `--admin`, no disabling checks), never merge
   unless `analyze-and-test` is green.

### Guiding principle: keep it simple, keep it manual

The owner of this project prefers explicit user control over cleverness. Do not
add automatic calculations, automatic data propagation or "helpful" inference
unless `Docs/` asks for it. When in doubt, the simpler and more predictable
behaviour is the correct one.

---

## 4. Folder structure

```
lib/
  main.dart              # minimal entry point only
  app/
    router/              # navigation
    theme/               # Material 3 theme from a single seed colour
  data/
    db/                  # Drift database, tables, migrations
    models/              # domain models
    repositories/        # the only access path to persisted data
    backup/              # backup package export / import, BackupLock
    drive/               # Google Drive copy: auth, client, guard, sync
    attachments/         # attachment files, staging, pickers, file opener
    platform/            # wrappers of the app's own native channels
  features/
    vehicles/            # pages/ widgets/ controllers/ (archive too)
    owners/              # pages/ widgets/ controllers/
    entries/             # pages/ widgets/ controllers/
    maintenance/         # pages/ widgets/ controllers/
    mileage/             # pages/ widgets/ controllers/
    reminders/           # pages/ widgets/ controllers/
    reports/             # pages/ widgets/ controllers/
    settings/            # pages/ widgets/ controllers/
    trash/               # pages/ widgets/ controllers/
    backup/              # pages/ widgets/ controllers/
    attachments/         # shared attachment pieces: sheet, list, viewer
  l10n/                  # .arb files, gen_l10n output
  shared/
    widgets/             # widgets reused across features
    utils/
    constants/

test/
  unit/
  widget/

assets/
  images/
  icons/

Docs/                    # Spanish conceptual documentation (source of truth)
CLAUDE.md                # this file
README.md                # public project description
```

**Layering rule.** Models, database and repositories live **only** in `data/`
and are shared between features. Everything under `features/` is presentation:
screens, feature-local widgets, and the state that drives them. A feature never
talks to the database directly — always through a repository.

**What a `controllers/` file is.** A controller is a Riverpod notifier holding
the state of one screen, or of one screen-sized piece of UI, and exposing the
actions that screen can perform. It calls repositories; it never touches Drift,
`googleapis` or any plugin directly. It contains no widgets.

**Data layer.** Drift-generated classes (`…Row`, `…Companion`) never leave
`lib/data/db/`: DAOs (`@DriftAccessor`) are the only code that builds
queries, and they accept and return the immutable domain models of
`lib/data/models/` (mapping in `db/row_mappers.dart`). Repositories are plain
Dart — an abstract interface plus a Drift implementation that receives its
DAOs and a UTC clock (`DateTime Function()`, default
`() => DateTime.now().toUtc()`) through the constructor — and report failures
as typed `RepositoryException`s, never raw SQLite errors. Domain models use no
code generation (`freezed` and similar are not used).

**Riverpod conventions.**

- Providers live next to what they expose: repository providers in `data/`,
  screen controllers in that feature's `controllers/`.
- Prefer `Notifier` / `AsyncNotifier` over `StateProvider` for anything with
  more than a single field or a single action.
- Widgets read state with `ref.watch` and trigger behaviour with
  `ref.read(...).method()`. No business logic inside `build`.
- A single `ProviderScope` wraps the app in `main.dart`. Never hold a
  `ProviderContainer` in a global variable.
- No code generation (`riverpod_generator` / `riverpod_annotation` are not
  used). Data providers (`appDatabaseProvider`, `databaseReadyProvider`,
  repository providers) are in `lib/data/data_providers.dart`.
- Read state that only mirrors the database is a `StreamProvider` /
  `FutureProvider` (`.autoDispose`, `.family` for an id from the path), so
  screens refresh after every write. Forms use an `AsyncNotifier` family
  keyed by the edited id (`null` = create) whose `save` returns an
  `ActionResult`; controllers map exceptions to `ActionError` and widgets
  turn it into a localised message (`shared/utils/`). Never show raw
  exceptions.
- Screen-scoped state that is not in the database, such as the history
  filters, is a `Notifier` family keyed by the id from the path and
  auto-disposed with the page (`logEntryFilterProvider`).
- Deletion controllers (`…DeletionController`) are **kept alive**: the Undo
  snackbar outlives the page that deleted, so its callback holds the
  notifier, read before popping, never the page's `ref`.
- Tests override `databaseReadyProvider` and the repository providers
  (`test/support/`), never the DAOs.

**Routing.** `go_router`, configured under `app/router/`. Every route that can
be the target of a notification takes its identifiers from the path, so a
reminder can deep-link straight to the entry that produced it. Outside that
configuration, do not navigate with anonymous `MaterialPageRoute`.

- Paths are built only through `AppRoutes` (`app/router/app_routes.dart`).
- The lists live in a `StatefulShellRoute` under the `NavigationBar`
  (`HomeShell`, which also owns the add FAB). Details and forms are
  top-level routes pushed full screen on top of it; `…/new` is declared
  before `…/:id`. History entries are nested under their vehicle
  (`/vehicles/:id/entries/new`, `…/entries/:entryId`, `…/:entryId/edit`), so
  both ids are in the path; an entry reached through another vehicle's path
  is not found. Odometer readings follow the same pattern
  (`/vehicles/:id/mileage/new`, `…/mileage/:readingId/edit`). The vehicle
  page has four tabs (`VehicleTab`: history, mileage, documents, details),
  opened through the `tab` query parameter (`AppRoutes.vehicle(id, tab: …)`,
  e.g. `?tab=mileage`), and owns its FAB: "Update km" on Mileage, "Add
  document" on Documents, "New entry" otherwise. The image viewer is the
  top-level route `/attachments/:attachmentId` (`AppRoutes.attachment`). An action that outlives its page (the odometer offer) asks the
  open vehicle page for a tab through `vehicleTabRequestProvider`.
- Screens are opened with `context.push`, so Back returns to where the user
  was. A form pops with the saved id (`context.popOrGo`), which is how the
  vehicle form gets the owner created through "New owner".
- An unknown id renders a not-found page, never an exception; an unknown
  path renders the router's `errorBuilder`.
- User feedback follows `Docs/03_features.md` through
  `shared/widgets/feedback.dart`: short snackbar on save, Undo snackbar
  after a delete (shown on the app-wide `ScaffoldMessenger`), long errors
  with a close button, dialogs for confirmations and blocking explanations.
- Pickers inside a form (make, model, nationality) are full-screen dialogs
  (`showSearchablePicker`, `shared/widgets/searchable_picker.dart`), not
  routes: a transient choice with nothing to deep-link to. They always end
  with a pinned "Other…" option for free text: the list helps, never blocks.
- Long forms use `SingleChildScrollView` + `Column`, not a lazy `ListView`:
  `Form.validate` only checks fields that are built.
- An offer after a save (`showOfferSnackBar`, 8 s) runs its action after
  the form is gone: it captures the messenger, the `GoRouter` (whose
  navigator shows any dialog) and a kept-alive controller before popping.

---

## 5. Domain rules that must not be broken

These encode decisions already taken. Changing them requires an explicit
decision, not a refactor.

### Vehicles and owners
- Multiple vehicles, each linked to one owner.
- An owner carries personal documents (driving licence, ID card, residence
  permit) with expiry dates that feed reminders.

### Log entries
- **One unified entry model.** A single base entry (date, mileage, cost, notes,
  photos, optional reminder) plus type-specific extra fields. Do **not** create
  a separate table per entry type.
- Types: maintenance, repair, refuelling, expense, inspection, legal deadline,
  note.

### Maintenance
- A shared catalogue of maintenance types; each vehicle has its own rules drawn
  from it.
- A maintenance type already assigned to a vehicle disappears from that
  vehicle's picker.
- Intervals may be km-based, time-based, or both. When both are set, **the
  first of the two to fall due wins**.
- Brakes are modelled **per axle**: disc + pads, or drum + shoes. Each
  component has its own independent deadline.

### Measurement checks
- Numeric value + unit (tyre tread, pad thickness, battery voltage, …), stored
  as history, with an optional low threshold that triggers an alert.

### Fuel economy
- Computed **per fill-up and self-contained**: km driven ÷ litres for that
  fill-up. It is **not** derived from the distance between two consecutive
  fill-ups.
- Total fuel spend is **not** auto-computed. The user stays in control.

### Archived vehicles
- Archive ≠ Trash: the Trash is a mistake (purged after 30 days), the
  archive is an end (kept forever). The two states are independent: an
  archived vehicle can go to the Trash and comes back archived.
- Archived = **strictly read-only** (vehicle, entries, readings,
  attachments), enforced in the repositories, not only in the UI. The only
  actions are Reactivate (always allowed, no confirmation, touches no
  reading) and Move to Trash.
- Archived vehicles are excluded from everything "current" (main list,
  default selections and, in step 11, reminders) through the single
  `VehiclesDao.isActive` filter. The owner page still lists them, folded.
- The final km of an archive **is** an odometer reading, inserted by the
  normal reading path under its rules; `archived_km` is only its snapshot.
- Reasons are a fixed list (`ArchiveReason`), never free text.

### Odometer history (`MileageReading`)
- An independent series, separate from log entries by design.
- Updated **only** by an explicit user action. Mileage recorded on a log entry
  is **never** automatically pushed into this series — the isolation exists to
  prevent uncorrectable errors.
- Deletion is allowed **only for the last reading**, in reverse chronological
  order.

### Audit log
- Every create, modify and delete is recorded with timestamp and operation
  type, and kept for future reference.

### Backup and sync ("Strada A")
- Backup / restore with a **version guard**. No automatic merging, ever.
- The database carries a version number and a last-modified timestamp.
- Cloud newer than local → offer download (local is replaced).
- Local newer than cloud → offer upload (cloud is replaced).
- **Both changed since the last common point** → warn honestly that either
  direction loses data, and let the user choose. Never resolve silently.
- The only automatic action is the upload at start when only the local
  data changed or there is no cloud copy; download is never automatic.
- Two account-linking modes: the system account picker (step 9), and manual
  OAuth 2.0 + PKCE through the system browser for an app-only account
  (step 9b, public Android client, no client secret ever). One mode linked
  at a time; changing mode needs an unlink.
- **Tokens only in secure storage.** Mode 1 stores no token at all. Mode 2
  stores its refresh token, and nothing else, through
  `flutter_secure_storage` (Android Keystore). Never in the `settings`
  table, never in the database, never in a file or plain preferences,
  never logged (nor authorisation codes or token responses).
- Unlinking mode 2 revokes the token at Google and wipes the secure storage
  even when the revocation fails (then the user is told).

---

## 6. UI and theming

- Material 3, with **one seed colour** generating both the light and the dark
  palette.
- Default to the OS theme, with a user override in settings.
- Reports (expenses, by type, fuel, general) are exportable to PDF.
- Time-based deadlines produce local notifications; km-based ones are surfaced
  through visual highlighting, not notifications.

---

## 7. Localisation

- Supported locales: **it**, **es**, **en**.
- `gen_l10n` with `.arb` files under `lib/l10n/`, configured by `l10n.yaml` at
  the repository root. The generated `AppLocalizations` classes are written to
  `lib/l10n/` too (no synthetic package).
- **Template language: English.** `app_en.arb` is the template: it defines
  every key, each with an `@key` description. `app_it.arb` and `app_es.arb`
  carry the same keys.
- **Fallback locale: `en`.** The device locale is matched by language code
  (`it_CH` → `it`); any other language falls back to English.
- **Generated files are not committed.** `lib/l10n/app_localizations*.dart` is
  git-ignored: with `generate: true` in `pubspec.yaml`, `flutter pub get`
  regenerates them (already formatted, `format: true` in `l10n.yaml`), which is
  all CI needs before analysing.
- Add every new string to all three `.arb` files in the same change. A missing
  translation is a bug, not a follow-up.
- Dates, numbers and currency are formatted through `intl`, never by hand.

---

## 8. Quality gates

Before reporting a task as finished:

```
dart format .
flutter analyze     # must be clean
flutter test
```

`analysis_options.yaml` enables `flutter_lints` plus a stricter set including
`prefer_const_constructors`, `public_member_api_docs`,
`require_trailing_commas` and `avoid_print`. Do not disable a lint to make
output green — raise it instead.

### What deserves a test

Depth is deliberate, not uniform. Put the effort where a silent bug is
expensive and the user cannot spot it by eye.

- **Repositories — always.** Unit tests against an in-memory Drift database.
- **Domain logic — always, thoroughly.** Due-date computation (km, time, and
  the "first of the two to fall due wins" rule), per-axle brake sub-deadlines,
  per-fill-up fuel economy, the odometer rules (no reading lower than the last
  one, deletion only of the most recent) and the backup version guard.
- **Schema migrations — always**, against the committed schema dumps.
- **Widgets — sparingly.** One smoke test per screen that it builds, plus a
  test for genuinely tricky interaction. Do not write widget tests that merely
  restate the widget tree.

Coverage percentage is not a target and must not be used as one.

---

## 9. Working method

- Work in small, reviewable steps. Finish one, show it, stop.
- Show the list of files created or modified at the end of every task.
- Never proceed to the next step on your own initiative.
- Prefer editing existing files over creating parallel ones.
- Keep this file up to date when a technical convention changes.
- **Phone test session before the merge** for every step with visible UI:
  the assistant installs the debug build on the owner's phone
  (`fvm flutter run` / `adb`), keeps the logs open, and takes screenshots
  with `adb exec-out screencap -p` when useful; the owner reports what they
  see, and the assistant fixes and reinstalls until the owner is satisfied.
  Test data only until roadmap step 6 (export / import and the release key).
- **Phone safety.** Install and run **only** on the owner's phone, Xiaomi
  model `22101316G`. Before every install, check `adb devices -l` and the
  model (`adb -s <serial> shell getprop ro.product.model`); always pass
  `-s <serial>` / `-d <id>`. If another device is listed or the model does
  not match, **stop and ask**. Never connect to, install on, or run commands
  against any other device found on the network. Install over the existing
  app (`adb install -r` / `fvm flutter run`), **never uninstall**: that
  deletes the data.
- **Language of communication.** The assistant talks to the owner in
  **Spanish**. Code, identifiers, comments, commit messages and PR texts stay
  in **English**; `Docs/` is in **Spanish**.

---

## 10. Contribution workflow

`main` is protected by a repository ruleset (`main-protection`): direct
pushes are rejected, and force pushes and branch deletion are blocked.

- Every change starts from an up-to-date `main`, on a dedicated branch named
  `<type>/<short-kebab-description>`, where `<type>` is one of `feature`,
  `fix`, `chore`, `docs`, `test`, `refactor`.
- Open a pull request towards `main`; the PR template checklist applies.
- Merging requires the `analyze-and-test` check to be green **and** the
  branch to be up to date with `main` (strict status checks).
- No required reviewers: the single developer self-merges once CI is green.

At the end of every task the assistant runs this cycle itself, within the
hard limits of §3 rule 6:

1. Commit (no AI attribution) and `git push -u origin <branch>`.
2. `gh pr create --base main`, filling `.github/pull_request_template.md`.
3. `gh pr checks --watch`. If the branch is behind `main`,
   `gh pr update-branch` and wait again. If CI is red, read
   `gh run view --log-failed`, fix on the branch, push, and wait (at most two
   rounds before stopping to ask).
4. Green → `gh pr merge --squash --delete-branch`, subject = PR title, short
   body, no `Co-authored-by` lines.
5. `git switch main && git pull`, and delete the local branch.

---

## 11. Data type conventions

Decided. Do not introduce a second representation alongside these.

### Money

Monetary amounts are stored as **integer cents** (`int`), never as `double`.
Floating point accumulates error across sums, and this app sums costs in the
expense report, the fuel report and the per-vehicle totals.

Conversion happens only at the boundary: in the formatter on the way out and in
the input parser on the way in (`shared/utils/money.dart`). Never do
arithmetic on a formatted value. The parser takes at most two decimals and
either `,` or `.` as the decimal separator (some keyboards offer only one),
never a thousands separator, so an ambiguous `1.234` is refused rather than
misread.

The currency is the **euro**, fixed — there is no currency column and no
currency setting (see `Docs/02_data_model.md`). Formatting still follows the
selected locale through `intl`: the same amount renders as `1.234,56 €` in
Italian and Spanish, and `€1,234.56` in English.

### Dates and timestamps

Two different things, handled differently on purpose.

- **Calendar dates** — the date of a service, a refuelling, a document expiry,
  an odometer reading. These are days, not instants: a service done on 4 March
  stays on 4 March whatever timezone the phone is in. Stored with no timezone
  and no time component, and never converted between timezones.
- **Technical timestamps** — `created_at`, `updated_at`, backup metadata.
  These are instants, stored in **UTC**, converted to local time only for
  display.

Never compare a calendar date directly against a technical timestamp, and never
derive one from the other by truncation without an explicit conversion.

All date and number formatting goes through `intl`. Never assemble a date
string by hand.

### Physical quantities

All physical quantities are stored in SI: distances in **km**, volumes in
**litres**, temperatures in **°C**, pressures in **bar**, fuel consumption
in **L/100 km**. The database, the repositories, the domain rules and the
backup package never see any other unit. Units are a UI concern handled
exclusively by the unit formatter (`UnitFormatter`, §2 "Units of
measurement"): user input is parsed through it and every displayed value
is formatted through it, in the units chosen in Settings. **Never
concatenate a unit symbol by hand** in a screen, widget, dialog, ARB string
or report: symbols come from the formatter, and a grep for stray `km`,
`L`, `°C`, `bar`, `mpg` in `lib/` is part of reviewing any UI change.

### Identifiers

Primary keys are device-generated UUIDs, as required by
`Docs/02_data_model.md`, not auto-increment integers: UUID v4 from the `uuid`
package, stored as a `TEXT` primary key.

### Storage of dates and enums

- **Technical timestamps** are `DateTime` in UTC, stored as ISO-8601 text.
  Repositories take their time from the injected UTC clock.
- **Calendar dates** are the `CalendarDate` value type (year, month, day),
  stored as `yyyy-MM-dd` text through a `TypeConverter`. Never a `DateTime`.
- **Enums** are stored as text through a `TypeConverter` with explicit codes,
  never through `Enum.name` or the index, so renaming a Dart value cannot
  change what is on disk.
