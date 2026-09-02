# Phase G-L Wave 4 — Founder Execution Runbook (Phase G-M revision)

**Mission** : `2026-08-29-fleetconnect-operational-recovery`
**Round**   : `r056-phase-g-m-wave4-import-remap-correction` (per Lux `cfb0e9b` partial-accept / G-M required)
**Audience** : **Founder only.** PRIME never assumes it holds `$NEW_DB_URL`. The Founder is the
authenticated execution principal for every step that touches the live target project.

> **Why this runbook exists.** Lux `cfb0e9b` rejected the original Phase G-L Wave 4 package because
> six BLOCKERS made the live execution contract unsafe (transaction can't be resumed, `\copy`
> before staging tables, `$FC_CSV_DIR` not expanded inside quoted heredoc, mapping-apply mixing
> `\copy` + hard-coded path, operational files in `supabase/migrations/` that auto-apply, no
> hard preflight for partner email uniqueness, harness didn't exercise the exact Founder runner).
> The corrected package has been verified end-to-end against a disposable reconstructed target:
> 1 positive fixture (11 rows, all V0-V5 zero) + 3 negative fixtures (duplicate email, orphan
> driver FK, bogus mapping new_user_id) — all 4 PASS. See `local-test-evidence.md`.

---

## §0 — Preconditions

- **0.1** Target project is `wjbxrgbyhqpiujifwqcf`. Legacy (read-only) is `rreqjjrmvytnwnsidmqi`.
- **0.2** Founder is authenticated to the target project via the Supabase Dashboard (SQL Editor
  / Edge Functions / Auth) or via `psql` over a TLS connection whose DSN is held by the Founder
  only. **Do not paste `$NEW_DB_URL` into PRIME, Telegram, the bridge, this repo, or any
  evidence file.**
- **0.3** Wave 1 (production-safe schema apply) is complete and green on the target project.
  Wave 2 (seven Edge Functions) and Wave 3 (Dashboard secrets) are still authorized under the
  previously reviewed chain.
- **0.4** The additive migration `supabase/migrations/20260902000001_phase_g_l_additive_legacy_user_id_audit_column.sql`
  has been applied to the target project. It is the **only** Wave-4 file that lives under
  `supabase/migrations/`. All other Wave-4 operational files live under
  `supabase/operations/phase_g_l_wave4/` and are **not** part of the Wave-1 manifest.
- **0.5** Founder has Dashboard access (Authentication → Users → "Add user" → "Create new user"
  with auto-confirm). Per Lux `39ca1a0` §5, Option C2 (direct SQL `INSERT INTO auth.users` /
  `auth.identities`) is REMOVED and is not a fallback path.

---

## §A — Prepare Founder-local artifacts

These files are stored **only on the Founder's workstation**. They never enter the repo,
PRIME, the bridge, or any evidence file.

### §A.1 — Four application-data CSVs (legacy export)

Founder runs a one-time export from the legacy project `rreqjjrmvytnwnsidmqi` to produce:

- `customers.csv` — columns matching `staging.customers` schema (see
  `sql/phase_g_l_staging_create.sql`)
- `partners.csv` — columns matching `staging.partners`
- `drivers.csv` — columns matching `staging.drivers`
- `bookings.csv` — columns matching `staging.bookings`

The CSVs contain the **legacy `user_id` values** (UUIDs that pointed at `auth.users.id` in the
legacy project). The runner will move them into the additive `legacy_user_id` audit column.

**Founder stores the four CSVs in a local directory of their choice, e.g. `~/fc_wave4_csvs/`.**

### §A.2 — Old→new mapping CSV

After Dashboard user creation (§B), Founder produces `mapping.csv` with this schema:

```
legacy_user_id,new_user_id,re_onboard_status
<legacy uuid>,<new uuid>,CREATED|INVITED|...
...
```

The mapping CSV is the authoritative source for applying the new `target user_id` from the
recorded `legacy_user_id`. **It is Founder-local only.**

### §A.3 — Confirm the three env-vars exist

```
echo "$FC_CSV_DIR"        # directory holding the four application-data CSVs
echo "$FC_MAPPING_CSV"    # absolute path to mapping.csv
echo "$NEW_DB_URL"        # DSN of the target project
```

These three env-vars are the only inputs the Founder runner consumes. The runner refuses to
start if any is unset (`: "${FOO:?...}"` shell-style guard).

---

## §B — Dashboard user creation (Option C1 only)

Per Lux `39ca1a0` §5, every new `auth.users.id` is created via the Dashboard:

1. Dashboard → Authentication → Users → **Add user** → **Create new user** with auto-confirm.
2. Record `(legacy_user_id, new_user_id, "CREATED")` into `mapping.csv` immediately.
3. Repeat for every legacy user (customer, partner, driver).

**Hard rule:** the mapping CSV must cover every distinct legacy `user_id` seen in §A.1 CSVs.
The runner's mapping-apply preflight (§D.2 B.2) refuses to start if the mapping is incomplete
or if any `new_user_id` does not exist in `auth.users`.

---

## §C — Run the Founder runner (PHASE 1 → PHASE 2 → PHASE 3)

```bash
cd /home/prime/fleetconnect-integration-r056

NEW_DB_URL="$NEW_DB_URL" \
FC_CSV_DIR="$FC_CSV_DIR" \
FC_MAPPING_CSV="$FC_MAPPING_CSV" \
  supabase/operations/phase_g_l_wave4/runner/run_wave4.sh import-and-apply
```

The runner performs three deterministic phases, each inside its own `psql` invocation with
`ON_ERROR_STOP=1`. Any failure aborts cleanly:

| Phase | Action | Invariants checked |
|---|---|---|
| **PHASE 1** | Load CSVs into `staging.*`, transform with preflight, INSERT into canonical tables with `user_id=NULL` and `legacy_user_id=<legacy uuid>` | A.1 (CSV column counts match staging schema), A.2 (no duplicate partner email), A.3 (all `drivers.partner_legacy_pk` resolvable), A.4 (all `bookings.driver_legacy_uuid` resolvable), V1 (row counts = expected), V3 (zero auth-FK orphans), V-pre-mapping |
| **PHASE 2** | Load `mapping.csv` into temp `user_id_mapping`, apply deterministic UPDATEs to set target `user_id` | B.1 (all mapping rows reference real `auth.users.id`), B.2 (every distinct legacy `user_id` in canonical tables is mapped), B.3 (no row has `legacy_user_id = user_id` after apply — i.e., cross-project UUID portability is NOT assumed), V2, V4, V5 |
| **PHASE 3** | `DROP SCHEMA staging CASCADE` | None |

On success the runner prints:

```
================================================================
Phase G-L Wave 4 Founder runner: ALL PHASES OK
================================================================
```

On any preflight failure the runner aborts with an `ERROR: Phase G-L ...` message naming the
specific preflight that failed and the offending rows. **The transaction is rolled back inside
the failing `psql` invocation; subsequent phases never execute.**

---

## §D — Verification (Founder or PRIME via read-only SQL)

After the runner prints `ALL PHASES OK`, Founder (or PRIME via the anon key against the target
project) runs the verification queries in
`supabase/operations/phase_g_l_wave4/sql/phase_g_l_verification_queries.sql`.

Expected results:

- V0: every row in `customers/partners/drivers/onderaannemers/bookings` has `legacy_user_id uuid`
- V1: row counts match legacy export
- V2: zero rows have `legacy_user_id = user_id`
- V3: zero auth-FK orphans
- V4: zero business-FK orphans
- V5: zero unmapped legacy users (i.e., every distinct `legacy_user_id` resolves via `mapping.csv`)

If any check fails, see `rollback.md` §B.

---

## §E — Wave 5 unblock

Per `CURRENT_MISSION.md` §Execution Gates, Wave 5 (application cutover) unblocks after:

1. Wave 4 completes and verification V0-V5 all pass.
2. Target runtime/security regression runs green.
3. Phase F real mailbox proof is delivered.
4. B3 lifecycle evidence is delivered.
5. PRIME review + Lux review + Founder hands-on acceptance of Wave 4 outputs.

---

## §F — Guardrails

- **No credentials in chat/Telegram/Bridge/repo/evidence.** `$NEW_DB_URL` is Founder-only.
- **No assumption PRIME holds `$NEW_DB_URL`.** PRIME supplies non-secret scripts + verifies
  outputs read-only via the anon key.
- **Option C2 REMOVED.** No `INSERT INTO auth.users` or `auth.identities` via SQL Editor.
- **Dashboard-only user creation.** Per Lux `39ca1a0` §5.
- **Deterministic mapping.** Every distinct `legacy_user_id` in CSVs must map to exactly one
  `new_user_id` that exists in `auth.users` at PHASE 2 time. No best-effort mapping.
- **Single transaction per phase.** Each phase's `psql` invocation begins, runs, commits or
  rolls back, and exits. No psql session is reused across phases (the original BLOCKER #2).
- **`legacy_user_id` retained until Founder acceptance.** Drop only after Founder approves the
  Wave-4 outputs in §D. Per Lux `2675123` §5: "Do NOT drop `legacy_user_id` until after Founder
  acceptance; retain as audit/rollback evidence."
