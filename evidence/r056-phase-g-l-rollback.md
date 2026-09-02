# Phase G-L Rollback / Abort Procedure

**Mission:** `2026-08-29-fleetconnect-operational-recovery`
**Round:** r056 Phase G-L executable Wave 4 data/auth remap package
**Predecessors:** Lux 2675123e… (G-K accept + Wave 4 import/remap blocker); Lux 45d7853b… (G-L schema-repair approval)

This document describes the staged rollback/abort for each step of the Wave 4
executable package. All actions are Founder-authenticated; PRIME does not
execute on the live target project.

## Decision tree

```
Step 1 (additive migration 20260902000001)  ── ABORT  → §A  (DROP COLUMN legacy_user_id)
Step 2 (staging-transform import            ── ABORT  → ROLLBACK transaction (no commit)
                                                  → staging tables dropped
                                                  → §B.1 (if already committed)
Step 3 (mapping-apply 20260902000003        ── ABORT  → ROLLBACK transaction
                                                  → §B.2 (if already committed)
Step 4 (verification queries return >0      ── ABORT  → §B.3 / §B.4
                  on V1/V2/V3/V4)
```

---

## §A — Drop additive `legacy_user_id` columns (only if backfill is NOT done)

If the additive migration (`20260902000001_phase_g_l_legacy_user_id_audit_column.sql`)
has been applied but the staging-transform import has NOT yet populated any
`legacy_user_id` values, the columns can be safely dropped. Verify zero
non-null values first:

```sql
-- PRE-CHECK: must return 0 for all 5 tables
SELECT 'customers'      AS tbl, count(*) FILTER (WHERE legacy_user_id IS NOT NULL) AS non_null FROM public.customers
UNION ALL SELECT 'partners',       count(*) FILTER (WHERE legacy_user_id IS NOT NULL) FROM public.partners
UNION ALL SELECT 'drivers',        count(*) FILTER (WHERE legacy_user_id IS NOT NULL) FROM public.drivers
UNION ALL SELECT 'onderaannemers', count(*) FILTER (WHERE legacy_user_id IS NOT NULL) FROM public.onderaannemers
UNION ALL SELECT 'bookings',       count(*) FILTER (WHERE legacy_user_id IS NOT NULL) FROM public.bookings
ORDER BY tbl;
```

If all counts are 0:

```sql
DROP INDEX IF EXISTS idx_customers_legacy_user_id;
DROP INDEX IF EXISTS idx_partners_legacy_user_id;
DROP INDEX IF EXISTS idx_drivers_legacy_user_id;
DROP INDEX IF EXISTS idx_onderaannemers_legacy_user_id;
DROP INDEX IF EXISTS idx_bookings_legacy_user_id;

ALTER TABLE public.customers      DROP COLUMN IF EXISTS legacy_user_id;
ALTER TABLE public.partners       DROP COLUMN IF EXISTS legacy_user_id;
ALTER TABLE public.drivers        DROP COLUMN IF EXISTS legacy_user_id;
ALTER TABLE public.onderaannemers DROP COLUMN IF EXISTS legacy_user_id;
ALTER TABLE public.bookings       DROP COLUMN IF EXISTS legacy_user_id;
```

If any count > 0: do NOT drop the column. Use §B instead.

---

## §B — Rollback after backfill / committed mapping-apply

### §B.1 — Rollback staging-transform import (legacy_user_id populated, mapping-apply not run)

`legacy_user_id` was populated on import. `user_id` is still NULL everywhere
or partially set. Mapping-apply has not run or has not committed.

**Preferred path:** if mapping-apply has not committed, ROLLBACK that
transaction. `user_id` reverts to NULL. `legacy_user_id` remains as the
audit trail of the failed import.

**If mapping-apply committed but verification flagged issues:** proceed to §B.2.

### §B.2 — Rollback mapping-apply (target user_id set on rows, but commit proceeded)

`user_id` is set on some/all rows. To revert:

```sql
-- Verify zero target user_id rows exist that would be orphaned by a NULL reset.
-- (i.e., V2 verification queries return 0 currently.)
-- Founder confirms before this query.

UPDATE public.customers
  SET user_id = NULL
  WHERE legacy_user_id IS NOT NULL;

UPDATE public.partners
  SET user_id = NULL
  WHERE legacy_user_id IS NOT NULL;

UPDATE public.drivers
  SET user_id = NULL
  WHERE legacy_user_id IS NOT NULL;

UPDATE public.bookings
  SET user_id = NULL
  WHERE legacy_user_id IS NOT NULL;

-- Re-run V4 verification queries. Expect all counts = 0 again.
-- legacy_user_id audit column remains intact.
```

After §B.2, re-validate the mapping CSV (`evidence/r056-phase-g-l-auth-user-id-mapping.csv`),
fix any rows that produced unmapped-user results, re-run
`20260902000003_phase_g_l_mapping_apply.sql`, and re-run verification.

### §B.3 — Drop the additive migration entirely (full reset)

If the Wave 4 attempt is being abandoned and the additive audit column
should also be removed (after a confirmed-safe state where no application
code reads `legacy_user_id`):

