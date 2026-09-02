# Phase G-L Wave 4 — Rollback Procedure (Phase G-M revision)

**Mission** : `2026-08-29-fleetconnect-operational-recovery`
**Round**   : `r056-phase-g-m-wave4-import-remap-correction` (per Lux `cfb0e9b`)

This document is the single source of truth for rolling back Wave 4 if any preflight,
verification, or downstream behavior fails. It is matched to the corrected file layout:

```
supabase/
├── migrations/
│   └── 20260902000001_phase_g_l_additive_legacy_user_id_audit_column.sql   (only Wave-4 migration)
└── operations/phase_g_l_wave4/
    ├── sql/
    │   ├── phase_g_l_staging_create.sql
    │   ├── phase_g_l_staging_transform.sql
    │   ├── phase_g_l_mapping_apply.sql
    │   └── phase_g_l_verification_queries.sql
    ├── runner/
    │   ├── run_wave4.sh
    │   ├── run_phase_g_l_wave4_tests.sh
    │   └── generate_fixtures.py
    └── evidence/
        ├── r056-phase-g-l-founder-execution-runbook.md
        ├── r056-phase-g-l-rollback.md                  (this file)
        └── r056-phase-g-l-local-test-evidence.md
```

---

## §A — Drop the additive migration (idempotent)

The additive migration only adds a `legacy_user_id UUID NULL` audit column to five auth-linked
tables. It never mutates existing data. To reverse it:

```sql
-- Run as a single transaction via the Founder's authenticated psql / SQL Editor.
BEGIN;

ALTER TABLE public.customers       DROP COLUMN IF EXISTS legacy_user_id;
ALTER TABLE public.partners        DROP COLUMN IF EXISTS legacy_user_id;
ALTER TABLE public.drivers         DROP COLUMN IF EXISTS legacy_user_id;
ALTER TABLE public.onderaannemers  DROP COLUMN IF EXISTS legacy_user_id;
ALTER TABLE public.bookings        DROP COLUMN IF EXISTS legacy_user_id;

COMMIT;
```

The `IF EXISTS` guard makes this idempotent: running it twice is a no-op the second time.

---

## §B — Roll back Wave 4 data + auth remap

If PHASE 2 (mapping apply) completed but verification failed, the canonical tables have new
`user_id` values that point at the wrong `auth.users.id`. The mapping is **not yet authoritative**:
you must reset both halves.

### §B.1 — Clear all target `user_id` values that Wave 4 set

The mapping applied via `UPDATE` only. Reverting requires the inverse `UPDATE`, but we don't
have the inverse mapping (and we shouldn't rely on it). The cleanest revert is to drop the
additive column (`legacy_user_id`) along with clearing `user_id` for every row that was
touched in Wave 4:

```sql
BEGIN;

-- Identify rows that were touched in Wave 4: those whose user_id matches a new_user_id
-- from the Founder's mapping.csv. The mapping is Founder-local, so this query uses a
-- JSON literal that the Founder pastes in.
WITH wave4_mapping AS (
  SELECT * FROM jsonb_to_recordset($WAVE4_MAPPING$[
    {"legacy_user_id": "11111111-1111-1111-1111-111111111111", "new_user_id": "cccccccc-cccc-cccc-cccc-cccccccccccc"},
    ...  -- full mapping from Founder's mapping.csv
  ]$WAVE4_MAPPING$::jsonb) AS x(legacy_user_id uuid, new_user_id uuid)
)
UPDATE public.customers c
   SET user_id = NULL
  FROM wave4_mapping w
 WHERE c.user_id = w.new_user_id;
-- repeat for partners, drivers, onderaannemers, bookings
COMMIT;
```

**Hard rule:** the inverse-UPDATE must be issued **before** the additive column is dropped,
because the additive column is the only durable record of which rows were touched.

### §B.2 — Drop the Dashboard-created auth.users rows

After §B.1, the `auth.users` rows created in §B of the runbook are orphaned (no canonical
table references them). Founder deletes them via Dashboard:

- Dashboard → Authentication → Users → filter by creation timestamp → delete in batches.

There is no SQL Editor equivalent (Option C2 is REMOVED).

### §B.3 — Drop the staging schema (if it survived)

PHASE 3 normally drops `staging` automatically. If the runner aborted mid-PHASE 1, staging may
still exist:

```sql
DROP SCHEMA IF EXISTS staging CASCADE;
```

### §B.4 — Re-apply the legacy export directly (last-resort path)

If §B.1 cannot reconstruct the legacy state because the additive column was already dropped,
the only recovery is to re-export from `rreqjjrmvytnwnsidmqi` and run the corrected Wave 4
again. This requires Founder to re-trigger the runner with a fresh mapping.

---

## §C — Transaction-abort safety

Each phase of `run_wave4.sh` runs in its own `psql` invocation with `ON_ERROR_STOP=1`. Any
preflight that raises `EXCEPTION` aborts the current transaction. Subsequent phases never
execute because the runner exits non-zero.

Observed in local test evidence:

- neg1 (duplicate partner email) → PHASE 1 ABORT, 0 rows in canonical tables
- neg2 (orphan driver.partner_legacy_pk) → PHASE 1 ABORT, 0 rows in canonical tables
- neg3 (bogus mapping new_user_id) → PHASE 1 OK (11 rows preserved), PHASE 2 ABORT, mapping not applied

For neg3, PHASE 1's 11 rows are intentionally preserved (the runner commits each phase
independently). To revert neg3's state, run §B.1's inverse-UPDATE.

---

## §D — Wave 4 ↔ Wave 5 one-way door

Wave 4 is **not** a one-way door on its own: the additive column is removable and the mapping
UPDATEs are reversible. However, once Wave 5 (application cutover) begins to write to the new
`user_id` values via live dispatch / booking / auth flows, **Wave 4's outputs become
load-bearing** and rollback narrows to:

1. Pause all write traffic to the cutover project.
2. Reverse-update `user_id` from Wave-5 live writes via §B.1 (still possible if additive column
   was retained).
3. If additive column was already dropped → no rollback; Wave 5 must complete.

**Hard rule:** never drop `legacy_user_id` until Wave 5 is complete and Founder has accepted
the production cutover outputs.

---

## §E — Founder guardrails (matching the runbook)

- **No credentials in chat/Telegram/Bridge/repo/evidence.** `$NEW_DB_URL` is Founder-only.
- **No assumption PRIME holds `$NEW_DB_URL`.**
- **Option C2 REMOVED.** No `INSERT INTO auth.users` or `auth.identities` via SQL Editor.
- **Dashboard-only user creation.** Per Lux `39ca1a0` §5.
- **Deterministic mapping.** Every distinct legacy `user_id` in canonical tables must be
  resolvable via the Founder's mapping.csv at all times until Wave 5 acceptance.
