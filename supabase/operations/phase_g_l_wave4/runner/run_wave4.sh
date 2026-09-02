#!/bin/bash
# Phase G-L Wave 4: Founder runner (deterministic single-transaction execution)
#
# Mission   : 2026-08-29-fleetconnect-operational-recovery
# Round     : r056 Phase G-L executable Wave 4 data/auth remap package
#
# This is the EXACT script the Founder runs against the production target
# (post-Wave 1/2/3 schema apply + Wave 4 pre-step additive audit migration).
# The local test harness invokes THIS script against a disposable reconstructed
# target to prove the execution contract.
#
# USAGE (Founder):
#   export NEW_DB_URL="postgres://..."        # from 1Password, NOT shared with PRIME
#   export FC_CSV_DIR="$HOME/Documents/fleetconnect-cutover-2026-09-02"
#   export FC_MAPPING_CSV="$FC_CSV_DIR/r056-phase-g-l-auth-user-id-mapping.csv"
#   ./run_wave4.sh
#
# USAGE (local test harness):
#   DB_NAME=phase_g_l_wave4_test \
#     NEW_DB_URL="postgresql://postgres@/phase_g_l_wave4_test" \
#     FC_CSV_DIR="/tmp/phase_g_l_test_stage" \
#     FC_MAPPING_CSV="/tmp/phase_g_l_test_stage/mapping.csv" \
#     ./run_wave4.sh [import|import-and-apply]
#
# WHAT THIS SCRIPT DOES (deterministic, single psql transaction where applicable):
#
#   PHASE 1: STAGING-TRANSFORM IMPORT (single transaction)
#     -v fc_csv_dir="$FC_CSV_DIR"
#     -v fc_mapping_csv="$FC_MAPPING_CSV"
#     -v import_step="yes"
#     \i phase_g_l_staging_create.sql      # creates staging schema/tables
#     \copy staging.customers FROM :'fc_csv_dir'/customers.csv CSV HEADER
#     \copy staging.partners  FROM :'fc_csv_dir'/partners.csv  CSV HEADER
#     \copy staging.drivers   FROM :'fc_csv_dir'/drivers.csv   CSV HEADER
#     \copy staging.bookings  FROM :'fc_csv_dir'/bookings.csv  CSV HEADER
#     \i phase_g_l_staging_transform.sql  # preflight + transform + V1+V3+V-pre-mapping invariants
#     # If anything above fails: psql errors, transaction rolls back automatically
#     COMMIT;                              # only after stage-transform succeeded
#
#   PHASE 2: MAPPING APPLY (separate single transaction)
#     # Founder has already created users in target auth.users via Dashboard (Option C1)
#     # Founder has already produced FC_MAPPING_CSV locally
#     BEGIN;
#     CREATE TEMP TABLE user_id_mapping (...);  # session-scoped, pg_temp schema
#     \copy user_id_mapping FROM :'fc_mapping_csv' CSV HEADER
#     \i phase_g_l_mapping_apply.sql   # preflight + UPDATE + V2+V4+V5 invariants
#     COMMIT;                          # only after mapping-apply succeeded
#
#   PHASE 3: POST-COMMIT CLEANUP
#     DROP TABLE staging.customers / partners / drivers / bookings
#
# WHY EACH PIECE:
#   - One single psql invocation per phase -> no "transaction can't be resumed"
#     problem (BLOCKER 2 fix)
#   - All verification INSIDE the same transaction -> fail-closed before commit
#   - -v fc_csv_dir / :'fc_csv_dir' interpolation -> shell variable expansion
#     in quoted heredoc replaced by psql variable (BLOCKER 4 fix)
#   - phase_g_l_staging_create.sql runs BEFORE \copy (BLOCKER 3 fix)
#   - phase_g_l_mapping_apply.sql is pure SQL, no \copy, no hard-coded path
#     (BLOCKER 5 fix)
#   - Operational files live under supabase/operations/phase_g_l_wave4/, NOT
#     supabase/migrations/, so they don't silently enter Wave 1 manifest
#     (BLOCKER 6 fix)
#
# NON-SCOPE (per Lux cfb0e9b §9):
#   - This script does NOT apply the additive audit migration. That is a
#     separately reviewed Wave 4 pre-step that runs once after Lux acceptance.
#   - This script does NOT create users in auth.users. Per Lux 39ca1a0 §5,
#     Option C1 (Dashboard) is the only canonical create-user path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/../sql"
EVIDENCE_DIR="${SCRIPT_DIR}/../evidence"

# ---- environment guardrails ----
: "${NEW_DB_URL:?NEW_DB_URL must be set (Founder: from 1Password; test: from env)}"
: "${FC_CSV_DIR:?FC_CSV_DIR must be set (Founder: Founder-local CSV directory)}"
: "${FC_MAPPING_CSV:?FC_MAPPING_CSV must be set (Founder: Founder-local mapping CSV)}"

# Derive the mapping CSV directory from the mapping CSV path. Used for
# \cd before \copy so the \copy can use a relative filename.
FC_MAPPING_CSV_DIR="$(dirname "${FC_MAPPING_CSV}")"

for f in \
  "${SQL_DIR}/phase_g_l_staging_create.sql" \
  "${SQL_DIR}/phase_g_l_staging_transform.sql" \
  "${SQL_DIR}/phase_g_l_mapping_apply.sql"
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
# We resolve PSQL_CMD into PSQL_INV (an array) so that sudo's word-splitting
# is preserved regardless of how the env var is set.
PSQL_CMD="${PSQL_CMD:-psql}"
# shellcheck disable=SC2206
PSQL_INV=( ${PSQL_CMD} )

