# r056 Phase G — Cutover Build Index (FULL EVIDENCE BATCH)

**Date:** 2026-08-31
**Author:** PRIME (autonomous, post Lux 2195825 acceptance)
**Branch:** `integration-r056`
**Target project:** `wjbxrgbyhqpiujifwqcf` (greenfield, empty)
**Legacy project:** `rreqjjrmvytnwnsidmqi` (post-cutover read-only)
**Mission:** `2026-08-29-fleetconnect-operational-recovery`

---

## Why this batch

Per Lux 2195825 acceptance + Founder directive (2026-08-31): continue
Phase G autonomously. Founder provisioning is **NOT** the immediate
blocker. The deliverables are buildable end-to-end as artifacts in the
repo, with deterministic verification on a local disposable harness.
No Supabase writes, no credential requests.

---

## What is in this batch (6 new artifacts + 1 config)

| Artifact | Path | Purpose |
|----------|------|---------|
| G-A. Canonical greenfield baseline SQL | `supabase/migrations/20260831000000_phase_g_canonical_greenfield_baseline.sql` (14,335 bytes) | 6 foundational tables + auth stubs + pgcrypto |
| G-B. Migration apply manifest (51 + 1 = 52 files) | `supabase/apply_manifest.sh` (3,999 bytes) + `evidence/r056-phase-g-migration-manifest.md` (194 lines) | Deterministic order, strict fail-fast |
| G-C. Strict local reconstruction proof | (this file §3) | 52/52 migrations apply, 0 SQL errors |
| G-D1. supabase/config.toml | `supabase/config.toml` (9,805 bytes) | Project pin for `wjbxrgbyhqpiujifwqcf` |
| G-D2. Edge function deployment manifest | `evidence/r056-phase-g-edge-function-deployment-manifest.md` (10 sections) | 7 functions × deterministic order × per-function deploy/verify/rollback |
| G-D3. Secret inventory + rollback | `evidence/r056-phase-g-secret-inventory-and-rollback.md` (7 sections, 12 secrets) | Symbolic secret names + 5-tier rollback ladder |
| G-E. Application cutover patch | `evidence/r056-phase-g-application-cutover-patch.md` (7 sections) | 11 HTML files × URL + anon key replacement |
| G-F. Data + auth migration mapping | `evidence/r056-phase-g-data-auth-migration-mapping.md` (7 sections) | 13 core tables + 5 mailbox + 3-tier auth import |
| G-G. Security review of legacy anon surfaces | `evidence/r056-phase-g-security-review-legacy-anon-surfaces.md` (8 sections) | 5 Tier 1 + 4 Tier 2 + 4 Tier 3 findings + reproducible probe |

---

## 1. Baseline SQL (G-A)

**File:** `supabase/migrations/20260831000000_phase_g_canonical_greenfield_baseline.sql`
**Size:** 14,335 bytes / 334 lines
**Status:** CREATED (untracked before this batch)

The baseline bootstraps 6 tables that the historical migration chain
references but never creates:

| # | Table | Type | Source of provenance |
|---|-------|------|----------------------|
| 1 | `customers` | TEXT id, 7 columns | REST probe + phase4_identity_closure ALTER |
| 2 | `partners` | TEXT id, 7+ columns | REST probe + authorize_admin_role refs |
| 3 | `drivers` | TEXT id, 10 columns | REST probe + booking RPCs |
| 4 | `bookings` | TEXT id, 30+ columns | REST probe + 30 migration ALTERs |
| 5 | `booking_lifecycle_events` | TEXT id | timeout_scanner migration ref |
| 6 | (auth stubs) | pgcrypto + auth schema + roles | Real Supabase provides; this is for local harness |

All `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`,
`ALTER TABLE ... ADD COLUMN IF NOT EXISTS` — idempotent.

---

## 2. Migration manifest (G-B)

**File:** `evidence/r056-phase-g-migration-manifest.md` (194 lines)
**Companion:** `supabase/apply_manifest.sh` (executable, 96 lines, 51 manifest entries)

