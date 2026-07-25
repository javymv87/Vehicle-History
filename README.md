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

Flutter · Drift (SQLite) · Google Drive (googleapis) · google_sign_in /
flutter_appauth · flutter_secure_storage · flutter_local_notifications · gen_l10n

## Project structure

```
lib/            # application code (see CLAUDE.md for the full layout)
Docs/           # Italian conceptual documentation (source of truth)
CLAUDE.md       # development guide and rules (English)
```

## Documentation

The full concept and design decisions live in [`Docs/`](Docs/) (in Italian).
Start from [`Docs/00_README.md`](Docs/00_README.md). Development rules and
conventions are in [`CLAUDE.md`](CLAUDE.md) (in English).

## Language policy

- Code, identifiers and comments: **English**
- User-facing strings: **externalised** (IT / ES / EN)
- Conceptual documentation (`Docs/`): **Italian**

## Status

Concept complete, documented before writing code. Next step: scaffold the
Flutter project following the structure in `CLAUDE.md`.

## License

_To be defined._