# Production Founder runs from the directory containing the SQL files (or
# sets RUNNER_SQL_DIR explicitly). The local test harness stages the SQL
# files in $STAGE_DIR and sets RUNNER_SQL_DIR to that path.
: "${RUNNER_SQL_DIR:?RUNNER_SQL_DIR must be set (Founder: directory containing the SQL files; test harness: \$STAGE_DIR)}"
if [ ! -f "${RUNNER_SQL_DIR}/phase_g_l_staging_create.sql" ]; then
  echo "FATAL: RUNNER_SQL_DIR=${RUNNER_SQL_DIR} does not contain phase_g_l_staging_create.sql" >&2
  exit 60
fi

# -v variables for parameterization (psql variable syntax, NOT shell heredoc).
# fc_sql_dir parameterizes the SQL file location for \i.
# ON_ERROR_STOP=1 -> any SQL error aborts the transaction.
# --no-psqlrc -X -> no startup file interference.
PSQL_BASE=("${PSQL_INV[@]}" "${NEW_DB_URL}" -v ON_ERROR_STOP=1 --no-psqlrc -X -q
  -v fc_csv_dir="${FC_CSV_DIR}"
  -v fc_mapping_csv_dir="${FC_MAPPING_CSV_DIR}"
  -v fc_sql_dir="${RUNNER_SQL_DIR}")

# ===========================================================================
# PHASE 1: STAGING-TRANSFORM IMPORT (single transaction)
# ===========================================================================
echo "================================================================"
echo "Phase G-L Wave 4 — Founder runner"
echo "================================================================"
echo ""
echo "PHASE 1: staging-transform import"
echo "  NEW_DB_URL:    ${NEW_DB_URL}"
echo "  FC_CSV_DIR:    ${FC_CSV_DIR}"
echo ""

"${PSQL_BASE[@]}" <<'SQL'
\set QUIET on

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

-- 1.4 Commit. If we reach here, all preflights + invariants passed.
COMMIT;

\echo 'PHASE 1 OK: staging-transform committed'
SQL

PHASE1_RC=$?
if [ $PHASE1_RC -ne 0 ]; then
  echo "PHASE 1 FAILED (rc=$PHASE1_RC); transaction rolled back automatically."
  echo "Investigate the SQL error above; re-run after fix."
  exit 1
fi
echo "PHASE 1 committed OK."
echo ""

# ===========================================================================
# PHASE 2: MAPPING APPLY (separate single transaction)
# ===========================================================================
# By default the runner stops here. Pass 'import-and-apply' as the first
# argument to also run PHASE 2 (mapping apply).
RUN_MODE="${1:-import}"
if [ "$RUN_MODE" != "import-and-apply" ]; then
  echo "PHASE 2 (mapping apply) NOT executed (run mode: '$RUN_MODE')."
  echo "Founder should now:"
  echo "  1. Create target users in Dashboard (Option C1 only, per Lux 39ca1a0 §5)"
  echo "  2. Build FC_MAPPING_CSV (legacy_user_id, new_user_id)"
  echo "  3. Re-run this script as:  $0 import-and-apply"
  exit 0
fi

echo "PHASE 2: mapping apply"
echo "  FC_MAPPING_CSV: ${FC_MAPPING_CSV}"
echo ""

"${PSQL_BASE[@]}" <<'SQL'
\set QUIET on

BEGIN;

-- 2.1 Create session-scoped TEMP TABLE for the mapping (no schema qualification
--     per Lux cfb0e9b §5: temp objects live in pg_temp, not staging).
CREATE TEMP TABLE user_id_mapping (
    legacy_user_id UUID NOT NULL,
    new_user_id    UUID NOT NULL,
    re_onboard_status TEXT
) ON COMMIT DROP;

-- 2.2 Load mapping CSV (change cwd to mapping CSV directory so relative path works)
\cd :fc_mapping_csv_dir
\copy user_id_mapping (legacy_user_id, new_user_id, re_onboard_status) FROM 'mapping.csv' CSV HEADER

-- 2.3 Apply mapping + invariant verification (pure SQL)
\cd :fc_sql_dir
\i phase_g_l_mapping_apply.sql

-- 2.4 Commit. If we reach here, all preflights + invariants passed.
COMMIT;

\echo 'PHASE 2 OK: mapping-apply committed'
SQL

PHASE2_RC=$?
if [ $PHASE2_RC -ne 0 ]; then
  echo "PHASE 2 FAILED (rc=$PHASE2_RC); transaction rolled back automatically."
  echo "Phase 1 rows remain committed (import succeeded); mapping-apply aborted."
  echo "Investigate, fix, re-run only PHASE 2."
  exit 2
fi
echo "PHASE 2 committed OK."
echo ""

# ===========================================================================
# PHASE 3: POST-COMMIT STAGING CLEANUP
# ===========================================================================
echo "PHASE 3: staging cleanup"
"${PSQL_BASE[@]}" -c "
DROP TABLE IF EXISTS staging.customers;
DROP TABLE IF EXISTS staging.partners;
DROP TABLE IF EXISTS staging.drivers;
DROP TABLE IF EXISTS staging.bookings;
DROP SCHEMA IF EXISTS staging;
" 2>&1 | tail -1
echo "PHASE 3 OK: staging dropped."

echo ""
echo "================================================================"
echo "Phase G-L Wave 4 Founder runner: ALL PHASES OK"
echo "================================================================"