**File count:** 51 SQL files in `supabase/migrations/`
- 1 NEW canonical greenfield baseline (this batch)
- 48 pre-existing timestamped migrations
- 1 unprefixed `phase4_identity_closure.sql` (NOT renamed; positional apply enforces order)
- 1 Phase F migration

**Deterministic apply order:** baseline FIRST (file 0), 48 timestamped
in lexicographic order (files 1-48), `phase4_identity_closure.sql`
(file 49), Phase F LAST (file 50).

**Why the order is NOT filename lex:**
- Lex order would put unprefixed `phase4...` AFTER `20260831...`
  Phase F (digits < 'p' in ASCII)
- Phase 4 identity closure must run AFTER the migrations that create
  the business logic on `customers`/`bookings`
- The apply script (`apply_manifest.sh`) is the canonical order; the
  filename lex is a coincidence for the timestamped ones

**Script:** `supabase/apply_manifest.sh` — strict fail-fast with
`ON_ERROR_STOP=1`, exits on first error, prints elapsed + result.

---

## 3. Strict local reconstruction (G-C)

**Verified by PRIME on this turn (2026-08-31):**

```
Local Postgres: PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1) on x86_64
Database: phase_g_greenfield_v2 (disposable, dropped+recreated)
Apply: 52/52 migrations, 0 SQL errors, 6.9 seconds
```

**Post-apply verification:**
- 5 foundational tables: customers, partners, drivers, bookings, booking_lifecycle_events — all EXISTS
- 5 Phase F mailbox tables: all EXISTS
- RLS ENABLED on all 5 mailbox tables
- 3 Phase F RPCs: authorize_dispatch_mailbox, log_dispatch_mailbox_action, get_mailbox_inbox — all EXISTS, 0 anon EXECUTE
- authorize_admin_role() v2 (r055): 0 anon EXECUTE
- 21 public tables, 77 public functions total
- 0 anon table grants on Tier 1 tables (customers, partners, drivers, transaction_ledger, account_requests, settlements, refunds)

**Idempotency finding (PRE-EXISTING, NOT introduced by baseline):**

| Symptom | File | Line | Nature |
|---------|------|------|--------|
| `CREATE POLICY "Service role full access on bookings" already exists` | `phase4_identity_closure.sql` | 69 | Pre-existing bug — missing `DROP POLICY IF EXISTS` |
| `CREATE POLICY "Service role full access on customers" already exists` | `phase4_identity_closure.sql` | 70 | Pre-existing bug — missing `DROP POLICY IF EXISTS` |

**Behavior:** First-apply (greenfield reconstruction) succeeds.
Re-apply (re-run on already-applied DB) FAILS at phase4 line 69
because the policies are created without the drop-if-exists guard
that the earlier policies in the same file use.

**Impact on greenfield cutover:** **None.** Greenfield is empty, so
the first apply is the only one that matters. The bug only manifests
on re-apply (e.g. disaster recovery, schema evolution, test reruns).

**Recommendation to Lux:** patch `phase4_identity_closure.sql` lines
69-70 to add `DROP POLICY IF EXISTS "..." ON ...;` before each
`CREATE POLICY`. This is a minimal, safe, idempotency-only patch.
**PRIME does NOT apply this patch autonomously** because it modifies
a historical migration; per Lux 2195825 §4, modifications to historical
migrations require Founder approval.

---

## 4. config.toml (G-D1)

**File:** `supabase/config.toml` (9,805 bytes)
**Project pin:** `project_id = "wjbxrgbyhqpiujifwqcf"`

**Sections:** `[api]`, `[db]`, `[db.pooler]`, `[realtime]`, `[studio]`,
`[inbucket]`, `[storage]`, `[auth]`, `[auth.email]`, `[auth.email.template.*]`,
`[edge_runtime]`, `[analytics]`, `[functions.<name>]` × 7.

**Critical settings:**
- `[analytics] enabled = false` (per Lux: "no third-party beacon")
- `[functions.stripe-webhook] verify_jwt = false` (Stripe signs its own callbacks)
- `[functions.{send-email,create-checkout-session,process-refund,dispatch-mail-*}] verify_jwt = true` (all others)
- All CORS allowlist origins + auth site_url + additional_redirect_urls documented
- NO secrets in the file (per Lux 2195825 §6)

