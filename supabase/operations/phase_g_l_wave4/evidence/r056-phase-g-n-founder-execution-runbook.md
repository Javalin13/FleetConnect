# Phase G-N Founder execution runbook — Wave 4 import + mapping apply (TWO-SCRIPT sequence)

**Mission:** `2026-08-29-fleetconnect-operational-recovery`
**Round:** `r056 Phase G-N transactional / secret-safe / split-runner correction`
**Predecessor:** Phase G-M (`1546e20`) reviewed by Lux `ee52b1a` (partial accept; 3 BLOCKERS)
**Date:** 2026-09-03
**Status:** ready for Founder-authenticated execution (G-N accept pending)

---

## A. What changed in G-N (per Lux ee52b1a BLOCKERS)

| Lux BLOCKER | G-N correction | Where |
|---|---|---|
| §3 PHASE 1 had no `BEGIN;` → autocommit → no rollback guarantee | Added explicit `BEGIN; ... COMMIT;` around PHASE 1's full sequence (staging-create + COPY + transform + V1+V3+V-pre-mapping invariants) | `run_wave4_import.sh` heredoc + `phase_g_l_staging_transform.sql` |
| §4 `run_wave4.sh` echoed `NEW_DB_URL` to stdout (credential leak) | New runners print `NEW_DB_URL: [set]` only; secrets-leakage scanner enforces | `run_wave4_import.sh`, `run_wave4_apply.sh`, `run_phase_g_l_wave4_tests.sh::secrets_scan()` |
| §5 `import-and-apply` re-executed PHASE 1 before PHASE 2 (duplicate-partner risk) | The combined runner is **REMOVED**. PHASE 1 and PHASE 2 are TWO SEPARATE SCRIPTS with no shared execution path. Old `run_wave4.sh` is a hard-deprecation shim that exits with code 70. | `run_wave4_import.sh` (NEW), `run_wave4_apply.sh` (NEW), `run_wave4.sh` (DEPRECATION SHIM) |

Plus Lux §6.12 REQUIRED: added a **post-write rollback negative fixture** that injects a deliberate EXCEPTION after the first canonical INSERT (`B.1.5` in `phase_g_l_staging_transform.sql`). The test harness verifies the transaction rolls back, leaving zero new canonical rows.

Plus Lux §7 onderaannemers note: no change. The additive `legacy_user_id` audit column on `onderaannemers` remains accepted; no import/map rows unless authenticated legacy evidence proves they exist.

---

## B. Founder preconditions (unchanged)

| Prerequisite | Status / Source |
|---|---|
| Wave 1 + Wave 2 + Wave 3 migrations already applied to target project `wjbxrgbyhqpiujifwqcf` | Owner: Founder; authorized under prior reviewed chain. |
| Wave 4 pre-step additive audit migration (`supabase/migrations/20260902000001_phase_g_l_additive_legacy_user_id_audit_column.sql`) applied | Run once after Lux accepts Wave 4 unblock. Owner: Founder via `apply_manifest.sh`. |
| Founder holds `NEW_DB_URL` (production Supabase connection string) in 1Password. **Never shared with PRIME.** | Founder-only credential. The new runners print `[set]` instead of the value. |
| Founder has the legacy CSV directory `FC_CSV_DIR` ready (customers.csv, partners.csv, drivers.csv, bookings.csv) | Founder-local; the runners never log its contents. |
| Founder has the auth-user mapping CSV `FC_MAPPING_CSV` ready | Founder-local; the runner never logs its contents. |

---

## C. Exact two-command Founder execution sequence

### C.1 PHASE 1 — staging + transform import

```bash
cd /path/to/FleetConnect

export NEW_DB_URL="postgres://..."          # from 1Password; NEVER printed by the runner
export FC_CSV_DIR="$HOME/Documents/fleetconnect-cutover-2026-09-02"

./supabase/operations/phase_g_l_wave4/runner/run_wave4_import.sh
```

**What this does (single psql transaction):**
1. `BEGIN;`
2. `\i phase_g_l_staging_create.sql` — creates staging schema + four tables (idempotent)
3. `\copy staging.{customers,partners,drivers,bookings}` — loads Founder-local CSVs
4. `\i phase_g_l_staging_transform.sql` — preflights (A.1-A.5) + transform INSERTs (B.1-B.4) + invariants (V1/V3/V-pre-mapping)
5. `COMMIT;` — only if every preflight + invariant passes
6. **Post-commit:** DROP staging schema

**Founder observes (in stdout):**
- `PHASE 1 OK: staging-transform committed` — if every check passed
- `PHASE 1 FAILED (rc=...)` — if any check failed; transaction rolled back automatically; verify with the four canonical-row-count queries the runner prints

**If PHASE 1 fails:** the Founder investigates the SQL error, fixes the source (CSV / preflight gap / migration drift), and **re-runs only PHASE 1**. The script is idempotent on a clean target (staging tables are dropped on entry). On a target with prior PHASE 1 partial commits, the additive `ON CONFLICT DO NOTHING` makes the re-run safe — but only AFTER manually cleaning any half-imported canonical rows.

### C.2 Dashboard user creation (Option C1 only)

Per Lux 39ca1a0 §5 and the Wave 4 §4.2 auth contract:

