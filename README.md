# Vehicle History

Offline-first Flutter app to track the full service history of one or more
vehicles — maintenance, refuelling, expenses, inspections, deadlines and
documents — with optional Google Drive backup and per-vehicle reports (PDF
export planned).

## Overview

A single-user, offline-first mobile app (Android first, built with Flutter so
iOS stays possible later) for keeping a complete digital history of one or more
vehicles. It replaces the paper service booklet and the shoebox of receipts:
log maintenance, repairs, refuelling, inspections, expenses, legal deadlines and
documents, then see per-vehicle reports and in-app reminders (phone
notifications and PDF export are planned). Data lives on the device and can be backed up to Google Drive to
move between phones.

## Key features

- Multiple vehicles — cars, vans, motorcycles and mopeds — each linked to an
  owner, with documents attached to vehicles and owners (document expiry
  dates: planned)
- Make and model picked from a bundled offline catalogue, or typed by hand
- Unified log of dated entries: maintenance, repairs, refuelling, expenses,
  inspections, legal deadlines, notes — each with mileage, cost and photos
- Fuel consumption by the full-tank chain, from the odometer km of each
  refuel (bi-fuel LPG / CNG vehicles keep one chain per fuel), with the
  amount / volume / price triangle in the refuel form
- Independent odometer history with its rules
- Per-vehicle Reports tab: consumption with an explicit coverage line, fuel
  spend by month, distance over time — filtered by dates or odometer range
- Units of measurement (km / miles, litres / gallons, …) with SI storage
- Reminders per vehicle from a fixed catalogue of maintenance and legal
  items, with km- and/or time-based intervals ("first of the two wins") or a
  single due date: the manufacturer's reference criterion kept next to any
  custom one (with its reason), postpone with a reason, a change history,
  status computed on every read, closed only through an entry; loaded from
  the manual by a documented procedure
- Archived vehicles, a 30-day Trash and an audit log
- Planned: local notifications for time-based deadlines (km-based ones are
  highlighted in the app); an editable maintenance catalogue; measurement
  checks with low-threshold alerts; PDF reports (expenses, by type, fuel,
  general) for resale
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
independently of the Trash. Step 11 added units of measurement (schema
v9): in Settings, an International / Imperial preset and the five
quantities (distance, volume, temperature, pressure, consumption) one by
one; everything that shows or asks for a distance is typed and read in the
chosen unit, while the database always stores km (and litres, °C, bar) and
knows nothing about units, with the distance columns as `REAL` so that
100 mi come back as 100 mi. Step 12 added fuel consumption (schema v10):
refuels carry a volume (litres, or kg for CNG), a full-tank flag, a
missed-refuel flag and a fuel (chosen on bi-fuel vehicles), with the amount /
volume / price triangle in the form; consumption is derived, never stored, by
the full-tank chain from the odometer km of each refuel, and shows after
saving, in the refuel detail and in each vehicle's new Reports tab
(consumption with its coverage line, fuel spend and distance over time,
filtered by dates or odometer range); the Mileage tab also shows the days
between readings. Step 13a added reminders inside the app (schema v11): a
Reminders destination on Home with an overdue / due-soon badge, a Reminders
tab per vehicle, the reference criterion and an optional applied one (with
a reason, never losing the reference), postpone with a reason, a history of
every change, the status computed on every read, closing through an entry
("Closes the reminder" or "Mark done") and the warning lead in Settings;
archived vehicles are left out. Reminders are loaded from the manual by a
documented procedure that writes into an exported package. Version 0.13.1
reworked those screens: Home lists only what is overdue or due soon, the
reminder detail is one card per question with a status card tinted by the
state, and the texts follow shared rules (years for multiples of 12 months,
"left / ago"). Version 0.13.2 moved the pieces of those screens into shared
archetype widgets (card, status card, list row, sectioned list, dialog, form
section) with no visible change, so the other screens can be rebuilt on
them. Version 0.14.0 (step 14b) rebuilt the three detail screens on them, the
vehicle's Details tab, the entry detail and the owner page: one card per
question, the most important first, with everything shown before still
shown. Next are local notifications (13b).

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
| 10 | ~~Archived vehicles: reason, date, final km as a reading, read-only, reactivate (schema v8)~~ — done |
| 11 | ~~Units of measurement: setting, SI storage, a single formatter (schema v9)~~ — done |
| 12 | ~~Fuel consumption (full-tank chain), refuel fields (schema v10) and per-vehicle Reports~~ — done |
| 13a | ~~Reminders inside the app (table, list, states, mark as done; archived vehicles excluded; schema v11)~~ — done |
| 13b | Local notifications (`flutter_local_notifications`, deep links) |

Then (14+), in an order decided while using the app: measurements, the
maintenance catalogue, documents, PDF reports (built on the step-12
Reports).

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
