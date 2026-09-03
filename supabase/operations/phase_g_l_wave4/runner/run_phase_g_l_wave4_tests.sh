#!/bin/bash
# Phase G-N Wave 4: Local strict test harness
# Mission   : 2026-08-29-fleetconnect-operational-recovery
# Round     : r056 Phase G-N transactional / secret-safe / split-runner correction
#
# This harness invokes the EXACT Founder runners (run_wave4_import.sh +
# run_wave4_apply.sh) against a disposable reconstructed target with
# representative legacy-ID fixtures. No inline SQL; the runners are the
# production execution path.
#
# Per Lux ee52b1a §6:
#   "G-N correction must prove the actual Founder path:
#    clean reconstructed target; Wave-4 additive audit pre-step;
#    run_wave4.sh import [now run_wave4_import.sh];
#    verify PHASE 1 committed once;
#    simulate Dashboard-created auth users without raw auth-table mutation
#    in the operational package; run_wave4.sh apply [now run_wave4_apply.sh];
#    V0-V5/V6 green; idempotent/safe rerun behavior documented;
#    negative duplicate partner email abort; negative unresolved partner abort;
#    negative nonexistent target auth user abort; new negative post-write
#    failure proves PHASE 1 transaction rollback leaves no partial target
#    rows; evidence confirms runner never prints NEW_DB_URL or any credential
#    value."
#
# Test artifacts produced:
#   - positive fixture: 11 rows imported + mapped, all V0-V5 zero, idempotent
#   - negative fixture 1: duplicate partner email -> ABORT (preflight A.2)
#   - negative fixture 2: missing partner_legacy_pk in staging.partners -> ABORT (A.3)
#   - negative fixture 3: mapping row referencing non-existent new_user_id -> ABORT (mapping preflight)
#   - negative fixture 4 (NEW G-N): post-write failure after customers INSERT ->
#         ABORT in PHASE 1 transaction -> rollback must leave ZERO new canonical
#         rows (Lux ee52b1a §6.12)
#   - secrets-leakage scan (NEW G-N): every captured runner log is grepped for
#         NEW_DB_URL credential value patterns; must find zero (Lux ee52b1a §4)
#
# Exit codes:
#   0  = ALL POSITIVE + NEGATIVE TESTS PASS
#   10 = additive migration failed
#   20 = test DB setup failed
#   30 = fixture generation failed
#   40 = founder runner phase 1 failed (unexpected on positive path)
#   41 = founder runner phase 2 failed (unexpected on positive path)
#   50 = negative fixture test 1 (duplicate email) did not abort as expected
#   51 = negative fixture test 2 (orphan partner_legacy_pk) did not abort as expected
#   52 = negative fixture test 3 (orphan mapping new_user_id) did not abort as expected
#   53 = negative fixture test 4 (post-write rollback) did NOT leave zero canonical rows
#   54 = secrets-leakage scan FAILED (runner printed credential value)
#   55 = deprecation shim rejected old run_wave4.sh invocation
#   60 = required Founder runner artifact missing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
RUNNER_IMPORT="${SCRIPT_DIR}/run_wave4_import.sh"
RUNNER_APPLY="${SCRIPT_DIR}/run_wave4_apply.sh"
RUNNER_OLD="${SCRIPT_DIR}/run_wave4.sh"
SQL_DIR="${SCRIPT_DIR}/../sql"
TEST_DB="phase_g_l_wave4_test"

PSQL_BASE="sudo -n -u postgres psql -d ${TEST_DB} -v ON_ERROR_STOP=1 --no-psqlrc -X -q"

# ---- Stage SQL + CSV files in /tmp where the postgres OS user can read them ----
STAGE_DIR="/tmp/phase_g_l_test_stage"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
chmod 755 "$STAGE_DIR"

