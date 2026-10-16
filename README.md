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

- Multiple vehicles, each linked to an owner (with owner documents: licence, ID,
  residence permit — with expiry reminders)
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
`go_router`: lists, details, forms, delete with confirmation and Undo). Next
is step 4.

Roadmap to the first usable version:

| Step | Content |
| --- | --- |
| 3 | ~~Vehicles **and owners** screens (Riverpod + `go_router`) — a vehicle requires an owner~~ — done |
| 4 | Basic log entries: date, km, type, cost, notes; list, filters, undo on delete |
| 5 | Odometer: update current km + `MileageReading` history with its rules |
| 6 | Export / import the database file, and a fixed release signing key kept outside the repo |

Then, in an order decided while using the app: settings, maintenance,
refuelling, documents, photos, reminders, PDF reports, Google Drive backup.

Why the signing key matters: each PC has its own debug key, so installing
from another PC forces an uninstall, which deletes the data.

## License

No licence is granted. All rights reserved.

This is a personal project published for reference only: the source can be
read, but it may not be reused, redistributed or derived from without explicit
written permission. The absence of a licence file is deliberate, not an
oversight.