```sql
-- PRE-CHECK: must return 0 (no rows with legacy_user_id NOT NULL)
SELECT 'customers'      AS tbl, count(*) FILTER (WHERE legacy_user_id IS NOT NULL) AS n FROM public.customers
UNION ALL SELECT 'partners',       count(*) FILTER (WHERE legacy_user_id IS NOT NULL) FROM public.partners
UNION ALL SELECT 'drivers',        count(*) FILTER (WHERE legacy_user_id IS NOT NULL) FROM public.drivers
UNION ALL SELECT 'onderaannemers', count(*) FILTER (WHERE legacy_user_id IS NOT NULL) FROM public.onderaannemers
UNION ALL SELECT 'bookings',       count(*) FILTER (WHERE legacy_user_id IS NOT NULL) FROM public.bookings
ORDER BY tbl;

-- Only if all counts are 0:
DROP INDEX IF EXISTS idx_customers_legacy_user_id;
DROP INDEX IF EXISTS idx_partners_legacy_user_id;
DROP INDEX IF EXISTS idx_drivers_legacy_user_id;
DROP INDEX IF EXISTS idx_onderaannemers_legacy_user_id;
DROP INDEX IF EXISTS idx_bookings_legacy_user_id;

ALTER TABLE public.customers      DROP COLUMN IF EXISTS legacy_user_id;
ALTER TABLE public.partners       DROP COLUMN IF EXISTS legacy_user_id;
ALTER TABLE public.drivers        DROP COLUMN IF EXISTS legacy_user_id;
ALTER TABLE public.onderaannemers DROP COLUMN IF EXISTS legacy_user_id;
ALTER TABLE public.bookings       DROP COLUMN IF EXISTS legacy_user_id;
```

### §B.4 — Per-row unmapped-user recovery

If V4 returns non-zero (some rows have `legacy_user_id NOT NULL` but
`user_id IS NULL` after mapping-apply), use the V5 unmapped-user report
query (in `20260902000004_phase_g_l_verification_queries.sql`) to list
the offending rows. For each:

1. Confirm the legacy user account is operationally required (operator,
   partner, driver, customer who needs to sign in).
2. Founder-authenticated: create the user in the target project via
   Option C1 Dashboard (NOT Option C2 direct SQL — REMOVED per Lux
   39ca1a0 §5).
3. Record the new `auth.users.id` in `evidence/r056-phase-g-l-auth-user-id-mapping.csv`.
4. Re-run `20260902000003_phase_g_l_mapping_apply.sql` (idempotent: only
   updates rows where `user_id IS NULL` and `legacy_user_id` matches).
5. Re-run V4 verification. Expect all counts = 0.

If a row's legacy user is NOT operationally required (e.g. test accounts,
deprecated users), it may remain with `user_id IS NULL` and
`legacy_user_id NOT NULL` as the audit-trail record. Document this in
the Wave 4 completion report (`evidence/r056-phase-g-l-wave4-completion-report.md`).

---

## §C — Abort during the import transaction

The import and transform run inside a single psql transaction:

```sql
BEGIN;
\copy staging.customers (...) FROM '/secure/path/fc-customers.csv' CSV HEADER
\copy staging.partners  (...) FROM '/secure/path/fc-partners.csv'  CSV HEADER
\copy staging.drivers   (...) FROM '/secure/path/fc-drivers.csv'   CSV HEADER
\copy staging.bookings  (...) FROM '/secure/path/fc-bookings.csv'  CSV HEADER

INSERT INTO public.customers ... SELECT ... FROM staging.customers ...;
INSERT INTO public.partners  ... SELECT ... FROM staging.partners  ...;
INSERT INTO public.drivers   ... SELECT ... FROM staging.drivers   ...;
INSERT INTO public.bookings  ... SELECT ... FROM staging.bookings  ...;

-- Verification queries (read-only, NOT inside transaction):
-- V1-V6 from 20260902000004_phase_g_l_verification_queries.sql
-- ... run in a SEPARATE session or with the import session paused ...

-- COMMIT;        -- only if V1-V6 all return zero issues
-- ROLLBACK;      -- if any non-zero
```

If the import transaction is aborted (ROLLBACK) before commit, no canonical
target rows are written. Staging tables are dropped at end of script; if
they survive (e.g., psql session crashed mid-script), drop them manually:

```sql
DROP TABLE IF EXISTS staging.customers;
DROP TABLE IF EXISTS staging.partners;
DROP TABLE IF EXISTS staging.drivers;
DROP TABLE IF EXISTS staging.bookings;
DROP SCHEMA IF EXISTS staging;
```

---

## §D — Wave 4 cannot be aborted once application cutover (Wave 5) begins

Per CURRENT_MISSION.md and Lux 2675123 §10, Wave 5 (application cutover)
depends on Wave 4 being complete. If Wave 5 has begun:

- DO NOT attempt to roll back `legacy_user_id` columns — they are now part
  of the operational data model.
- DO NOT attempt to roll back the user mapping — re-onboarding flows are
  live and users are signing in.
- For any data-integrity issue discovered post-Wave-5, open a hot-fix
  additive migration (NOT a destructive rollback). Document in
  `evidence/hotfix-YYYYMMDD-<slug>.md`.

The Wave 4 ↔ Wave 5 transition is a one-way door.

---

## §E — Founder execution guardrails

1. **PRIME does NOT execute any SQL in this document on the live target.**
2. **All SQL runs in Founder-authenticated Dashboard SQL Editor or
   Founder-local psql session with `$NEW_DB_URL` from 1Password.**
3. **The mapping CSV (`evidence/r056-phase-g-l-auth-user-id-mapping.csv`)
   is Founder-local only.** PRIME never receives its contents.
4. **No credential transits chat, Telegram, Bridge, repo, or evidence.**
5. **The `publish_and_arm.sh`-style bridge round trip is used to request
   Lux review of the package BEFORE the Founder commits to apply.**
6. **Verification (V0-V6) must be green BEFORE COMMIT.** Any non-zero
   count is a hard abort.