1. Open Supabase Dashboard → Authentication → Users → **Add user** → **Create new user** with email + auto-confirm
2. For each legacy `auth.users.id` in the export, create a corresponding new target `auth.users.id` (a freshly generated UUID per documented Supabase behavior; the mapping CSV records the correspondence)
3. **Option C2 (`INSERT INTO auth.users` via SQL Editor) is REMOVED.** Even with Founder authenticated, do not use raw SQL to create users.

### C.3 PHASE 2 — mapping apply

```bash
cd /path/to/FleetConnect

export NEW_DB_URL="postgres://..."          # from 1Password
export FC_MAPPING_CSV="$HOME/Documents/fleetconnect-cutover-2026-09-02/r056-phase-g-l-auth-user-id-mapping.csv"

./supabase/operations/phase_g_l_wave4/runner/run_wave4_apply.sh
```

**What this does (single psql transaction, NO PHASE 1 work):**
1. `BEGIN;`
2. `CREATE TEMP TABLE user_id_mapping` (session-scoped, `pg_temp`)
3. `\copy user_id_mapping FROM 'mapping.csv' CSV HEADER`
4. `\i phase_g_l_mapping_apply.sql` — preflight (new_user_id must exist) + UPDATE for customers/partners/drivers/bookings + invariants V2/V4/V5
5. `COMMIT;` — only if every check passes

**Founder observes:**
- `PHASE 2 OK: mapping-apply committed`
- `PHASE 2 FAILED (rc=...)` — if any check failed; **PHASE 1 rows remain committed** (the canonical import persists); re-run only PHASE 2 after fixing the mapping CSV / Dashboard user set

**This script CANNOT re-execute PHASE 1.** It does not reference `staging.*` and does not invoke any `\copy` against the source CSVs. There is no `import-and-apply` argument. There is no combined mode.

### C.4 DO NOT do these things

- **DO NOT** run `./run_wave4.sh` (any argument) — it now exits with code 70.
- **DO NOT** pass any argument to `./run_wave4_import.sh` or `./run_wave4_apply.sh`.
- **DO NOT** re-run PHASE 1 after a successful PHASE 1 commit without first cleaning any partial canonical rows.
- **DO NOT** create users with `INSERT INTO auth.users` via SQL Editor (Option C2 REMOVED).
- **DO NOT** paste `NEW_DB_URL` into chat, Telegram, or any PRIME-controlled surface.

---

## D. Operational hygiene (unchanged from G-L/G-M)

- **No PRIME writes** to either Supabase project. PRIME does not hold `NEW_DB_URL`. PRIME does not run the runners.
- **No raw `auth.users` / `auth.identities` CSV import** in the canonical re-onboarding path.
- **No historical migration modified** (per Lux 2195825 §4).
- **No DNS change to fleetconnect.be.** No Vercel → Supabase hosting move in this round.
- **No `sed` + `/tmp` path anywhere.** All staging paths go through the test harness's `/tmp/phase_g_l_test_stage` or the Founder-local `FC_CSV_DIR`.

---

## E. Wave 4 → Wave 5 unblock conditions (unchanged)

Wave 5 remains blocked behind Wave 4 completion review, target runtime/security regression, Phase F real mailbox proof, B3 lifecycle proof, PRIME/Lux final reviews and Founder hands-on acceptance. See Lux 39ca1a0 §9 and the bridge `CURRENT_MISSION.md` § Definition of Done.

---

## F. Evidence

- **Local test harness:** `run_phase_g_l_wave4_tests.sh` — passes all 4 negative fixtures + positive fixture + deprecation shim check + secrets-leakage scan (`/tmp/phase_g_n_full_run*.log` history, committed evidence in `evidence/r056-phase-g-n-local-test-evidence.txt`).
- **Redaction of prior leak:** `evidence/r056-phase-g-l-local-test-evidence.txt` — 3 `NEW_DB_URL` echo lines replaced with `[REDACTED — G-N §4 correction]`; redaction banner added at top.
- **Correction summary:** `evidence/r056-phase-g-n-correction-summary.md` (companion document).

---

## G. Files in G-N (commit)

| File | Status |
|---|---|
| `supabase/operations/phase_g_l_wave4/runner/run_wave4_import.sh` | NEW (PHASE 1 only, transactional, secret-safe) |
| `supabase/operations/phase_g_l_wave4/runner/run_wave4_apply.sh` | NEW (PHASE 2 only, transactional, secret-safe) |
| `supabase/operations/phase_g_l_wave4/runner/run_wave4.sh` | REPLACED with hard-deprecation shim (exit 70) |
| `supabase/operations/phase_g_l_wave4/sql/phase_g_l_staging_transform.sql` | MODIFIED — added B.1.5 post-write rollback injection point (test-only) |
| `supabase/operations/phase_g_l_wave4/runner/run_phase_g_l_wave4_tests.sh` | MODIFIED — two-runner invocation + neg4 (post-write rollback) + secrets-scan + deprecation-shim check |
| `supabase/operations/phase_g_l_wave4/evidence/r056-phase-g-n-founder-execution-runbook.md` | NEW (this file) |
| `supabase/operations/phase_g_l_wave4/evidence/r056-phase-g-n-correction-summary.md` | NEW |
| `supabase/operations/phase_g_l_wave4/evidence/r056-phase-g-n-local-test-evidence.txt` | NEW (full G-N harness run, secrets-clean) |
| `supabase/operations/phase_g_l_wave4/evidence/r056-phase-g-l-local-test-evidence.txt` | MODIFIED — 3 `NEW_DB_URL` echo lines redacted with banner |