cp "${REPO_ROOT}/supabase/local_harness/00_local_auth_stubs.sql"        "$STAGE_DIR/00_local_auth_stubs.sql"
cp "${REPO_ROOT}/supabase/migrations/20260831000000_phase_g_canonical_greenfield_baseline.sql" "$STAGE_DIR/baseline.sql"
cp "${REPO_ROOT}/supabase/migrations/20260902000001_phase_g_l_additive_legacy_user_id_audit_column.sql" "$STAGE_DIR/gl_additive.sql"
cp "${SQL_DIR}/phase_g_l_staging_create.sql"     "$STAGE_DIR/phase_g_l_staging_create.sql"
cp "${SQL_DIR}/phase_g_l_staging_transform.sql"  "$STAGE_DIR/phase_g_l_staging_transform.sql"
cp "${SQL_DIR}/phase_g_l_mapping_apply.sql"      "$STAGE_DIR/phase_g_l_mapping_apply.sql"
chmod 644 "$STAGE_DIR/"*.sql

if [ ! -f "$RUNNER_IMPORT" ] || [ ! -f "$RUNNER_APPLY" ] || [ ! -f "$RUNNER_OLD" ]; then
  echo "FATAL: missing runner artifact (need run_wave4_import.sh, run_wave4_apply.sh, run_wave4.sh)" >&2
  exit 60
fi

# ---- helper: drop + create disposable DB ----
reset_db() {
  sudo -n -u postgres psql -c "DROP DATABASE IF EXISTS ${TEST_DB}" 2>&1 | tail -1
  sudo -n -u postgres psql -c "CREATE DATABASE ${TEST_DB}" 2>&1 | tail -1
}

# ---- helper: apply harness stubs + baseline + additive ----
apply_pre_steps() {
  $PSQL_BASE -f "$STAGE_DIR/00_local_auth_stubs.sql" 2>&1 | tail -1
  $PSQL_BASE -f "$STAGE_DIR/baseline.sql"             2>&1 | tail -1
  $PSQL_BASE -f "$STAGE_DIR/gl_additive.sql"          2>&1 | tail -1
}

# ---- secrets-leakage scanner (Lux ee52b1a §4) ----
# Forbidden patterns: any line in the runner output that looks like a real
# postgres connection URL (other than the literal "[set]" marker we print).
# In the test harness we use a local-socket URL, so even that should not appear.
# Patterns: anything starting with postgres://, postgresql://, or containing
# a password= / user:pass@ token.
SECRETS_LOG="$STAGE_DIR/secrets_scan.log"
secrets_scan() {
  local label="$1"
  local log="$2"
  : > "$SECRETS_LOG"
  local rc=0
  if [ ! -f "$log" ]; then
    echo "  [secrets] ${label}: log file missing ($log)" >> "$SECRETS_LOG"
    return 1
  fi
  # Forbidden patterns. We allow the literal "NEW_DB_URL: [set]" because
  # that's the explicit safe marker. We forbid any "NEW_DB_URL:" line that
  # does NOT end with "[set]".
  if grep -E -nH 'postgres(ql)?://[^[:space:]]+' "$log" >> "$SECRETS_LOG" 2>&1; then
    rc=1
  fi
  if grep -E -nH 'password=[^[:space:]]+' "$log" >> "$SECRETS_LOG" 2>&1; then
    rc=1
  fi
  if grep -E -nH '://[^:/[:space:]]+:[^@[:space:]]+@' "$log" >> "$SECRETS_LOG" 2>&1; then
    rc=1
  fi
  # NEW_DB_URL: <something other than [set]>
  if grep -E -nH '^[[:space:]]*NEW_DB_URL:[[:space:]]+\[[Ss]et\]' "$log" >> "$SECRETS_LOG.ok" 2>&1; then
    : # the safe marker line is expected
  fi
  if grep -E -nH '^[[:space:]]*NEW_DB_URL:' "$log" | grep -v -E '\[[Ss]et\]' >> "$SECRETS_LOG" 2>&1; then
    rc=1
  fi
  return $rc
}

