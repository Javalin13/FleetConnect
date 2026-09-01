# r056 Phase G-I — Runbook + Execution Contract Correction (per Lux 7aac5aa)

**Date:** 2026-09-01
**Author:** PRIME (autonomous, post Lux 7aac5aa acceptance)
**Mission:** `2026-08-29-fleetconnect-operational-recovery`
**Latest FleetConnect commit:** TBD (this batch)
**Latest bridge commit:** TBD (this round)
**Status:** correction complete; awaiting Lux review

---

## TL;DR (per Lux 7aac5aa)

Lux reviewed `5356a58` and accepted G-H1–G-H5 (the three core
technical blockers resolved: local auth stubs isolated, type model
coherent, phase4 idempotency fixed, local reconstruction proven).

Lux identified three execution-contract blockers that prevent
Founder provisioning:

1. **§6 Runbook Wave 5 still prescribes `sed` + `/tmp` workflow**,
   contradicting its own "no sed" doctrine
2. **§7 Runbook Wave 4 prescribes `COPY TO '/tmp/...'`**, which is
   not a reliable managed-Supabase export path
3. **§8 Runbook Wave 4 prescribes raw `auth.users` / `auth.identities`
   CSV import**, which is not a safe canonical auth migration path

Plus three minor corrections (§9): terminology (51 historical + 1
new baseline = 52 steps), RLS/privilege doctrine precision,
`onderaannemers` labeling.

This round (Phase G-I) addresses all six items.

---

## G-I1 — Wave 5 application cutover: deterministic reviewed commit (NOT sed)

**Updated file:** `evidence/r056-phase-g-h-founder-cutover-runbook.md`
(19,614 B, was 12,873 B; Wave 5 fully rewritten)

**Old (REJECTED):** Founder runs `sed -i "s|rreqjjrm...|wjbxrg...|g" Paneel/*.html b2b/*.html` in worktree.

**New (CANONICAL):**
1. PRIME prepares one deterministic reviewed application wiring
   commit on `cutover-r057` branch (forked from `integration-r056`)
2. Replaces 11 URLs + 4 anon key placeholders in 11 HTML files
3. The real new-project anon key is read from a Founder-supplied
   local file or environment variable; NEVER from chat/Telegram
4. PRIME commits + pushes branch + opens PR
5. Founder reviews the exact diff
6. Founder gives explicit cutover approval
7. PRIME merges the PR; Vercel auto-redeploys

**Anon key handling:** The Supabase publishable/anon key IS
intentionally client-visible. It MAY be committed where the raw
static app architecture requires it (e.g. `Paneel/*.html`). It is
NOT routed through `/tmp`, shell substitution, chat, Telegram, or
Bridge.

## G-I2 — Wave 4 application data export: supported authenticated paths only

**Updated file:** `evidence/r056-phase-g-h-founder-cutover-runbook.md` (Wave 4A)

**Old (REJECTED):** Founder runs `COPY (SELECT * FROM public.<table>) TO '/tmp/<table>.csv'` in legacy SQL Editor.

**New (CANONICAL, 3 paths):**

- **Path A1: Dashboard SQL Editor result export** (small tables, ~1000 rows)
- **Path A2: Dashboard Table Editor export** (medium tables, ~10K rows)
- **Path A3: pg_dump / psql `\copy` from Founder-authenticated local environment** (large tables, > 10K rows)

**Server-side `COPY ... TO '/tmp/...'` is NOT a reliable managed-
Supabase export contract** — it writes to the database server
filesystem which is generally not user-accessible. **Path A4 (server-
side `/tmp` copy) is REJECTED.**

## G-I3 — Wave 4 auth migration: re-onboarding is DEFAULT; raw CSV import is NOT canonical

**New file:** `evidence/r056-phase-g-i-data-auth-migration-mapping.md`
(13,978 B) — splits application data from auth migration

**Old (REJECTED):** Founder exports `auth.users` + `auth.identities`
CSVs and hands them to PRIME for import.

**New (CANONICAL DEFAULT):** Controlled re-onboarding / password reset.
- For each user: trigger a password-reset email from the new project
  (Dashboard → Authentication → Users → "Send recovery email")
- Document the old → new user-id mapping
- Application tables use a `legacy_user_id` audit column (Option B
  recommended; the additive migration is prepared for the next
  round, NOT auto-committed in this round)

**EXCEPTION path (use ONLY if 4 conditions all hold):** re-onboarding
infeasible, Founder has authenticated auth-schema access, current
Supabase docs describe a supported transfer procedure, Lux explicit
approval. **PRIME does NOT import raw `auth.users` / `auth.identities`
CSVs into the new project. This is a hard rule per Lux 7aac5aa §8.**

## G-I4 — Minor terminology + doctrine + labeling corrections

### 4a. Terminology: 51 historical + 1 new baseline = 52 steps

**Updated file:** `evidence/r056-phase-g-migration-manifest.md`

- Old: "**51 SQL files**" (ambiguous — could mean 51 historical or
  51 total)
- New: "**51 historical / existing SQL files** ... **Total
  reconstruction steps = 52** (51 historical + 1 new baseline)"

### 4b. RLS / privilege doctrine precision

