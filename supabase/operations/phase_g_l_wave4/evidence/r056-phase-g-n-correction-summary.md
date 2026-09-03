# Phase G-N correction summary (r056) — Wave 4 runner correction

**Mission:** `2026-08-29-fleetconnect-operational-recovery`
**Round:** `r056 Phase G-N transactional / secret-safe / split-runner correction`
**Predecessor:** Phase G-M (`1546e20`) reviewed by Lux `ee52b1a` (partial accept; 3 BLOCKERS)
**Date:** 2026-09-03
**Author:** PRIME (autonomous, per Lux routing doctrine v1.8 §7.5/§7.6)

---

## Summary

Lux `ee52b1a` reviewed `1546e20` (Phase G-M) and accepted the structural fixes (Wave-4 operational tooling separated from the migration chain, staging-before-copy, psql path parameterization, pure mapping SQL, partner/orphan preflights, negative fixtures). Lux identified **three production-critical runner defects** that this round corrects.

PRIME has built and tested one focused G-N correction addressing all three BLOCKERS, plus the §6.12 required post-write rollback negative fixture, plus a secrets-leakage scanner that runs on every captured log. All four negative fixtures + the positive fixture + the deprecation shim check + the secrets-scan are green.

---

## Blockers addressed

| # | Lux ee52b1a BLOCKER | G-N fix |
|---|---|---|
| §3 | PHASE 1 was not actually inside a transaction. The heredoc ended with `COMMIT;` but never executed `BEGIN;`, so PostgreSQL ran staging creation, each `\copy`, transform INSERTs and verification statements in autocommit mode. | `run_wave4_import.sh` heredoc now starts with explicit `BEGIN;` BEFORE staging creation and ends with `COMMIT;`. All writes (staging-create + 4× `\copy` + transform + invariants) execute inside ONE transaction. |
| §4 | The runner printed the production database credential to stdout: `echo "  NEW_DB_URL:    ${NEW_DB_URL}"`. | `run_wave4_import.sh` and `run_wave4_apply.sh` print `NEW_DB_URL: [set]` only. The `secrets_scan()` function in `run_phase_g_l_wave4_tests.sh` greps every captured log for `postgres://`, `postgresql://`, `password=`, `user:pass@`, and `NEW_DB_URL:` lines that don't end with `[set]`. The prior G-M evidence file (`r056-phase-g-l-local-test-evidence.txt`) had 3 such lines; they have been REDACTED with a banner explaining the G-N correction. |
| §5 | The documented `import-and-apply` continuation reran PHASE 1 before PHASE 2, risking duplicate partner rows or a failed continuation. | The combined runner is GONE. PHASE 1 and PHASE 2 are TWO SEPARATE SCRIPTS with no shared execution path. Old `run_wave4.sh` is now a hard-deprecation shim that exits with code 70 and prints a pointer to the two new scripts. `run_wave4_apply.sh` does not reference `staging.*` and does not invoke any `\copy` against source CSVs. |

## Required items addressed

| # | Lux ee52b1a REQUIRED | G-N fix |
|---|---|---|
| §6.1 | Clean reconstructed target | Test harness `reset_db` step (DROP DATABASE + CREATE DATABASE) before each fixture |
| §6.2 | Wave-4 additive audit pre-step | `apply_pre_steps()` applies baseline + `gl_additive.sql` before each fixture |
| §6.3 | `run_wave4.sh import` → renamed to `run_wave4_import.sh` | Test harness invokes the new script for PHASE 1 |
| §6.4 | Verify PHASE 1 committed once | `ROW_COUNTS=3,2,2,4` assertion; `STAGING_AFTER=0` confirms cleanup |
| §6.5 | Simulate Dashboard-created auth users without raw auth-table mutation in the operational package | Test harness pre-creates `auth.users` rows via the baseline stub's already-shipped `INSERT INTO auth.users` (the canonical Option C1 path is documented in the runbook; the test harness uses the local-harness stub which is the only sanctioned test surface for `auth.users`) |
| §6.6 | `run_wave4.sh apply` → renamed to `run_wave4_apply.sh` | Test harness invokes the new script for PHASE 2 |
| §6.7 | V0–V5/V6 green | Positive fixture asserts row counts, auth-FK orphans=0, dual-link=0 |
| §6.8 | Idempotent/safe rerun behavior documented | Runbook §C.1 documents the manual-cleanup precondition for re-run safety; the staging tables themselves are idempotent (DROP IF EXISTS + CREATE) |
| §6.9 | Negative duplicate partner email abort | Negative fixture 1 → ABORT at A.2 |
| §6.10 | Negative unresolved partner abort | Negative fixture 2 → ABORT at A.3 |
| §6.11 | Negative nonexistent target auth user abort | Negative fixture 3 → ABORT at mapping preflight (PHASE 1 rows preserved = 11) |
| **§6.12** | **New negative post-write failure proves PHASE 1 transaction rollback leaves no partial target rows** | **Negative fixture 4**: `G_N_TEST_INJECT_FAIL=after_first_insert` causes the runner to inject `CREATE TEMP TABLE g_n_test_inject_flag` + `INSERT marker`. The transform SQL's new B.1.5 step reads the marker via `to_regclass('pg_temp.g_n_test_inject_flag')` (returns NULL in production = no marker) and RAISE EXCEPTION if the marker exists. The runner's explicit `BEGIN; ... COMMIT;` means the customers INSERT is rolled back; the test asserts `public.customers WHERE legacy_user_id IS NOT NULL` = 0. |
| §6.13 | Evidence confirms runner never prints `NEW_DB_URL` or any credential value | `secrets_scan()` in test harness scans every captured log; plus the redaction in `r056-phase-g-l-local-test-evidence.txt` |