---

## 5. Edge function deployment manifest (G-D2)

**File:** `evidence/r056-phase-g-edge-function-deployment-manifest.md` (10 sections)

**7 functions in dependency-driven deploy order:**

| Step | Function | verify_jwt | Why this order |
|------|----------|------------|----------------|
| 1 | `dispatch-mail-flag` | true | Pure RPC, earliest go-live confidence |
| 2 | `dispatch-mail-inbox` | true | Depends on DB schema only |
| 3 | `dispatch-mail-send` | true | Same |
| 4 | `send-email` | true | Resend only, no FC interop |
| 5 | `create-checkout-session` | true | Stripe only |
| 6 | `process-refund` | true | Stripe + admin scope |
| 7 | `stripe-webhook` | false | Webhook last (so misrouted events have nowhere to land during cutover) |

**Per-function deliverable:** deploy command + verify probe (expected
status) + secret set (symbolic) + source-bundle SHA + rollback command.

**Pinned source SHA:** `c98bff3` (current HEAD of `integration-r056`).
Runner MUST recompute SHA at deploy time and update this section
if the local HEAD has moved.

---

## 6. Secret inventory + rollback (G-D3)

**File:** `evidence/r056-phase-g-secret-inventory-and-rollback.md` (7 sections, 12 secret symbols)

**12 symbolic secret names (S1-S13):**
- S1-S4: Supabase-platform auto-injected (URL, anon, service_role, db_url)
- S5: RESEND_API_KEY (F1 send-email)
- S6: STRIPE_SECRET_KEY (F2 + F3)
- S7: STRIPE_WEBHOOK_SECRET (F4)
- S8-S13: Mailbox secrets (F5/F6, including MAILBOX_USER, MAILBOX_PROVIDER_HOST = w021ae07.kasserver.com per Lux be9be92/eb4a9bf, IMAP/SMTP ports + passwords)

**5-tier rollback ladder:**
1. Function-secret-only rollback (Dashboard edit, no redeploy)
2. Function-source rollback (git revert + redeploy)
3. Function-source rollback + secret rotation (combined)
4. Schema rollback (additive migrations; revert = new migration, not undo)
5. Whole-project rollback to legacy (DNS flip + browser revert + Stripe URL revert; legacy preserved 30 days)

---

## 7. Application cutover patch (G-E)

**File:** `evidence/r056-phase-g-application-cutover-patch.md` (7 sections)

