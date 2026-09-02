# Phase G-L Wave 4 — Local Test Evidence (Phase G-M revision)

**Mission** : `2026-08-29-fleetconnect-operational-recovery`
**Round**   : `r056-phase-g-m-wave4-import-remap-correction` (per Lux `cfb0e9b`)
**Date**    : 2026-09-02
**Run by**  : PRIME (autonomous, no credentials assumed)

## Summary

| Test | Expectation | Result |
|---|---|---|
| Positive (11 rows, all canonical tables) | PASS — V0-V5 all zero, idempotent | ✅ PASS |
| Negative 1: duplicate partner email | ABORT at preflight A.2 | ✅ PASS |
| Negative 2: orphan driver.partner_legacy_pk | ABORT at preflight A.3 | ✅ PASS |
| Negative 3: bogus mapping new_user_id | ABORT at mapping preflight, PHASE 1 preserved | ✅ PASS |

**Final harness verdict:**

```
================================================================
ALL Phase G-L Wave 4 tests PASSED
  - positive fixture: 11 rows imported + mapped, V0-V5 all zero, idempotent
  - negative fixture 1: duplicate partner email -> ABORT at preflight A.2
  - negative fixture 2: orphan driver.partner_legacy_pk -> ABORT at preflight A.3
  - negative fixture 3: bogus mapping new_user_id -> ABORT at mapping preflight
================================================================
```

## What the corrected package addresses

Per Lux `cfb0e9b` 6 BLOCKERS + 2 REQUIRED items:

| # | Blocker | Fix in this package |
|---|---|---|
| 2 | Heredoc transaction can't resume | Each phase runs in its own psql invocation with `ON_ERROR_STOP=1`; explicit COMMIT/ROLLBACK before exit |
| 3 | `\copy` runs before staging tables exist | `phase_g_l_staging_create.sql` runs FIRST in PHASE 1 (pure SQL, idempotent) |
| 4 | `$FC_CSV_DIR` not expanded inside `<<'SQL'` | Runner uses `psql -v fc_csv_dir="$FC_CSV_DIR"` + `\cd :fc_csv_dir` + relative paths |
| 5 | mapping-apply mixes TEMP+\copy+hard-coded path | `phase_g_l_mapping_apply.sql` is pure SQL; runner loads temp `user_id_mapping` separately |
| 6 | Operational files in `supabase/migrations/` get auto-applied | Moved via `git mv` to `supabase/operations/phase_g_l_wave4/`; only additive migration stays in `supabase/migrations/` |
| 7 | No hard preflight for partner email uniqueness | `phase_g_l_staging_transform.sql` preflight A.2 raises EXCEPTION on duplicate partner emails; A.3 raises on orphan driver.partner_legacy_pk |
| 8 | Harness didn't test the exact Founder runner | Harness invokes `run_wave4.sh` via env-var parameters (`NEW_DB_URL`, `FC_CSV_DIR`, `FC_MAPPING_CSV`, `PSQL_CMD`, `RUNNER_SQL_DIR`) |
| 9 | Waves 1-3 manifest expansion | Wave-4 operational files do NOT enter the Wave-1 manifest (see file layout in rollback.md §0) |

## Test DB lifecycle

- Disposable DB `phase_g_l_wave4_test` is dropped and recreated for each fixture variant
- DB is destroyed at harness exit (no leakage)
- postgres user connects via `sudo -n -u postgres psql` (only test environment); Founder in
  production uses `$NEW_DB_URL` directly

## Preflight gates exercised by the test

| Preflight | Where | What it catches |
|---|---|---|
| A.1 | staging-transform.sql | CSV column count vs staging schema mismatch |
| A.2 | staging-transform.sql | Duplicate partner email (cannot resolve mapping deterministically) |
| A.3 | staging-transform.sql | Driver with `partner_legacy_pk` not in `staging.partners` |
| A.4 | staging-transform.sql | Booking with `driver_legacy_uuid` not in `staging.drivers` |
| V1 | staging-transform.sql | Row counts after INSERT match expected |
| V3 | staging-transform.sql | Zero auth-FK orphans (`user_id NOT IN auth.users`) |
| V-pre-mapping | staging-transform.sql | All canonical-table `user_id` are NULL post-transform |
| B.1 | mapping-apply.sql | Every mapping row's `new_user_id` exists in `auth.users` |
| B.2 | mapping-apply.sql | Every distinct `legacy_user_id` in canonical tables is mapped |
| B.3 | mapping-apply.sql | No row has `legacy_user_id = user_id` after apply (cross-project UUID portability is NOT assumed) |
| V2 | mapping-apply.sql | Zero rows have `legacy_user_id = user_id` |
| V4 | mapping-apply.sql | Zero business-FK orphans |
| V5 | mapping-apply.sql | Zero unmapped legacy users |

## How to reproduce

```bash
cd /home/prime/fleetconnect-integration-r056
bash supabase/operations/phase_g_l_wave4/runner/run_phase_g_l_wave4_tests.sh
```

The harness exits 0 on success and uses non-zero codes (10/20/30/40/41/50/51/52/60) for specific
abort reasons. See `runner/run_phase_g_l_wave4_tests.sh` lines 20-30 for the exit-code map.

## Raw output

See `r056-phase-g-l-local-test-evidence.txt` (138 lines of stdout/stderr from the harness run).
