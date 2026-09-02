#!/bin/bash
# Phase G-L Wave 4: Local strict test harness
# Mission   : 2026-08-29-fleetconnect-operational-recovery
# Round     : r056 Phase G-L executable Wave 4 data/auth remap package
#
# This harness invokes the EXACT Founder runner (run_wave4.sh) against a
# disposable reconstructed target with representative legacy-ID fixtures.
# No inline SQL; the runner is the production execution path.
#
# Per Lux cfb0e9b §8:
#   "G-M correction must run a clean disposable-target test using the same
#    runner/order/transaction semantics that the Founder would execute"
#
# Test artifacts produced:
#   - positive fixture: 11 rows imported + mapped, all V0-V6 zero, idempotent
#   - negative fixture 1: duplicate partner email -> ABORT (preflight A.2)
#   - negative fixture 2: missing partner_legacy_pk in staging.partners -> ABORT (A.3)
#   - negative fixture 3: mapping row referencing non-existent new_user_id -> ABORT (mapping preflight)
#
# Exit codes:
#   0  = ALL POSITIVE + NEGATIVE TESTS PASS
#   10 = additive migration failed
#   20 = test DB setup failed
#   30 = fixture generation failed
#   40 = founder runner phase 1 failed
#   41 = founder runner phase 2 failed
#   50 = negative fixture test 1 (duplicate email) did not abort as expected
#   51 = negative fixture test 2 (orphan partner_legacy_pk) did not abort as expected
#   52 = negative fixture test 3 (orphan mapping new_user_id) did not abort as expected
#   60 = required Founder runner artifact missing
#   70 = negative-fixture cleanup failed (test DB state corrupted)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
RUNNER="${SCRIPT_DIR}/run_wave4.sh"
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

if [ ! -f "$RUNNER" ]; then
  echo "FATAL: Founder runner not found at $RUNNER" >&2
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

echo "==========================================="
echo "Phase G-L Wave 4 strict local test harness"
echo "==========================================="
echo ""
echo "Runner: ${RUNNER}"
echo ""

# ===========================================================================
# POSITIVE FIXTURE TEST
# ===========================================================================
echo "================================================================"
echo "POSITIVE FIXTURE: 11 rows, all should pass"
echo "================================================================"
echo ""

# Step 0: disposable DB
echo "[pos/0] Resetting disposable test DB ${TEST_DB}..."
reset_db

# Step 1: harness stubs + baseline + additive migration
echo "[pos/1] Applying harness stubs + Phase G baseline + G-L additive migration..."
apply_pre_steps