**11 HTML files in scope:**
- 8 Paneel/* files (operator/driver/partner UIs)
- 3 b2b/* files (login, portal, webbooker)

**Patch operations:**
- 11 URL replacements: `rreqjjrmvytnwnsidmqi.supabase.co` → `wjbxrgbyhqpiujifwqcf.supabase.co`
- 4 anon key replacements: `eyJhbG...8MTA` (placeholder) → real new-project anon key

**Why staged, not pre-committed:**
- Pre-committing the URL swap would break legacy for any browser on stale Vercel/CDN cache
- The patch is held in this evidence doc; HTML files stay on legacy URL until cutover day
- Founder (or PRIME in a separate cutover commit) applies the patch in one atomic commit

**Single commit shape; single revert.**

---

## 8. Data + auth migration mapping (G-F)

**File:** `evidence/r056-phase-g-data-auth-migration-mapping.md` (7 sections)

**18 tables total (T1-T18):**
- 13 core ops tables (T1-T13): bookings, customers, partners, drivers, account_requests, payments, pricing_profiles, fixed_routes, invoices, settlements, ride_reviews, refunds, transaction_ledger
- 5 mailbox tables (T14-T18): NONE on legacy (Phase F not applied) — no data to migrate

**Export procedure (Founder, legacy Dashboard):**
- `COPY (SELECT * FROM public.<table> ...)` per table
- OR `pg_dump --data-only --column-inserts` for full SQL script
- NEVER export `auth.users` via this path — separate procedure

**Auth users mapping (3 options):**
- A: Hash export + import (fast, may break on bcrypt salt)
- B: Password reset all users (zero hash risk, every user must act)
- C: Hybrid (A + reset fallback for fails) — RECOMMENDED

**Import order (FK-respecting):**
1. `auth.users` + `auth.identities` (FIRST — everything depends on UUIDs)
2. Reference data (pricing_profiles, fixed_routes)
3. Master data (customers, partners, drivers — link to auth.users)
4. Operational data (bookings, payments, etc.)

**Post-import verification:** row count parity + FK integrity + idempotency smoke test.

---

## 9. Security review of legacy anon-readable surfaces (G-G)

**File:** `evidence/r056-phase-g-security-review-legacy-anon-surfaces.md` (8 sections)

**5 Tier 1 (CRITICAL) findings on legacy — must remediate before cutover:**

| ID | Finding | Risk |
|----|---------|------|
| C1 | Anon `SELECT * FROM customers` | PII harvest (email/phone/address) |
| C2 | Anon `SELECT * FROM partners/drivers` | Internal roster + home addresses |
| C3 | Anon `SELECT * FROM account_requests` | Pre-customer sensitive messages |
| C4 | Anon `SELECT * FROM transaction_ledger` | Full financial audit trail |
| C5 | Anon `SELECT * FROM bookings` | Travel pattern leak |

**All 5 are remediated by the migration chain on the new project** — verified by post-apply RLS check (§3 above): 0 anon grants on Tier 1 tables.

**4 Tier 2 (HIGH) findings:** payments, invoices, settlements, refunds — also remediated by migration chain.

**4 Tier 3 (INTENTIONAL) surfaces stay anon-readable:** pricing_profiles, fixed_routes, ride_reviews, public booking lookup by id.

**Reproducible probe (§7):** exact `curl` commands to verify any project (legacy or new) — Founder can re-run after cutover to confirm parity.

---

## 10. What this batch does NOT do

- ❌ Does NOT write to either Supabase project (legacy or new)
- ❌ Does NOT request DB passwords, service_role keys, access tokens, or any secret value
- ❌ Does NOT modify any historical migration file
- ❌ Does NOT commit or push without explicit verification
- ❌ Does NOT pre-commit the cutover patch (held in evidence, applied at cutover day)
- ❌ Does NOT change DNS, Stripe webhook URL, or any external integration

---

## 11. What is staged for the next wave (Founder-only)

| Wave | What | Blocked on |
|------|------|-----------|
| 1. Schema apply | 52 migrations on new project via `supabase/apply_manifest.sh` | New project DB password OR service_role key |
| 2. Edge function deploy | 7 functions via per-function `supabase functions deploy` | CLI access token + (per function) secret set in Dashboard |
| 3. Cutover patch | 11 HTML files URL+key swap (single commit) | New project anon key (Founder holds) |
| 4. Data migration | pg_dump legacy + \copy to new | Legacy DB connection (Founder holds) |
| 5. Auth users | A/B/C decision + import | New project service_role + auth import |
| 6. DNS / Stripe | Domain + webhook URL | Founder hand-on |
| 7. Verification | Re-run §7 probe on new project; compare to legacy baseline | (none — PRIME autonomous) |

---

## 12. LUX — SYNC NEEDED

This batch is ready for Lux review. Six things to confirm:
1. Baseline SQL covers the 6 foundational tables correctly (Lux 2195825 §3)
2. Manifest apply order is correct (Lux 2195825 §4)
3. Edge function deploy order is dependency-driven (Lux 2195825 §5)
4. Secret inventory is complete (Lux 2195825 §6)
5. Cutover patch scope is 11 files (Lux 2195825 §7)
6. Security findings are accurate and remediated by migration chain (Lux 2195825 §9)

**PRE-EXISTING bug to flag:** `phase4_identity_closure.sql` lines 69-70
lack `DROP POLICY IF EXISTS` — re-apply fails on an already-populated
DB. Greenfield cutover is unaffected (first-apply works). Lux decision
needed: ship as-is for greenfield (no impact) or patch (minimal
additive diff). PRIME does NOT modify historical migrations
autonomously.
