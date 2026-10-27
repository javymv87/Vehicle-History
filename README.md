# Vehicle History

Offline-first Flutter app to track the full service history of one or more
vehicles — maintenance, refuelling, expenses, inspections, deadlines and
documents — with optional Google Drive backup and PDF reports.

## Overview

A single-user, offline-first mobile app (Android first, built with Flutter so
iOS stays possible later) for keeping a complete digital history of one or more
vehicles. It replaces the paper service booklet and the shoebox of receipts:
log maintenance, repairs, refuelling, inspections, expenses, legal deadlines and
documents, then get reminders and exportable PDF reports. Data lives on the
device and can be backed up to Google Drive to move between phones.

## Key features

- Multiple vehicles — cars, vans, motorcycles and mopeds — each linked to an
  owner (with owner documents: licence, ID, residence permit — with expiry
  reminders)
- Make and model picked from a bundled offline catalogue, or typed by hand
- Unified log of dated entries: maintenance, repairs, refuelling, expenses,
  inspections, legal deadlines, notes — each with mileage, cost, photos and
  optional reminders
- Per-vehicle maintenance rules from a shared catalogue, with km- and/or
  time-based intervals ("first of the two wins")
- Per-axle brake modelling (disc+pads / drum+shoes) with independent component
  deadlines
- Measurement checks (tyre tread, pad thickness, battery voltage…) with history
  and low-threshold alerts
- Self-contained fuel economy per fill-up, plus average-consumption and
  fuel-spend reports
- Independent odometer history for a km-driven-over-time report
- Reports (expenses, by type, fuel, general) exportable to PDF — useful for
  resale
- Local notifications for time-based deadlines; visual highlighting for
  km-based ones
- Optional Google Drive backup with a version guard; two account-linking modes
  (system account picker and manual OAuth for an app-only account)
- Multilingual UI: Italian, Spanish, English

## Tech stack

Flutter · Riverpod · go_router · Drift (SQLite) · Google Drive (googleapis) · google_sign_in /
flutter_appauth · flutter_secure_storage · flutter_local_notifications · gen_l10n

## Project structure

```
lib/            # application code (see CLAUDE.md for the full layout)
Docs/           # Spanish conceptual documentation (source of truth)
CLAUDE.md       # development guide and rules (English)
```

## Documentation

The full concept and design decisions live in [`Docs/`](Docs/) (in Spanish).
Start from [`Docs/00_README.md`](Docs/00_README.md). Development rules and
conventions are in [`CLAUDE.md`](CLAUDE.md) (in English).

## Language policy

- Code, identifiers and comments: **English**
- User-facing strings: **externalised** (IT / ES / EN)
- Conceptual documentation (`Docs/`): **Spanish**

## Status

