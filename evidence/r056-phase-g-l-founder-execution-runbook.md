# Phase G-L Founder Execution Runbook

**Mission:** `2026-08-29-fleetconnect-operational-recovery`
**Round:** r056 Phase G-L executable Wave 4 data/auth remap package

This runbook is the Founder-authenticated execution contract for the
Phase G-L Wave 4 import. **PRIME does not execute any step here.**
The Founder performs every action in an authenticated Dashboard session
or Founder-local terminal with `$NEW_DB_URL` from 1Password (never
shared with PRIME).

---

## §0 — Preconditions (Founder-verified BEFORE any step)

- [ ] Wave 1 schema apply complete (canonical greenfield baseline +
      phase4 identity closure + Phase F mailbox migration applied to
      `wjbxrgbyhqpiujifwqcf`).
- [ ] `20260902000001_phase_g_l_legacy_user_id_audit_column.sql` applied
      to the target. **V0 verification** (in
      `20260902000004_phase_g_l_verification_queries.sql`) returns 5 rows,
      all `data_type='uuid'`, all `is_nullable='YES'`.
- [ ] Legacy CSV exports captured via supported authenticated paths only
      (Path A1/A2/A3 from
      `evidence/r056-phase-g-i-data-auth-migration-mapping.md` §1.2). NOT
      chat/Telegram/Bridge/repo.
- [ ] Legacy CSV files held in a Founder-local secure directory
      (e.g. `~/Documents/fleetconnect-cutover-2026-09-02/`). Path is
      referenced as `$FC_CSV_DIR` below.
- [ ] `$NEW_DB_URL` available in Founder's 1Password; PRIME does NOT hold it.
- [ ] Wave 2 Edge Function deploy + Wave 3 Dashboard secrets configuration
      complete (per Lux 2675123 §7 — Waves 1-3 remain authorized).

---

## §A — Staging-transform import (`20260902000002`)

### §A.1 — Founder-local psql session, single transaction

```bash
# Founder-local terminal, NOT in chat/Telegram/Bridge/repo/evidence
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 <<'SQL'
\set QUIET on
\echo '--- Phase G-L staging-transform import begin ---'

BEGIN;

-- Step 1: psql \copy each legacy CSV into the matching staging table.
-- Adjust column-list to match the actual CSV column order.

\copy staging.customers (id, created_at, updated_at, user_id, email, name, phone, default_pickup_address, archived, archived_at, auth_user_linked, auth_user_linked_at, is_active, no_email, no_session, status, approved, approved_at, auto_approved_at, rejected, rejected_at, pending, approval_not_required, request_scope, username, customer_profile_upserted_at) FROM '$FC_CSV_DIR/fc-customers.csv' CSV HEADER

\copy staging.partners (legacy_pk, created_at, updated_at, user_id, email, name, phone, is_hoofd, company, notes, account_type, archived_at, default_pickup_address, contact, driver, kind, operations, pending_request, primary_dispatch_driver_id) FROM '$FC_CSV_DIR/fc-partners.csv' CSV HEADER

\copy staging.drivers (id, created_at, updated_at, partner_legacy_pk, user_id, email, name, phone, vehicle, license_plate, color, driver_code, preferred_language, is_active, archived_at) FROM '$FC_CSV_DIR/fc-drivers.csv' CSV HEADER

\copy staging.bookings (id, created_at, pickup, destination, status, customer_id, partner_legacy_pk, user_id, email, name, phone, notes, payment_status, assigned_driver, driver_legacy_uuid, route_distance_km, route_duration_min, extras, flight_number, vehicle, license_plate, assignment_token, pickup_place_id, dropoff_place_id, assignment_sent_at, assignment_accepted_at, assignment_declined_at, pwa_driver_can_act, form_data, metadata, amount, payment, time, datetime) FROM '$FC_CSV_DIR/fc-bookings.csv' CSV HEADER

-- Step 2: transform + insert into canonical targets.
-- File contents executed here:
\i /path/to/20260902000002_phase_g_l_staging_transform_import.sql

-- DO NOT COMMIT yet. Verification must run first.
\echo '--- Phase G-L staging-transform import holding for verification ---'
SQL
```

### §A.2 — Verification (V1, V3, V5) — read-only in a separate session

Open a separate Founder-authenticated psql session:

```bash
psql "$NEW_DB_URL" -f /path/to/20260902000004_phase_g_l_verification_queries.sql
```

V1 (row-count parity): founder compares each `target_count` against the
legacy count captured at export. **ABORT if any target_count != legacy.**

V3 (business-FK orphans): all counts must be 0. **ABORT if any > 0.**

V5 (dual-link): all counts must be 0. **ABORT if any > 0.**

If all green:

```bash
# Back in the original session (which is still holding the transaction):
COMMIT;
\echo '--- Phase G-L staging-transform import committed ---'
```

If any verification fails:

```bash
ROLLBACK;
\echo '--- Phase G-L staging-transform import ABORTED ---'
# See evidence/r056-phase-g-l-rollback.md §C for cleanup of staging tables
```

---

## §B — Dashboard-only user creation + recorded mapping

**Per Lux 2675123 §2 + Lux 39ca1a0 §5: Option C1 (Dashboard Authentication →
Users → Add user → Create new user with email + auto-confirm checked) is
the only canonical create-user path. Option C2 (direct SQL INSERT INTO
auth.users / auth.identities) is REMOVED entirely.**

### §B.1 — Build the mapping CSV locally