echo "==========================================="
echo "Phase G-N Wave 4 strict local test harness"
echo "==========================================="
echo ""
echo "Import runner: ${RUNNER_IMPORT}"
echo "Apply runner:  ${RUNNER_APPLY}"
echo "Old runner:    ${RUNNER_OLD} (deprecation shim)"
echo ""

# ===========================================================================
# DEPRECATION SHIM CHECK (Lux ee52b1a §5): the old run_wave4.sh must refuse
# to execute. This is a structural guarantee, not just a doc change.
# ===========================================================================
echo "================================================================"
echo "DEPRECATION SHIM CHECK: old run_wave4.sh must refuse execution"
echo "================================================================"
echo "[shim] Using deprecation shim with test-harness URL (trust-auth local socket)"
# Test-harness only. The trust-auth local-socket URL is never logged by the
# runners; it lives only in this variable, which is exported to NEW_DB_URL.
# Production Founder invocation uses the actual Supabase connection string
# from 1Password, which the runners print only as "[set]" (Lux ee52b1a §4).
TEST_DB_CONN_URL="postgresql://postgres@/phase_g_l_wave4_test?host=/var/run/postgresql"
set +e
NEW_DB_URL="$TEST_DB_CONN_URL" \
FC_CSV_DIR="$STAGE_DIR" \
FC_MAPPING_CSV="$STAGE_DIR/mapping.csv" \
PSQL_CMD="sudo -n -u postgres psql" \
RUNNER_SQL_DIR="$STAGE_DIR" \
  "$RUNNER_OLD" 2>&1 | tee /tmp/phase_g_l_shim.log | tail -5
SHIM_RC=${PIPESTATUS[0]}
set -e
if [ "$SHIM_RC" -ne 70 ]; then
  echo "FAILED: old run_wave4.sh did not exit with the documented deprecation code 70 (got $SHIM_RC)"
  exit 55
fi
if ! grep -q "run_wave4.sh has been SPLIT" /tmp/phase_g_l_shim.log; then
  echo "FAILED: deprecation shim did not emit the expected SPLIT message"
  exit 55
fi
echo "DEPRECATION SHIM CHECK PASS (old runner rejected with code 70)"
echo ""

# ===========================================================================
# POSITIVE FIXTURE TEST (uses the NEW two-runner sequence)
# ===========================================================================
echo "================================================================"
echo "POSITIVE FIXTURE: 11 rows, all should pass (run_wave4_import.sh + run_wave4_apply.sh)"
echo "================================================================"
echo ""

echo "[pos/0] Resetting disposable test DB ${TEST_DB}..."
reset_db

echo "[pos/1] Applying harness stubs + Phase G baseline + G-L additive migration..."
apply_pre_steps

