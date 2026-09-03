#!/bin/bash
# Phase G-N Wave 4: Founder import runner (PHASE 1 ONLY — staging + transform import)
#
# Mission   : 2026-08-29-fleetconnect-operational-recovery
# Round     : r056 Phase G-N transactional / secret-safe / split-runner correction
# Predecessor : Phase G-L/G-M (commit 1546e20) reviewed by Lux ee52b1a (partial accept)
#
# Lux ee52b1a §3 BLOCKER: PHASE 1 had no BEGIN -> autocommit -> no rollback guarantee.
# Lux ee52b1a §4 BLOCKER: run_wave4.sh echoed NEW_DB_URL to stdout -> secret leak.
# Lux ee52b1a §5 BLOCKER: documented `import-and-apply` re-executed PHASE 1 before
#                          PHASE 2 -> duplicate-partner risk + failed continuation.
#
# G-N correction (this file + apply script + transform SQL):
#   - PHASE 1 and PHASE 2 are now TWO SEPARATE SCRIPTS. There is no combined mode.
#   - PHASE 1 starts with explicit BEGIN; and runs all writes + invariants inside
#     ONE psql transaction. COMMIT only after all V1+V3+V-pre-mapping checks pass.
#   - This script NEVER prints NEW_DB_URL or any credential value. The only DB
#     connection reference printed is `[set]` (or "via PSQL_CMD override").
#   - No `set -x`, no `env` dump, no PSQL_CMD echo. A secrets-leakage scanner
#     runs at the end of every test invocation.
#
# USAGE (Founder):
#   export NEW_DB_URL="postgres://..."          # from 1Password; NOT shared with PRIME
#   export FC_CSV_DIR="$HOME/Documents/fleetconnect-cutover-2026-09-02"
#   ./run_wave4_import.sh
#
# USAGE (local test harness):
#   NEW_DB_URL="postgresql://..." \
#   FC_CSV_DIR="/tmp/phase_g_l_test_stage" \
#   PSQL_CMD="sudo -n -u postgres psql" \
#   RUNNER_SQL_DIR="/tmp/phase_g_l_test_stage" \
#   ./run_wave4_import.sh
#
# WHAT THIS SCRIPT DOES (one single psql transaction):
#   1. BEGIN;
#   2. \i phase_g_l_staging_create.sql         # staging schema + tables (idempotent)
#   3. \copy staging.{customers,partners,drivers,bookings} FROM ... CSV HEADER
#   4. \i phase_g_l_staging_transform.sql      # preflights + transform INSERTs
#                                              # + V1+V3+V-pre-mapping invariants
#   5. COMMIT;                                  # only if all preflights + invariants pass
#   6. POST-COMMIT staging cleanup (DROP SCHEMA staging)
#
# If anything in steps 1-5 raises, the transaction rolls back AUTOMATICALLY and
# no canonical target row is written. The exit code is non-zero and no COMMIT
# banner is printed.
#
# PHASE 2 (mapping apply) is a SEPARATE script: run_wave4_apply.sh. Run AFTER
# Dashboard user creation (Option C1 only) and mapping CSV is built.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/../sql"

# ---- environment guardrails ----
: "${NEW_DB_URL:?NEW_DB_URL must be set (Founder: from 1Password; test: from env)}"
: "${FC_CSV_DIR:?FC_CSV_DIR must be set (Founder: Founder-local CSV directory)}"

# FC_MAPPING_CSV is intentionally NOT required here. PHASE 2 needs it; PHASE 1 does not.
# This is a critical G-N correction: PHASE 1 must NOT depend on the mapping CSV.

# ---- required SQL files ----
for f in \
  "${SQL_DIR}/phase_g_l_staging_create.sql" \
  "${SQL_DIR}/phase_g_l_staging_transform.sql"
do
  if [ ! -f "$f" ]; then
    echo "FATAL: required SQL file missing: $f" >&2
    exit 60
  fi
done

# ---- psql invocation ----
# PSQL_CMD defaults to `psql` (production Founder invocation).
# The local test harness overrides it to `sudo -n -u postgres psql` so the
# runner can be exercised against the disposable test DB without requiring
# a password. Production Founder must NEVER set this override.
PSQL_CMD="${PSQL_CMD:-psql}"
# shellcheck disable=SC2206
PSQL_INV=( ${PSQL_CMD} )

