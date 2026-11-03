-- Loads ONE reminder from the manufacturer's manual into the database of an
-- exported backup package (schema v11). The procedure that runs it is in
-- Docs/08_recordatorios.md, section "Carga desde el manual (procedimiento)",
-- and test/unit/data/reminders_runbook_sql_test.dart runs this very file.
--
-- Run the three statements in the same transaction, once per approved
-- reminder, with PRAGMA foreign_keys = ON. They are separated by semicolons,
-- and the comments contain neither semicolons nor colons, so a plain split
-- gives the statements.
--
-- Named parameters, bound by name (a dict in Python sqlite3)
--   id                  UUID v4, lowercase, of the reminder
--   change_id           UUID v4 of its create history row
--   audit_id            UUID v4 of its create audit row
--   now                 UTC instant, in the exact text format of an existing
--                       timestamp of the same file, the same in the 3 rows
--   vehicle_id          id of the live, active vehicle
--   kind                ReminderKind code, such as engine_oil or other
--   title               title shown in the app, never blank
--   note                free note or NULL (severe-use intervals go here)
--   manual_ref          where in the manual, or NULL
--   ref_interval_km     interval in km (SI), or NULL
--   ref_interval_months interval in months, or NULL
--   due_date            yyyy-MM-dd of a one-shot reminder, else NULL
--   last_done_date      yyyy-MM-dd anchor day of a recurring one, else NULL
--   last_done_km        anchor km (SI), required with a km interval
--
-- What the owner decides in the app is never written here. The source is
-- generated. Override, snooze, own lead, last entry and completion stay NULL.

INSERT INTO reminders (
  id, created_at, updated_at, deleted, deleted_at,
  vehicle_id, kind, title, note, source, manual_ref,
  ref_interval_km, ref_interval_months, due_date,
  last_done_date, last_done_km, last_entry_id,
  override_active, applied_interval_km, applied_interval_months,
  override_reason, override_at, lead_days, lead_km,
  snooze_until_date, snooze_until_km, snooze_reason, completed_at
) VALUES (
  :id, :now, :now, 0, NULL,
  :vehicle_id, :kind, :title, :note, 'generated', :manual_ref,
  :ref_interval_km, :ref_interval_months, :due_date,
  :last_done_date, :last_done_km, NULL,
  0, NULL, NULL,
  NULL, NULL, NULL, NULL,
  NULL, NULL, NULL, NULL
);

-- The first row of the reminder's history, with its state after the create.
INSERT INTO reminder_changes (
  id, reminder_id, changed_at, change_type, reason, entry_id,
  due_date, last_done_date, last_done_km,
  ref_interval_km, ref_interval_months,
  override_active, applied_interval_km, applied_interval_months,
  snooze_until_date, snooze_until_km
) VALUES (
  :change_id, :id, :now, 'create', NULL, NULL,
  :due_date, :last_done_date, :last_done_km,
  :ref_interval_km, :ref_interval_months,
  0, NULL, NULL,
  NULL, NULL
);

-- The audit row of the create, as every write of the app adds.
INSERT INTO audit_log (id, entity_type, entity_id, operation, at)
VALUES (:audit_id, 'reminder', :id, 'create', :now);