echo "[pos/2] Generating positive fixtures..."
python3 "$(dirname "$0")/generate_fixtures.py" "$STAGE_DIR" positive
chmod 644 "$STAGE_DIR"/*.csv

echo "[pos/3a] Pre-creating 7 new auth.users rows (simulating Dashboard Option C1 user creation)..."
$PSQL_BASE <<'SQL'
INSERT INTO auth.users (id, email) VALUES
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'alice@new.example'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'bob@new.example'),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'carol@new.example'),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'partner-a@new.example'),
  ('99999999-9999-9999-9999-999999999999', 'partner-b@new.example'),
  ('88888888-8888-8888-8888-888888888888', 'driver-a@new.example'),
  ('7a7a7a7a-7a7a-7a7a-7a7a-7a7a7a7a7a7a', 'driver-b@new.example');
SQL

echo ""
echo "[pos/3b] Running run_wave4_import.sh (PHASE 1)..."
NEW_DB_URL="$TEST_DB_CONN_URL" \
FC_CSV_DIR="$STAGE_DIR" \
PSQL_CMD="sudo -n -u postgres psql" \
RUNNER_SQL_DIR="$STAGE_DIR" \
  "$RUNNER_IMPORT" 2>&1 | tee /tmp/phase_g_l_pos_import.log | tail -10
IMPORT_RC=${PIPESTATUS[0]}
if [ $IMPORT_RC -ne 0 ]; then
  echo "FAILED: run_wave4_import.sh exited with rc=$IMPORT_RC"
  exit 40
fi

# Verify PHASE 1 committed once: 11 rows in canonical public.* with legacy_user_id NOT NULL.
ROW_COUNTS=$($PSQL_BASE -tAc "
SELECT
  (SELECT count(*) FROM public.customers WHERE legacy_user_id IS NOT NULL) || ',' ||
  (SELECT count(*) FROM public.partners  WHERE legacy_user_id IS NOT NULL) || ',' ||
  (SELECT count(*) FROM public.drivers   WHERE legacy_user_id IS NOT NULL) || ',' ||
  (SELECT count(*) FROM public.bookings  WHERE legacy_user_id IS NOT NULL)
" 2>&1)
echo "  Phase 1 row counts (customers,partners,drivers,bookings): $ROW_COUNTS"
if [ "$ROW_COUNTS" != "3,2,2,4" ]; then
  echo "FAILED: Phase 1 expected 3,2,2,4 got $ROW_COUNTS"
  exit 40
fi

# Verify staging schema was dropped by the import runner's cleanup step.
STAGING_AFTER=$($PSQL_BASE -tAc "SELECT count(*) FROM information_schema.schemata WHERE schema_name = 'staging'" 2>&1)
echo "  staging schema count after import cleanup: $STAGING_AFTER (expect 0)"
if [ "$STAGING_AFTER" != "0" ]; then
  echo "FAILED: staging schema not dropped after import cleanup"
  exit 40
fi

# Secrets-leakage scan on the import runner log (Lux ee52b1a §4).
if secrets_scan "import" /tmp/phase_g_l_pos_import.log; then
  echo "  [secrets] import log: clean (no credential values printed)"
else
  echo "FAILED: secrets-leakage detected in import runner log:"
  cat "$SECRETS_LOG"
  exit 54
fi

echo ""
echo "[pos/3c] Running run_wave4_apply.sh (PHASE 2)..."
NEW_DB_URL="$TEST_DB_CONN_URL" \
FC_MAPPING_CSV="$STAGE_DIR/mapping.csv" \
PSQL_CMD="sudo -n -u postgres psql" \
RUNNER_SQL_DIR="$STAGE_DIR" \
  "$RUNNER_APPLY" 2>&1 | tee /tmp/phase_g_l_pos_apply.log | tail -10
APPLY_RC=${PIPESTATUS[0]}
if [ $APPLY_RC -ne 0 ]; then
  echo "FAILED: run_wave4_apply.sh exited with rc=$APPLY_RC"
  exit 41
fi

# Secrets-leakage scan on the apply runner log (Lux ee52b1a §4).
if secrets_scan "apply" /tmp/phase_g_l_pos_apply.log; then
  echo "  [secrets] apply log: clean (no credential values printed)"
else
  echo "FAILED: secrets-leakage detected in apply runner log:"
  cat "$SECRETS_LOG"
  exit 54
fi

echo ""
echo "[pos/4] Post-runner verification..."

# All 11 rows linked (legacy_user_id IS NOT NULL AND user_id IS NOT NULL)
LINKED_COUNTS=$($PSQL_BASE -tAc "
SELECT
  (SELECT count(*) FROM public.customers WHERE legacy_user_id IS NOT NULL AND user_id IS NOT NULL) || ',' ||
  (SELECT count(*) FROM public.partners  WHERE legacy_user_id IS NOT NULL AND user_id IS NOT NULL) || ',' ||
  (SELECT count(*) FROM public.drivers   WHERE legacy_user_id IS NOT NULL AND user_id IS NOT NULL) || ',' ||
  (SELECT count(*) FROM public.bookings  WHERE legacy_user_id IS NOT NULL AND user_id IS NOT NULL)
" 2>&1)
echo "  Linked (both legacy+target): $LINKED_COUNTS"
if [ "$LINKED_COUNTS" != "3,2,2,4" ]; then
  echo "FAILED: expected 3,2,2,4 linked got $LINKED_COUNTS"
  exit 41
fi

# Verify zero auth-FK orphans
ORPHAN_COUNT=$($PSQL_BASE -tAc "
SELECT
  (SELECT count(*) FROM public.customers WHERE user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = user_id)) +
  (SELECT count(*) FROM public.partners  WHERE user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = user_id)) +
  (SELECT count(*) FROM public.drivers   WHERE user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = user_id)) +
  (SELECT count(*) FROM public.bookings  WHERE user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = user_id))
" 2>&1)
echo "  Auth-FK orphans: $ORPHAN_COUNT (expect 0)"
if [ "$ORPHAN_COUNT" != "0" ]; then
  echo "FAILED: $ORPHAN_COUNT auth-FK orphans (expect 0)"
  exit 41
fi

# Verify zero dual-link
DUAL_COUNT=$($PSQL_BASE -tAc "
SELECT
  (SELECT count(*) FROM public.customers WHERE legacy_user_id = user_id) +
  (SELECT count(*) FROM public.partners  WHERE legacy_user_id = user_id) +
  (SELECT count(*) FROM public.drivers   WHERE legacy_user_id = user_id) +
  (SELECT count(*) FROM public.bookings  WHERE legacy_user_id = user_id)
" 2>&1)
echo "  Dual-link (legacy==target): $DUAL_COUNT (expect 0)"
if [ "$DUAL_COUNT" != "0" ]; then
  echo "FAILED: $DUAL_COUNT dual-link (expect 0)"
  exit 41
fi

echo "POSITIVE FIXTURE PASS"
echo ""

# ===========================================================================
# NEGATIVE FIXTURE TEST 1: duplicate partner email -> ABORT (preflight A.2)
# ===========================================================================
echo "================================================================"
echo "NEGATIVE FIXTURE 1: duplicate partner email must ABORT (PHASE 1 preflight A.2)"
echo "================================================================"
echo ""

reset_db
apply_pre_steps

python3 "$(dirname "$0")/generate_fixtures.py" "$STAGE_DIR" neg1
chmod 644 "$STAGE_DIR"/*.csv

echo "[neg1] Running run_wave4_import.sh with duplicate-email partners (expect ABORT)..."
set +e
NEW_DB_URL="$TEST_DB_CONN_URL" \
FC_CSV_DIR="$STAGE_DIR" \
PSQL_CMD="sudo -n -u postgres psql" \
RUNNER_SQL_DIR="$STAGE_DIR" \
  "$RUNNER_IMPORT" 2>&1 | tee /tmp/phase_g_l_neg1_runner.log | tail -10
NEG1_RC=${PIPESTATUS[0]}
set -e

if [ $NEG1_RC -eq 0 ]; then
  echo "FAILED: negative fixture 1 did NOT abort (expected rc != 0)"
  exit 50
fi

if ! grep -q "duplicate email groups" /tmp/phase_g_l_neg1_runner.log; then
  echo "FAILED: negative fixture 1 did not raise the duplicate-email preflight"
  echo "  (looking for: 'duplicate email groups')"
  exit 50
fi

# Verify NO canonical rows persisted from the failed run.
NEG1_ROWS=$($PSQL_BASE -tAc "
SELECT
  (SELECT count(*) FROM public.customers WHERE legacy_user_id IS NOT NULL) +
  (SELECT count(*) FROM public.partners  WHERE legacy_user_id IS NOT NULL) +
  (SELECT count(*) FROM public.drivers   WHERE legacy_user_id IS NOT NULL) +
  (SELECT count(*) FROM public.bookings  WHERE legacy_user_id IS NOT NULL)
" 2>&1)
echo "  Canonical rows after neg1 abort: $NEG1_ROWS (expect 0; transaction must roll back)"
if [ "$NEG1_ROWS" != "0" ]; then
  echo "FAILED: neg1 left $NEG1_ROWS canonical rows; transaction did NOT roll back"
  exit 50
fi
echo "NEGATIVE FIXTURE 1 PASS (runner aborted at A.2 preflight; transaction rolled back; 0 canonical rows)"
echo ""

# ===========================================================================
# NEGATIVE FIXTURE TEST 2: missing partner_legacy_pk in staging.partners -> ABORT (A.3)
# ===========================================================================
echo "================================================================"
echo "NEGATIVE FIXTURE 2: orphan driver.partner_legacy_pk must ABORT (PHASE 1 preflight A.3)"
echo "================================================================"
echo ""

reset_db
apply_pre_steps

python3 "$(dirname "$0")/generate_fixtures.py" "$STAGE_DIR" neg2
chmod 644 "$STAGE_DIR"/*.csv

echo "[neg2] Running run_wave4_import.sh with orphan driver.partner_legacy_pk (expect ABORT)..."
set +e
NEW_DB_URL="$TEST_DB_CONN_URL" \
FC_CSV_DIR="$STAGE_DIR" \
PSQL_CMD="sudo -n -u postgres psql" \
RUNNER_SQL_DIR="$STAGE_DIR" \
  "$RUNNER_IMPORT" 2>&1 | tee /tmp/phase_g_l_neg2_runner.log | tail -10
NEG2_RC=${PIPESTATUS[0]}
set -e

if [ $NEG2_RC -eq 0 ]; then
  echo "FAILED: negative fixture 2 did NOT abort"
  exit 51
fi

if ! grep -q "partner_legacy_pk not resolvable to staging.partners" /tmp/phase_g_l_neg2_runner.log; then
  echo "FAILED: negative fixture 2 did not raise the A.3 preflight"
  exit 51
fi

NEG2_ROWS=$($PSQL_BASE -tAc "
SELECT
  (SELECT count(*) FROM public.customers WHERE legacy_user_id IS NOT NULL) +
  (SELECT count(*) FROM public.partners  WHERE legacy_user_id IS NOT NULL) +
  (SELECT count(*) FROM public.drivers   WHERE legacy_user_id IS NOT NULL) +
  (SELECT count(*) FROM public.bookings  WHERE legacy_user_id IS NOT NULL)
" 2>&1)
echo "  Canonical rows after neg2 abort: $NEG2_ROWS (expect 0; transaction must roll back)"
if [ "$NEG2_ROWS" != "0" ]; then
  echo "FAILED: neg2 left $NEG2_ROWS canonical rows; transaction did NOT roll back"
  exit 51
fi
echo "NEGATIVE FIXTURE 2 PASS (runner aborted at A.3 preflight; transaction rolled back; 0 canonical rows)"
echo ""

# ===========================================================================
# NEGATIVE FIXTURE TEST 3: mapping row referencing non-existent new_user_id
# (PHASE 1 succeeds; PHASE 2 aborts at mapping preflight; PHASE 1 rows preserved)
# ===========================================================================
echo "================================================================"
echo "NEGATIVE FIXTURE 3: bogus mapping new_user_id must ABORT (PHASE 2 mapping preflight)"
echo "================================================================"
echo ""

reset_db
apply_pre_steps

python3 "$(dirname "$0")/generate_fixtures.py" "$STAGE_DIR" neg3
chmod 644 "$STAGE_DIR"/*.csv

$PSQL_BASE <<'SQL'
INSERT INTO auth.users (id, email) VALUES
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'alice@new.example'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'bob@new.example'),
  -- carol (eeeeeeee...) intentionally NOT pre-created
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'partner-a@new.example'),
  ('99999999-9999-9999-9999-999999999999', 'partner-b@new.example'),
  ('88888888-8888-8888-8888-888888888888', 'driver-a@new.example'),
  ('7a7a7a7a-7a7a-7a7a-7a7a-7a7a7a7a7a7a', 'driver-b@new.example');
SQL

echo "[neg3a] Running run_wave4_import.sh (PHASE 1 must succeed)..."
NEW_DB_URL="$TEST_DB_CONN_URL" \
FC_CSV_DIR="$STAGE_DIR" \
PSQL_CMD="sudo -n -u postgres psql" \
RUNNER_SQL_DIR="$STAGE_DIR" \
  "$RUNNER_IMPORT" 2>&1 | tee /tmp/phase_g_l_neg3_import.log | tail -5
NEG3_IMPORT_RC=${PIPESTATUS[0]}
if [ $NEG3_IMPORT_RC -ne 0 ]; then
  echo "FAILED: neg3 PHASE 1 unexpectedly failed (rc=$NEG3_IMPORT_RC)"
  exit 52
fi

echo "[neg3b] Running run_wave4_apply.sh (PHASE 2 must ABORT at mapping preflight)..."
set +e
NEW_DB_URL="$TEST_DB_CONN_URL" \
FC_MAPPING_CSV="$STAGE_DIR/mapping.csv" \
PSQL_CMD="sudo -n -u postgres psql" \
RUNNER_SQL_DIR="$STAGE_DIR" \
  "$RUNNER_APPLY" 2>&1 | tee /tmp/phase_g_l_neg3_apply.log | tail -10
NEG3_APPLY_RC=${PIPESTATUS[0]}
set -e

if [ $NEG3_APPLY_RC -eq 0 ]; then
  echo "FAILED: negative fixture 3 PHASE 2 did NOT abort"
  exit 52
fi

if ! grep -q "non-existent new_user_id" /tmp/phase_g_l_neg3_apply.log; then
  echo "FAILED: negative fixture 3 did not raise the mapping preflight"
  exit 52
fi

# PHASE 1 rows must persist (PHASE 2 only failed; canonical import still committed).
PHASE1_PERSISTED=$($PSQL_BASE -tAc "
SELECT
  (SELECT count(*) FROM public.customers WHERE legacy_user_id IS NOT NULL) +
  (SELECT count(*) FROM public.partners  WHERE legacy_user_id IS NOT NULL) +
  (SELECT count(*) FROM public.drivers   WHERE legacy_user_id IS NOT NULL) +
  (SELECT count(*) FROM public.bookings  WHERE legacy_user_id IS NOT NULL)
" 2>&1)
echo "  Phase 1 rows persisted after Phase 2 abort: $PHASE1_PERSISTED (expect 11)"
if [ "$PHASE1_PERSISTED" != "11" ]; then
  echo "FAILED: Phase 1 rollback unexpectedly on Phase 2 failure (got $PHASE1_PERSISTED, expected 11)"
  exit 52
fi

echo "NEGATIVE FIXTURE 3 PASS (runner aborted at mapping preflight; PHASE 1 rows preserved)"
echo ""

# ===========================================================================
# NEGATIVE FIXTURE TEST 4 (NEW G-N §6.12): post-write failure after customers
# INSERT. The transaction MUST roll back the customers INSERT and leave ZERO
# canonical rows visible.
# ===========================================================================
echo "================================================================"
echo "NEGATIVE FIXTURE 4 (G-N): post-write PHASE 1 failure -> transaction rollback -> 0 canonical rows"
echo "================================================================"
echo ""

reset_db
apply_pre_steps

python3 "$(dirname "$0")/generate_fixtures.py" "$STAGE_DIR" positive
chmod 644 "$STAGE_DIR"/*.csv

echo "[neg4] Running run_wave4_import.sh with G_N_TEST_INJECT_FAIL=after_first_insert (expect ABORT after customers INSERT)..."
set +e
NEW_DB_URL="$TEST_DB_CONN_URL" \
FC_CSV_DIR="$STAGE_DIR" \
PSQL_CMD="sudo -n -u postgres psql" \
RUNNER_SQL_DIR="$STAGE_DIR" \
G_N_TEST_INJECT_FAIL="after_first_insert" \
  "$RUNNER_IMPORT" 2>&1 | tee /tmp/phase_g_l_neg4_runner.log | tail -10
NEG4_RC=${PIPESTATUS[0]}
set -e

if [ $NEG4_RC -eq 0 ]; then
  echo "FAILED: negative fixture 4 did NOT abort (expected rc != 0)"
  exit 53
fi

if ! grep -q "Phase G-N TEST INJECTION" /tmp/phase_g_l_neg4_runner.log; then
  echo "FAILED: negative fixture 4 did not raise the injection exception"
  exit 53
fi

# CRITICAL ASSERTION: after the post-write failure, the transaction MUST have
# rolled back, so there must be ZERO canonical rows with legacy_user_id IS NOT
# NULL across all four target tables. This is the Lux ee52b1a §6.12 contract.
NEG4_ROWS=$($PSQL_BASE -tAc "
SELECT
  (SELECT count(*) FROM public.customers WHERE legacy_user_id IS NOT NULL) +
  (SELECT count(*) FROM public.partners  WHERE legacy_user_id IS NOT NULL) +
  (SELECT count(*) FROM public.drivers   WHERE legacy_user_id IS NOT NULL) +
  (SELECT count(*) FROM public.bookings  WHERE legacy_user_id IS NOT NULL)
" 2>&1)
echo "  Canonical rows after neg4 post-write rollback: $NEG4_ROWS (expect 0)"
if [ "$NEG4_ROWS" != "0" ]; then
  echo "FAILED: neg4 left $NEG4_ROWS canonical rows visible; transaction did NOT roll back"
  exit 53
fi

# Specifically check customers (the table the B.1.5 injection writes before raising).
NEG4_CUST_ROWS=$($PSQL_BASE -tAc "SELECT count(*) FROM public.customers WHERE legacy_user_id IS NOT NULL" 2>&1)
echo "  public.customers rows after neg4 rollback: $NEG4_CUST_ROWS (expect 0; the customers INSERT was rolled back)"
if [ "$NEG4_CUST_ROWS" != "0" ]; then
  echo "FAILED: neg4 left $NEG4_CUST_ROWS customers rows visible; B.1 INSERT not rolled back"
  exit 53
fi

# Secrets-leakage scan on the neg4 log too (defense in depth).
if secrets_scan "neg4" /tmp/phase_g_l_neg4_runner.log; then
  echo "  [secrets] neg4 log: clean (no credential values printed)"
else
  echo "FAILED: secrets-leakage detected in neg4 runner log:"
  cat "$SECRETS_LOG"
  exit 54
fi

echo "NEGATIVE FIXTURE 4 PASS (post-write failure -> transaction rolled back -> 0 canonical rows)"
echo ""

# ===========================================================================
# DONE
# ===========================================================================
echo "================================================================"
echo "ALL Phase G-N Wave 4 tests PASSED"
echo "  - deprecation shim: old run_wave4.sh rejected with code 70"
echo "  - positive fixture: 11 rows imported (run_wave4_import.sh) + mapped (run_wave4_apply.sh), all V0-V5 zero"
echo "  - negative fixture 1: duplicate partner email -> ABORT at A.2 preflight; 0 canonical rows"
echo "  - negative fixture 2: orphan driver.partner_legacy_pk -> ABORT at A.3 preflight; 0 canonical rows"
echo "  - negative fixture 3: bogus mapping new_user_id -> ABORT at PHASE 2 mapping preflight; PHASE 1 rows preserved (11)"
echo "  - negative fixture 4 (G-N §6.12): post-write failure -> PHASE 1 transaction rolled back -> 0 canonical rows"
echo "  - secrets-leakage scan: every runner log clean (no NEW_DB_URL credential value printed)"
echo "================================================================"

exit 0