: "${RUNNER_SQL_DIR:?RUNNER_SQL_DIR must be set (Founder: directory containing the SQL files; test harness: \$STAGE_DIR)}"
if [ ! -f "${RUNNER_SQL_DIR}/phase_g_l_staging_create.sql" ]; then
  echo "FATAL: RUNNER_SQL_DIR=${RUNNER_SQL_DIR} does not contain phase_g_l_staging_create.sql" >&2
  exit 60
fi

# -v variables for parameterization (psql variable syntax, NOT shell heredoc).
# ON_ERROR_STOP=1 -> any SQL error aborts the transaction (with BEGIN+COMMIT, that's a real rollback).
# --no-psqlrc -X -> no startup file interference.
# Production: no G_N_TEST_INJECT_FAIL env var -> G_N_INJECT_BLOCK is empty.
# Test: G_N_TEST_INJECT_FAIL=after_first_insert -> emits CREATE TEMP TABLE
# g_n_test_inject_flag + INSERT marker. The marker is read by
# phase_g_l_staging_transform.sql B.1.5 to raise a post-write EXCEPTION,
# proving the transaction rolls back (Lux ee52b1a §6.12).
G_N_INJECT_BLOCK=""
if [ -n "${G_N_TEST_INJECT_FAIL:-}" ]; then
  G_N_INJECT_BLOCK=$(printf "%s\n" \
    "-- Test-only marker injection (G-N §6.12)" \
    "CREATE TEMP TABLE g_n_test_inject_flag (flag TEXT PRIMARY KEY);" \
    "INSERT INTO g_n_test_inject_flag VALUES ('${G_N_TEST_INJECT_FAIL}');")
fi

PSQL_BASE=("${PSQL_INV[@]}" "${NEW_DB_URL}" -v ON_ERROR_STOP=1 --no-psqlrc -X -q
  -v fc_csv_dir="${FC_CSV_DIR}"
  -v fc_sql_dir="${RUNNER_SQL_DIR}")

# ===========================================================================
# PHASE 1: STAGING-TRANSFORM IMPORT (single transaction, BEGIN added)
# ===========================================================================
echo "================================================================"
echo "Phase G-N Wave 4 - Founder import runner (PHASE 1 only)"
echo "================================================================"
echo ""
echo "PHASE 1: staging-transform import (transactional)"
echo "  NEW_DB_URL: [set]                 <- NEVER print the value (Lux ee52b1a §4)"
echo "  FC_CSV_DIR: ${FC_CSV_DIR}"
echo ""

# NOTE: This heredoc contains BEGIN; ... COMMIT; around ALL writes. If any
# statement raises EXCEPTION, the transaction aborts and rolls back automatically.
# Lux ee52b1a §3 BLOCKER fix.
"${PSQL_BASE[@]}" <<SQL
\set QUIET on

-- Explicit BEGIN. Required so the entire staging-create + COPY + transform +
-- invariant sequence is one rollback unit. Lux ee52b1a §3.
BEGIN;

-- 1.0 Optional test-only marker injection (Lux ee52b1a §6.12).
--     If G_N_TEST_INJECT_FAIL=after_first_insert, the runner (via bash)
--     injects CREATE TEMP TABLE g_n_test_inject_flag + INSERT marker here.
--     The transform SQL reads it at B.1.5 and raises a deliberate EXCEPTION
--     after B.1 has written at least one canonical row, proving the
--     transaction rolls back.
--
--     Production: G_N_TEST_INJECT_FAIL is unset -> no marker SQL is injected.
--     No pg_temp pollution in prod. The transform B.1.5 IF returns false.
${G_N_INJECT_BLOCK}

-- 1.1 Create staging schema + tables (pure SQL, idempotent)
\cd :fc_sql_dir
\i phase_g_l_staging_create.sql