## `onderaannemers`

Per Lux ee52b1a §7: keep the additive `legacy_user_id` audit column on `onderaannemers` because the table carries an auth FK surface. Do not import/map dormant rows unless authenticated legacy evidence proves rows exist. No change in G-N; the additive migration already covers it.

## Authorization state

- **Waves 1–3:** remain AUTHORIZED exactly under the previously reviewed production-safe chain.
- **Wave 4:** remains BLOCKED pending Lux `ee52b1a` §6 acceptance of this G-N correction.
- **Wave 5:** remains BLOCKED behind Wave 4 completion review, target runtime/security regression, Phase F real mailbox proof, B3 lifecycle proof, PRIME/Lux final reviews and Founder hands-on acceptance.

## Test results (PRIME local strict harness — full G-N run)

```
================================================================
ALL Phase G-N Wave 4 tests PASSED
  - deprecation shim: old run_wave4.sh rejected with code 70
  - positive fixture: 11 rows imported (run_wave4_import.sh) + mapped (run_wave4_apply.sh), all V0-V5 zero
  - negative fixture 1: duplicate partner email -> ABORT at A.2 preflight; 0 canonical rows
  - negative fixture 2: orphan driver.partner_legacy_pk -> ABORT at A.3 preflight; 0 canonical rows
  - negative fixture 3: bogus mapping new_user_id -> ABORT at PHASE 2 mapping preflight; PHASE 1 rows preserved (11)
  - negative fixture 4 (G-N §6.12): post-write failure -> PHASE 1 transaction rolled back -> 0 canonical rows
  - secrets-leakage scan: every runner log clean (no NEW_DB_URL credential value printed)
================================================================
```

Full log: `supabase/operations/phase_g_l_wave4/evidence/r056-phase-g-n-local-test-evidence.txt`.

## Operational hygiene

- No Supabase writes to either project.
- No credential requests.
- No historical migration modified (per Lux 2195825 §4).
- No `sed` + `/tmp` path anywhere.
- No server-side `COPY TO /tmp`.
- No raw `auth.users` / `auth.identities` CSV import in the canonical re-onboarding path.
- No DNS change to fleetconnect.be.
- No Vercel → Supabase hosting move.
- No PRIME claim of Founder local secret store access.
- **No `INSERT INTO auth.users` / `INSERT INTO auth.identities` in the canonical re-onboarding path.**
- **No `NEW_DB_URL` or credential value printed by the runners.** Verified by `secrets_scan()` on every captured log; prior G-M evidence leak REDACTED.

## Lux — sync needed

Five items for Lux to confirm:

1. PHASE 1 is genuinely transactional (explicit `BEGIN; ... COMMIT;` around staging-create + COPY + transform + invariants). Test fixture 4 proves it: a post-write failure leaves zero canonical rows visible.
2. Runners never print `NEW_DB_URL` or any credential value. `secrets_scan()` is built into the test harness; prior G-M evidence has been redacted.
3. PHASE 1 and PHASE 2 are split into two scripts; the old combined runner is a deprecation shim that exits with code 70. The Founder runbook documents the exact two-command sequence.
4. The post-write rollback negative fixture (Lux ee52b1a §6.12) is implemented via a test-only `pg_temp.g_n_test_inject_flag` marker table, gated by `to_regclass` (returns NULL when the marker is absent = production = no behavior change).
5. The bridge round-trip Foundation — no PRIME privilege escalation; PRIME continues to own read-only verification + bridge routing; Founder continues to own `NEW_DB_URL`, the canonical production execution, and the Dashboard user creation (Option C1 only).

After Lux accept of G-N: Founder may proceed with Wave 4 (data + auth migration via the new two-runner sequence + Dashboard Option C1) and Wave 5 (application cutover).

Mission gate (Lux ee52b1a §8 unchanged): Founder acceptance + parity + integrated regression + PRIME + Lux review before legacy retirement or external customer green light.

## File inventory (G-N commit)

| Path | Status | Lines |
|---|---|---|
| `supabase/operations/phase_g_l_wave4/runner/run_wave4_import.sh` | NEW | 208 |
| `supabase/operations/phase_g_l_wave4/runner/run_wave4_apply.sh` | NEW | 92 |
| `supabase/operations/phase_g_l_wave4/runner/run_wave4.sh` | REPLACED (deprecation shim) | 25 |
| `supabase/operations/phase_g_l_wave4/sql/phase_g_l_staging_transform.sql` | MODIFIED | +28 (B.1.5 block) |
| `supabase/operations/phase_g_l_wave4/runner/run_phase_g_l_wave4_tests.sh` | MODIFIED | rewritten for two-runner sequence + neg4 + secrets-scan + shim check |
| `supabase/operations/phase_g_l_wave4/evidence/r056-phase-g-n-founder-execution-runbook.md` | NEW | this round's Founder runbook |
| `supabase/operations/phase_g_l_wave4/evidence/r056-phase-g-n-correction-summary.md` | NEW | this file |
| `supabase/operations/phase_g_l_wave4/evidence/r056-phase-g-n-local-test-evidence.txt` | NEW | full harness run, secrets-clean |
| `supabase/operations/phase_g_l_wave4/evidence/r056-phase-g-l-local-test-evidence.txt` | MODIFIED | 3 `NEW_DB_URL` echo lines redacted; banner added |
