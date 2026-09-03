#!/bin/bash
# Phase G-N Wave 4: Founder apply runner (PHASE 2 ONLY — mapping apply)
#
# Mission   : 2026-08-29-fleetconnect-operational-recovery
# Round     : r056 Phase G-N transactional / secret-safe / split-runner correction
#
# This is the EXACT script the Founder runs AFTER:
#   1. run_wave4_import.sh has succeeded (PHASE 1 committed)
#   2. Target auth.users rows have been created in Supabase Dashboard (Option C1 only)
#   3. Founder has produced FC_MAPPING_CSV locally
#
# G-N correction: this script NEVER re-executes PHASE 1. It only consumes an
# already-committed PHASE 1 state and applies the legacy_user_id -> new_user_id
# mapping in a fresh transaction. There is no "combined" mode. There is no
# `import-and-apply` argument. There is no path by which PHASE 2 can trigger
# a re-import of staging CSVs.
#
# USAGE (Founder):
#   export NEW_DB_URL="postgres://..."          # from 1Password; NOT shared with PRIME
#   export FC_MAPPING_CSV="$HOME/Documents/fleetconnect-cutover-2026-09-02/r056-phase-g-l-auth-user-id-mapping.csv"
#   ./run_wave4_apply.sh
#
# USAGE (local test harness):
#   NEW_DB_URL="postgresql://..." \
#   FC_MAPPING_CSV="/tmp/phase_g_l_test_stage/mapping.csv" \
#   PSQL_CMD="sudo -n -u postgres psql" \
#   RUNNER_SQL_DIR="/tmp/phase_g_l_test_stage" \
#   ./run_wave4_apply.sh
#
# WHAT THIS SCRIPT DOES (one single psql transaction):
#   1. BEGIN;
#   2. CREATE TEMP TABLE user_id_mapping ON COMMIT DROP;
#   3. \copy user_id_mapping FROM 'mapping.csv' CSV HEADER
#   4. \i phase_g_l_mapping_apply.sql         # preflight + UPDATE + V2+V4+V5 invariants
#   5. COMMIT;                                 # only if all preflights + invariants pass
#
# PHASE 1 MUST already be committed. This script does not depend on, nor re-run,
# PHASE 1's staging tables. It only touches canonical public.* tables.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/../sql"

# ---- environment guardrails ----
: "${NEW_DB_URL:?NEW_DB_URL must be set (Founder: from 1Password; test: from env)}"
: "${FC_MAPPING_CSV:?FC_MAPPING_CSV must be set (Founder: Founder-local mapping CSV)}"

# Derive the mapping CSV directory from the mapping CSV path. Used for
# \cd before \copy so the \copy can use a relative filename.
FC_MAPPING_CSV_DIR="$(dirname "${FC_MAPPING_CSV}")"

# ---- required SQL files ----
if [ ! -f "${SQL_DIR}/phase_g_l_mapping_apply.sql" ]; then
  echo "FATAL: required SQL file missing: ${SQL_DIR}/phase_g_l_mapping_apply.sql" >&2
  exit 60
fi

# ---- psql invocation ----
PSQL_CMD="${PSQL_CMD:-psql}"
# shellcheck disable=SC2206
PSQL_INV=( ${PSQL_CMD} )

: "${RUNNER_SQL_DIR:?RUNNER_SQL_DIR must be set (Founder: directory containing the SQL files; test harness: \$STAGE_DIR)}"
if [ ! -f "${RUNNER_SQL_DIR}/phase_g_l_mapping_apply.sql" ]; then
  echo "FATAL: RUNNER_SQL_DIR=${RUNNER_SQL_DIR} does not contain phase_g_l_mapping_apply.sql" >&2
  exit 60
fi

PSQL_BASE=("${PSQL_INV[@]}" "${NEW_DB_URL}" -v ON_ERROR_STOP=1 --no-psqlrc -X -q
  -v fc_mapping_csv_dir="${FC_MAPPING_CSV_DIR}"
  -v fc_sql_dir="${RUNNER_SQL_DIR}")

# ===========================================================================
# PHASE 2: MAPPING APPLY (single transaction)
# ===========================================================================
echo "================================================================"
echo "Phase G-N Wave 4 - Founder apply runner (PHASE 2 only)"
echo "================================================================"
echo ""
echo "PHASE 2: mapping apply (transactional)"
echo "  NEW_DB_URL:      [set]             <- NEVER print the value (Lux ee52b1a §4)"
echo "  FC_MAPPING_CSV:  ${FC_MAPPING_CSV} (dir only, not contents)"
echo ""

# This heredoc NEVER references staging.* or PHASE 1 files. It only touches
# public.* tables via phase_g_l_mapping_apply.sql.
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
  echo "PHASE 1 rows remain committed (import succeeded); mapping-apply aborted."
  echo "Investigate the SQL error above. After fix, re-run this same script only."
  exit 2
fi
echo "PHASE 2 committed OK."
echo ""
echo "================================================================"
echo "Phase G-N Wave 4 apply runner: PHASE 2 OK"
echo "================================================================"