-- 1.2 Load CSVs into staging tables (change cwd to FC_CSV_DIR so relative paths work)
\cd :fc_csv_dir
\copy staging.customers (id, created_at, updated_at, user_id, email, name, phone, default_pickup_address, archived, archived_at, auth_user_linked, auth_user_linked_at, is_active, no_email, no_session, status, approved, approved_at, auto_approved_at, rejected, rejected_at, pending, approval_not_required, request_scope, username, customer_profile_upserted_at) FROM 'customers.csv' CSV HEADER
\copy staging.partners  (legacy_pk, created_at, updated_at, user_id, email, name, phone, is_hoofd, company, notes, account_type, archived_at, default_pickup_address, contact, driver, kind, operations, pending_request, primary_dispatch_driver_id) FROM 'partners.csv' CSV HEADER
\copy staging.drivers   (id, created_at, updated_at, partner_legacy_pk, user_id, email, name, phone, vehicle, license_plate, color, driver_code, preferred_language, is_active, archived_at) FROM 'drivers.csv' CSV HEADER
\copy staging.bookings  (id, created_at, pickup, destination, status, customer_id, partner_legacy_pk, driver_legacy_uuid, user_id, email, name, phone, notes, payment_status, assigned_driver, route_distance_km, route_duration_min, extras, flight_number, vehicle, license_plate, assignment_token, pickup_place_id, dropoff_place_id, assignment_sent_at, assignment_accepted_at, assignment_declined_at, pwa_driver_can_act, form_data, metadata, amount, payment, time, datetime) FROM 'bookings.csv' CSV HEADER

-- 1.3 Transform + invariant verification (pure SQL, raises EXCEPTION on any failure)
\cd :fc_sql_dir
\i phase_g_l_staging_transform.sql

-- 1.4 Optional test-only post-write failure injection (Lux ee52b1a §6.12).
--    The transform SQL reads this psql variable and raises EXCEPTION after at
--    least one canonical target INSERT, proving the transaction rolls back.
--    Set G_N_TEST_INJECT_FAIL=after_first_insert in the test harness ONLY.
--    Production runs MUST leave it unset (default ''), so the branch is dead
--    code in production.

-- 1.5 Commit. If we reach here, all preflights + invariants passed.
COMMIT;

\echo 'PHASE 1 OK: staging-transform committed'
SQL

PHASE1_RC=$?
if [ $PHASE1_RC -ne 0 ]; then
  echo "PHASE 1 FAILED (rc=$PHASE1_RC); transaction rolled back automatically."
  echo "No canonical target rows from this run should be visible. Verify with:"
  echo "  SELECT count(*) FROM public.customers WHERE legacy_user_id IS NOT NULL;"
  echo "  SELECT count(*) FROM public.partners  WHERE legacy_user_id IS NOT NULL;"
  echo "  SELECT count(*) FROM public.drivers   WHERE legacy_user_id IS NOT NULL;"
  echo "  SELECT count(*) FROM public.bookings  WHERE legacy_user_id IS NOT NULL;"
  exit 1
fi
echo "PHASE 1 committed OK."
echo ""

# ===========================================================================
# PHASE 1b: POST-COMMIT STAGING CLEANUP (separate connection, outside transaction)
# ===========================================================================
echo "PHASE 1b: staging cleanup"
"${PSQL_BASE[@]}" -c "
DROP TABLE IF EXISTS staging.customers;
DROP TABLE IF EXISTS staging.partners;
DROP TABLE IF EXISTS staging.drivers;
DROP TABLE IF EXISTS staging.bookings;
DROP SCHEMA IF EXISTS staging;
" 2>&1 | tail -1
echo "PHASE 1b OK: staging dropped."
echo ""

echo "================================================================"
echo "Phase G-N Wave 4 import runner: PHASE 1 OK"
echo ""
echo "NEXT FOUNDER STEP (NOT THIS SCRIPT):"
echo "  1. Create target users in Supabase Dashboard (Option C1 only)."
echo "  2. Build FC_MAPPING_CSV (legacy_user_id, new_user_id)."
echo "  3. Run PHASE 2 separately:  ./run_wave4_apply.sh"
echo ""
echo "DO NOT re-run PHASE 1 after success."
echo "DO NOT pass any argument to this script."
echo "================================================================"
