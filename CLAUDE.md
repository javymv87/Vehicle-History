# CLAUDE.md — Vehicle-History development guide

This file is the operating manual for any AI assistant or developer working on
this repository. Read it **before** writing or changing code.

The conceptual documentation in [`Docs/`](Docs/) (Italian) is the **source of
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

Flutter · Drift (SQLite) · `googleapis` (Google Drive) · `google_sign_in` /
`flutter_appauth` · `flutter_secure_storage` · `flutter_local_notifications` ·
`gen_l10n` · Material 3

Toolchain reference (recorded at scaffold time): **Flutter 3.44.8** (stable
channel) · **Dart 3.12.2**.

Dependencies are added **one at a time, on explicit request**. Never add a
package as a side effect of implementing a feature.

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
6. **No Git side effects.** No `add`, `commit`, `push`, branch switching or
   history rewriting unless explicitly requested.

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
    backup/              # Google Drive backup & restore
  features/
    vehicles/            # pages/ widgets/ controllers/
    owners/              # pages/ widgets/ controllers/
    entries/             # pages/ widgets/ controllers/
    maintenance/         # pages/ widgets/ controllers/
    mileage/             # pages/ widgets/ controllers/
    reminders/           # pages/ widgets/ controllers/
    reports/             # pages/ widgets/ controllers/
    settings/            # pages/ widgets/ controllers/
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

Docs/                    # Italian conceptual documentation (source of truth)
CLAUDE.md                # this file
README.md                # public project description
```

**Layering rule.** Models, database and repositories live **only** in `data/`
and are shared between features. Everything under `features/` is presentation:
screens, feature-local widgets, and the state that drives them. A feature never
talks to the database directly — always through a repository.

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
- Two account-linking modes: the system account picker, and manual
  OAuth 2.0 + PKCE through the system browser for an app-only account.
- Tokens are stored via `flutter_secure_storage` (Android Keystore). Never in
  plain preferences, never in the database, never logged.

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
- `gen_l10n` with `.arb` files under `lib/l10n/`.
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

---

## 9. Working method

- Work in small, reviewable steps. Finish one, show it, stop.
- Show the list of files created or modified at the end of every task.
- Never proceed to the next step on your own initiative.
- Prefer editing existing files over creating parallel ones.
- Keep this file up to date when a technical convention changes.

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