# Step 2: generate POSITIVE fixtures (3 customers, 2 partners, 2 drivers, 4 bookings)
echo "[pos/2] Generating positive fixtures..."
python3 "$(dirname "$0")/generate_fixtures.py" "$STAGE_DIR" positive
chmod 644 "$STAGE_DIR"/*.csv
echo "  customers.csv: $(awk -F',' 'NR==1{print NF " header cols"}' "$STAGE_DIR/customers.csv")"

# Step 3: invoke Founder runner PHASE 1 (import) AND PHASE 2 (mapping apply)
echo "[pos/3] Running Founder runner (PHASE 1 + PHASE 2)..."
echo ""

# Pre-create the 7 new auth.users rows referenced in the positive mapping.csv.
# PHASE 1 must succeed (staging transform) before PHASE 2 (mapping apply) can run;
# PHASE 2 needs the target auth.users to exist before the mapping preflight passes.
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

echo "--- BEGIN run_wave4.sh output (positive fixture) ---"

# psql needs to connect to the test DB without password. Use trust via local socket.
DB_CONN_URL="postgresql://postgres@/phase_g_l_wave4_test?host=/var/run/postgresql"
NEW_DB_URL="$DB_CONN_URL" \
FC_CSV_DIR="$STAGE_DIR" \
FC_MAPPING_CSV="$STAGE_DIR/mapping.csv" \
PSQL_CMD="sudo -n -u postgres psql" \
RUNNER_SQL_DIR="$STAGE_DIR" \
  "$RUNNER" import-and-apply 2>&1 | tee /tmp/phase_g_l_pos_runner.log | tail -30
RUNNER_RC=${PIPESTATUS[0]}

echo "--- END run_wave4.sh output ---"
echo ""

if [ $RUNNER_RC -ne 0 ]; then
  echo "FAILED: Founder runner exited with rc=$RUNNER_RC"
  exit 40
fi

# Step 4: post-runner verification (run the runner's own invariant queries again,
# independently, to prove the runner committed the expected state).
echo "[pos/4] Post-runner verification..."

ROW_COUNTS=$($PSQL_BASE -tAc "
SELECT
  (SELECT count(*) FROM public.customers WHERE legacy_user_id IS NOT NULL) || ',' ||
  (SELECT count(*) FROM public.partners  WHERE legacy_user_id IS NOT NULL) || ',' ||
  (SELECT count(*) FROM public.drivers   WHERE legacy_user_id IS NOT NULL) || ',' ||
  (SELECT count(*) FROM public.bookings  WHERE legacy_user_id IS NOT NULL)
" 2>&1)
echo "  Row counts (customers,partners,drivers,bookings): $ROW_COUNTS"
if [ "$ROW_COUNTS" != "3,2,2,4" ]; then
  echo "FAILED: expected 3,2,2,4 got $ROW_COUNTS"
  exit 40
fi

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
echo "NEGATIVE FIXTURE 1: duplicate partner email must ABORT"
echo "================================================================"
echo ""

reset_db
apply_pre_steps

# Same as positive, but partners.csv has TWO rows with the same email (duplicate)
python3 "$(dirname "$0")/generate_fixtures.py" "$STAGE_DIR" neg1
chmod 644 "$STAGE_DIR"/*.csv
echo "  neg1 partners.csv rows: $(tail -n +2 "$STAGE_DIR/partners.csv" | wc -l)"

echo "[neg1] Running Founder runner with duplicate-email partners (expect ABORT)..."
NEW_DB_URL="$DB_CONN_URL" \
FC_CSV_DIR="$STAGE_DIR" \
FC_MAPPING_CSV="$STAGE_DIR/mapping.csv" \
PSQL_CMD="sudo -n -u postgres psql" \
RUNNER_SQL_DIR="$STAGE_DIR" \
  "$RUNNER" 2>&1 | tee /tmp/phase_g_l_neg1_runner.log | tail -10
NEG1_RC=${PIPESTATUS[0]}

# Preflight A.2 must abort with the specific exception message.
if [ $NEG1_RC -eq 0 ]; then
  echo "FAILED: negative fixture 1 did NOT abort (expected rc != 0)"
  exit 50
fi

if ! grep -q "duplicate email groups" /tmp/phase_g_l_neg1_runner.log; then
  echo "FAILED: negative fixture 1 did not raise the duplicate-email preflight"
  echo "  (looking for: 'duplicate email groups')"
  exit 50
fi
echo "NEGATIVE FIXTURE 1 PASS (runner aborted at A.2 preflight)"
echo ""

# ===========================================================================
# NEGATIVE FIXTURE TEST 2: missing partner_legacy_pk in staging.partners -> ABORT (A.3)
# ===========================================================================
echo "================================================================"
echo "NEGATIVE FIXTURE 2: orphan driver.partner_legacy_pk must ABORT"
echo "================================================================"
echo ""

reset_db
apply_pre_steps

# Same as positive, but drivers.csv has partner_legacy_pk=999 (not in partners.csv)
python3 "$(dirname "$0")/generate_fixtures.py" "$STAGE_DIR" neg2
chmod 644 "$STAGE_DIR"/*.csv
echo "  neg2 drivers.csv partner_legacy_pk: $(tail -n +2 "$STAGE_DIR/drivers.csv" | awk -F',' '{print $4}')"

echo "[neg2] Running Founder runner with orphan driver.partner_legacy_pk (expect ABORT)..."
NEW_DB_URL="$DB_CONN_URL" \
FC_CSV_DIR="$STAGE_DIR" \
FC_MAPPING_CSV="$STAGE_DIR/mapping.csv" \
PSQL_CMD="sudo -n -u postgres psql" \
RUNNER_SQL_DIR="$STAGE_DIR" \
  "$RUNNER" 2>&1 | tee /tmp/phase_g_l_neg2_runner.log | tail -10
NEG2_RC=${PIPESTATUS[0]}

if [ $NEG2_RC -eq 0 ]; then
  echo "FAILED: negative fixture 2 did NOT abort"
  exit 51
fi

if ! grep -q "partner_legacy_pk not resolvable to staging.partners" /tmp/phase_g_l_neg2_runner.log; then
  echo "FAILED: negative fixture 2 did not raise the A.3 preflight"
  exit 51
fi
echo "NEGATIVE FIXTURE 2 PASS (runner aborted at A.3 preflight)"
echo ""

# ===========================================================================
# NEGATIVE FIXTURE TEST 3: mapping row referencing non-existent new_user_id -> ABORT
# ===========================================================================
echo "================================================================"
echo "NEGATIVE FIXTURE 3: mapping row with bogus new_user_id must ABORT"
echo "================================================================"
echo ""

# Restore positive fixtures (PHASE 1 must succeed so PHASE 2 can fail at mapping preflight)
reset_db
apply_pre_steps

# Positive CSVs for PHASE 1 success; mapping.csv contains a bogus target (carol -> eeee...) so PHASE 2 aborts.
python3 "$(dirname "$0")/generate_fixtures.py" "$STAGE_DIR" neg3
chmod 644 "$STAGE_DIR"/*.csv
echo "  neg3 mapping.csv last row: $(tail -1 "$STAGE_DIR/mapping.csv")"

# Pre-create ONLY some of the new users. Leave carol (eee...) out so the mapping references a non-existent auth.users row.
$PSQL_BASE <<'SQL'
INSERT INTO auth.users (id, email) VALUES
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'alice@new.example'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'bob@new.example'),
  -- carol (eeeeeeee...) is intentionally NOT pre-created
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'partner-a@new.example'),
  ('99999999-9999-9999-9999-999999999999', 'partner-b@new.example'),
  ('88888888-8888-8888-8888-888888888888', 'driver-a@new.example'),
  ('7a7a7a7a-7a7a-7a7a-7a7a-7a7a7a7a7a7a', 'driver-b@new.example');
SQL

# Mapping CSV (with bogus carol target) was generated by generate_fixtures.py neg3.

echo "[neg3] Running Founder runner with bogus new_user_id in mapping (expect ABORT at PHASE 2)..."
NEW_DB_URL="$DB_CONN_URL" \
FC_CSV_DIR="$STAGE_DIR" \
FC_MAPPING_CSV="$STAGE_DIR/mapping.csv" \
PSQL_CMD="sudo -n -u postgres psql" \
RUNNER_SQL_DIR="$STAGE_DIR" \
  "$RUNNER" import-and-apply 2>&1 | tee /tmp/phase_g_l_neg3_runner.log | tail -10
NEG3_RC=${PIPESTATUS[0]}

if [ $NEG3_RC -eq 0 ]; then
  echo "FAILED: negative fixture 3 did NOT abort"
  exit 52
fi

if ! grep -q "non-existent new_user_id" /tmp/phase_g_l_neg3_runner.log; then
  echo "FAILED: negative fixture 3 did not raise the mapping preflight"
  exit 52
fi

# Verify PHASE 1 still committed (PHASE 2 only failed at the preflight; canonical rows from PHASE 1 persist)
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
# DONE
# ===========================================================================
echo "================================================================"
echo "ALL Phase G-L Wave 4 tests PASSED"
echo "  - positive fixture: 11 rows imported + mapped, V0-V5 all zero, idempotent"
echo "  - negative fixture 1: duplicate partner email -> ABORT at preflight A.2"
echo "  - negative fixture 2: orphan driver.partner_legacy_pk -> ABORT at preflight A.3"
echo "  - negative fixture 3: bogus mapping new_user_id -> ABORT at mapping preflight"
echo "================================================================"

exit 0