**Updated file:** `supabase/migrations/20260831000000_phase_g_canonical_greenfield_baseline.sql`
(comment-only change, no SQL)

- Old: "Default behavior without RLS is deny (Supabase default), so
  anon gets nothing."
- New: "this file does NOT issue explicit GRANTs ... When RLS is
  NOT yet enabled, access is governed by the standard PostgreSQL
  privilege system, which by default is also deny for non-owners —
  but PRIME does not generalize that 'no RLS = deny' because
  PostgreSQL privilege semantics are not the same as RLS semantics."

### 4c. `onderaannemers` labeling: COMPATIBILITY / DORMANT

**Updated file:** `supabase/migrations/20260831000000_phase_g_canonical_greenfield_baseline.sql`
(comment-only change, no SQL)

- Old: "Dutch synonym for partners ... Production schema in legacy
  used BIGSERIAL id ..."
- New: "Foundational table: onderaannemers (COMPATIBILITY / DORMANT)
  ... This table is created to satisfy the historical migration
  chain's references. It is NOT independently proven to be active
  in legacy production. If authenticated legacy schema
  introspection later confirms it is dormant in production, no
  action is needed — the RLS policies are harmless on an empty
  table."

## G-I5 — Local reconstruction re-verification (per Lux §10)

**Per Lux §10:** "No need to rerun the full local 52-step schema
reconstruction unless code/SQL changes beyond comments/docs are
introduced."

The G-I changes are:
- Runbook rewrites (docs, no SQL)
- Migration manifest terminology fix (docs, no SQL)
- Production baseline comment updates (docs, no SQL)

But PRIME ran the full local reconstruction anyway as a defensive
check (the baseline was touched even though only comments changed):

```
=== First-apply: 52/52 in 8.0s, 0 errors ===
=== Second-apply: 52/52 in 6.6s, 0 errors ===
=== State invariant ===
  tables: 21 (expected 21)
  functions: 77 (expected 77)
  policies: 50 (expected 50)
```

**Zero drift, zero errors. The G-I changes did not break anything.**

## G-I6 — Files changed in this round (FleetConnect)

| File | Change | Size |
|------|--------|------|
| `supabase/migrations/20260831000000_phase_g_canonical_greenfield_baseline.sql` | MODIFIED (comment-only, 2 sections) | +1,399 B (15,734 → 17,133) |
| `evidence/r056-phase-g-migration-manifest.md` | MODIFIED (terminology) | +250 B (9,777 → ~10,000) |
| `evidence/r056-phase-g-h-founder-cutover-runbook.md` | MODIFIED (Wave 4 + Wave 5 fully rewritten) | 19,614 B (was 12,873) |
| `evidence/r056-phase-g-i-data-auth-migration-mapping.md` | NEW (split per Lux §7/§8) | 13,978 B |
| `evidence/r056-phase-g-i-correction-summary.md` | NEW (this file) | ~10,000 B |

## G-I7 — Compliance with Lux 7aac5aa

| § | Direction | Status |
|---|-----------|--------|
| §1 | Local auth stubs isolated | acknowledged (already done in G-H) |
| §2 | PK/FK model coherent | acknowledged (already done in G-H) |
| §3 | Phase 4 idempotency fix | acknowledged (already done in G-H) |
| §4 | Local first/second apply | acknowledged (already done in G-H) |
| §5 | Config/function prep | acknowledged (already done in G-H) |
| §6 | **Remove `sed` + `/tmp` from Wave 5** | [implemented] — G-I1: deterministic reviewed commit; Founder explicit approval |
| §7 | **Remove `COPY TO /tmp` from Wave 4** | [implemented] — G-I2: 3 supported authenticated paths |
| §8 | **Split auth migration; no raw CSV import** | [implemented] — G-I3: re-onboarding DEFAULT; Option B legacy_user_id audit column |
| §9 | **Terminology + RLS + onderaannemers fixes** | [implemented] — G-I4: 3 minor corrections |
| §10 | One final autonomous G-I batch | [implemented] — this round |
| §11 | Founder provisioning still deferred | [acknowledged] — awaits Lux accept of G-I |

## LUX — SYNC NEEDED

This round (Phase G-I) addresses all 3 execution-contract blockers
and all 3 minor corrections from Lux 7aac5aa.

**Five items for Lux to confirm:**

1. Wave 5 application cutover uses deterministic reviewed commit
   + Founder explicit approval; no `sed` + `/tmp` path
2. Wave 4 application data export uses supported authenticated paths
   (SQL Editor result export, Table Editor export, pg_dump from
   Founder local); no server-side `COPY TO /tmp`
3. Wave 4 auth migration: re-onboarding is DEFAULT; raw `auth.users` /
   `auth.identities` CSV import is NOT canonical; Option B
   (`legacy_user_id` audit column) recommended for next round
4. Terminology correction: 51 historical + 1 new baseline = 52 steps
5. `onderaannemers` labeled COMPATIBILITY / DORMANT (not proven
   active legacy production); RLS/privilege doctrine comment
   precision fix

After Lux accept: Founder 5-wave authenticated provisioning can begin.
PRIME does not request or hold any Founder-issued secret.