Concept documented and Flutter project scaffolded: folder structure, strict
lint rules, CI and the conceptual documentation in `Docs/` are all in place.
The Material 3 theme (single seed, light/dark, status colours) and the
`gen_l10n` localisation skeleton (IT / ES / EN) are done, and so is the Drift
data layer for owners and vehicles (with the audit log, schema migrations from
v1 and repositories) and the vehicle and owner screens (Riverpod +
`go_router`: lists, details, forms, delete with confirmation and Undo).
Step 3b added the vehicle kind (car, van, motorcycle, moped), the make / model
catalogue, model year, version and the nationality picker, with the first real
schema migration (v1 → v2). Step 4 added the vehicle history (schema v3):
each vehicle opens on its history, with quick entry creation, month grouping,
detail, edit, delete with Undo, and filters by date range, type and text.
Step 5 added the odometer (schema v4): a Mileage tab with the readings, one
initial reading per vehicle, "Update km", delete-last with Undo, the offer
to update the odometer from an entry, and future dates allowed per entry
type. Step 5b added the Trash (schema v5): `deleted_at` on every
soft-deletable table, a delete dialog that says what goes with the vehicle,
the Trash screen (restore, delete permanently, empty) and the automatic
30-day cleanup at app start. Step 6 added the backup package (export /
import of all the data as a `.zip`, with validation, a newer-schema refusal,
migration of older ones and a safety copy that is restored if the import
fails), the `settings` table (schema v6), the Backup screen and a fixed
signing key for debug and release builds. Step 7 added the Settings screen:
in-app language (System, Italiano, Español, English) and theme (System,
Light, Dark), applied at once and carried inside the backup package. Step 8
added attachments (schema v7): photos and documents on entries, vehicles (a
Documents tab) and owners, from the camera, the gallery or a file, with a
viewer, "Save to…" and physical delete with the Trash; the backup package
now carries every file, is exported streamed through a native "save as",
and an import restores the attachments folder too if it fails. Step 9
added the Google Drive copy: link the phone's account, Upload to Drive and
Restore from Drive (through the same import and its safety net), the last 3
copies in a visible folder, the version guard with its status line (and a
home banner when another phone uploaded a newer copy) and a single automatic
action: an upload at start when only this phone changed. Step 9b added the
second way to link the account: signing in in the browser (OAuth + PKCE)
with an account that is not added to the phone. Its refresh token is kept
only in the secure storage and revoked at Google on unlink. Step 10 added
archived vehicles (schema v8): archive a sold, scrapped or stolen vehicle
with a reason, a date, final km (recorded as a normal odometer reading) and
a note; it leaves the main list for an "Archived (n)" row, stays fully
visible but read-only behind a banner, and can be reactivated at any time,
independently of the Trash. Next is step 11 (reminders), built knowing
which vehicles are archived.

Roadmap to the first usable version:

| Step | Content |
| --- | --- |
| 3 | ~~Vehicles **and owners** screens (Riverpod + `go_router`) — a vehicle requires an owner~~ — done |
| 3b | ~~Vehicle kind, make / model catalogue, year, version, nationality picker (schema v2)~~ — done |
| 4 | ~~Basic log entries: date, km, type, cost, notes; list, filters, undo on delete (schema v3)~~ — done |
| 5 | ~~Odometer: update current km + `MileageReading` history with its rules (schema v4)~~ — done |
| 5b | ~~Trash: deleted vehicles, restore, permanent delete, 30-day cleanup (schema v5)~~ — done |
| 6 | ~~Export / import as a package, `settings` table (schema v6), fixed signing key for debug and release~~ — done |
| 7 | ~~Settings screen: in-app language and theme~~ — done |
| 8 | ~~Attachments (entries, vehicles, owners), backup package with the files (schema v7)~~ — done |
| 9 | ~~Google Drive backup with the startup version guard~~ — done |
| 9b | ~~Link an account manually (browser, OAuth + PKCE, token in the secure storage)~~ — done |

Then, in an order decided while using the app: maintenance, refuelling,
documents, reminders, PDF reports.

Why the signing key matters: each PC has its own debug key, so installing
from another PC forces an uninstall, which deletes the data.

## Credits

- **Vehicle data by [VehiclesDB](https://vehiclesdb.com) (CC BY 4.0), built
  from official public registers.** The make / model catalogue in
  `assets/catalog/` is a projection of a pinned VehiclesDB release; its
  licence and the upstream register notices are in
  `assets/catalog/LICENSE.md` and `assets/catalog/ATTRIBUTION.md`, and are
  shown in the app under About → licences.
- **Country names from [Unicode CLDR](https://cldr.unicode.org)**, under the
  Unicode License v3 (`assets/countries/LICENSE.md`).

These data files keep their own licences; the "all rights reserved" notice
below covers the rest of the repository.

## License

No licence is granted. All rights reserved.

This is a personal project published for reference only: the source can be
read, but it may not be reused, redistributed or derived from without explicit
written permission. The absence of a licence file is deliberate, not an
oversight.