The mapping CSV is held Founder-local and never shared with PRIME. Format
(from canonical doc §2.2):

```csv
legacy_user_id,legacy_email,new_user_id,new_email,re_onboard_status
aaaa-bbbb-cccc-dddd-eeee-ffff-0001,ops@fleetconnect.be,,ops@fleetconnect.be,PENDING_CREATE
aaaa-bbbb-cccc-dddd-eeee-ffff-0002,partner1@example.com,,partner1@example.com,PENDING_CREATE
...
```

The Founder builds this from the legacy `auth.users` inventory (per
`r056-phase-g-i-data-auth-migration-mapping.md` §2.2 step 1-2).

### §B.2 — Dashboard create-user loop

For each row in the mapping CSV where `re_onboard_status=PENDING_CREATE`:

1. Open Supabase Dashboard → project `wjbxrgbyhqpiujifwqcf` → Authentication → Users.
2. Click "Add user" → "Create new user".
3. Enter email = `legacy_email`. Tick "Auto Confirm User".
4. Click "Create user".
5. The Dashboard returns the new `auth.users.id` (UUID v4). **Record this
   in the mapping CSV's `new_user_id` column. Set
   `re_onboard_status=CREATED`.**
6. Send recovery email: click on the user row → "Send recovery email" →
   so the user sets their own password.
7. Loop until every PENDING_CREATE row has a CREATED row with a
   non-null `new_user_id`.

For customer accounts (operationally feasible at scale via Dashboard but
slow): see §B.3 for the optional bulk-create flow if Supabase Admin Auth
API is later reviewed and adopted. **Until then, Dashboard one-by-one is
the only supported path.**

### §B.3 — Optional bulk-create (NOT YET ADOPTED)

Per Lux 39ca1a0 §5 + Lux 2675123 §2: a future supported Admin Auth API path
may be added if separately verified and reviewed. Until then, the §B.2
Dashboard loop is the only canonical path. **PRIME does NOT adopt, suggest,
or implement any bulk-create method that is not on a verified current
Supabase-supported admin API.**

---

## §C — Apply deterministic old → new mapping (`20260902000003`)

After §B.2 completes for every user the Founder wants to bring across:

```bash
psql "$NEW_DB_URL" -v ON_ERROR_STOP=1 <<'SQL'
\set QUIET on
\echo '--- Phase G-L mapping-apply begin ---'

BEGIN;

-- Step 1: load mapping CSV into a temp table.
CREATE TEMP TABLE staging.user_id_mapping (
    legacy_user_id UUID NOT NULL,
    new_user_id    UUID NOT NULL,
    re_onboard_status TEXT
);

\copy staging.user_id_mapping (legacy_user_id, new_user_id, re_onboard_status) FROM '$FC_CSV_DIR/r056-phase-g-l-auth-user-id-mapping.csv' CSV HEADER

-- Step 2: apply mapping via legacy_user_id.
\i /path/to/20260902000003_phase_g_l_mapping_apply.sql

-- DO NOT COMMIT yet. Verification must run first.
\echo '--- Phase G-L mapping-apply holding for verification ---'
SQL
```

In a separate psql session:

```bash
psql "$NEW_DB_URL" -f /path/to/20260902000004_phase_g_l_verification_queries.sql
```

V2 (zero auth-orphan FKs): all counts must be 0. **ABORT if any > 0.**

V4 (zero unmapped legacy_user_id rows): all counts must be 0 (modulo
intentionally-unmapped audit rows documented in §B.4). **ABORT if any > 0.**

If green:

```bash
COMMIT;
\echo '--- Phase G-L mapping-apply committed ---'
```

If any verification fails:

```bash
ROLLBACK;
\echo '--- Phase G-L mapping-apply ABORTED ---'
# See evidence/r056-phase-g-l-rollback.md §B.4 for per-row unmapped-user recovery
```

---

## §D — Wave 4 completion report

After §C commits green:

1. Run V0-V6 one more time in a final psql session; capture the output
   as `evidence/r056-phase-g-l-wave4-completion-report.md` (or attached
   to the existing report).
2. Note any intentionally-unmapped `legacy_user_id` rows (per §B.4) in
   the report.
3. Tag the FleetConnect repo at the Wave 4 cutover commit
   (`r056-wave4-cutover-<date>`). The tag is additive and immutable; do
   not move an older tag.
4. Founder publishes `LUX — SYNC NEEDED` via the bridge:
   `evidence/r056-phase-g-l-wave4-completion-report.md` is the review
   artifact.

---

## §E — Wave 5 unblock

After Lux reviews Wave 4 completion:

- Wave 5 (application cutover) becomes unblocked. See CURRENT_MISSION.md
  Execution Gates §2 for the controlled lifecycle proof steps.
- Wave 5 must include the B3 lifecycle regression (per Lux 2675123 §10
  Mission gate).

---

## §F — Founder execution guardrails (summary)

1. **No PRIME execution on the live target.**
2. **All SQL is Founder-authenticated (Dashboard SQL Editor or
   Founder-local psql with `$NEW_DB_URL` from 1Password).**
3. **No credential transits chat, Telegram, Bridge, repo, or evidence.**
4. **The mapping CSV is Founder-local only.**
5. **Verification (V0-V6) green BEFORE every COMMIT.**
6. **§B uses Option C1 (Dashboard) only — Option C2 direct SQL is REMOVED.**
7. **Tag the FleetConnect repo at Wave 4 cutover; do not move older tags.**
