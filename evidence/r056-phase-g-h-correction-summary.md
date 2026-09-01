# r056 Phase G-H — Production-Safe Baseline Correction (per Lux d3a5d92)

**Date:** 2026-09-01
**Author:** PRIME (autonomous, post Lux d3a5d92 acceptance)
**Mission:** `2026-08-29-fleetconnect-operational-recovery`
**Latest FleetConnect commit:** TBD (this batch)
**Latest bridge commit:** TBD (this round)
**Status:** build complete; awaiting Lux review

---

## TL;DR (per Lux d3a5d92)

Lux reviewed `cc10c8f` and accepted the material progress, but
identified **three blockers** that prevented target provisioning:

1. **Production baseline contained local-harness auth stubs** that
   would have replaced Supabase-managed `auth.uid/jwt/role` and
   silently created the standard roles
2. **Foundational ID/type doctrine was internally contradictory** —
   comments said "ALL TEXT" but the executable schema uses BIGSERIAL
   for partners.id and UUID for drivers.id
3. **`phase4_identity_closure.sql` service-role policy creation was
   not idempotent** — re-apply to a populated DB failed

This round (Phase G-H) addresses all three blockers and re-verifies
the greenfield reconstruction with documented second-apply checks.

---

## G-H1 — Local Supabase auth stubs separated from production

**New file:** `supabase/local_harness/00_local_auth_stubs.sql` (3,517 B)

Contains ONLY the test-only objects:
- `auth.users` (minimal stub table)
- `auth.uid()` / `auth.jwt()` / `auth.role()` (stub functions)
- `anon` / `authenticated` / `service_role` roles

Header comment explicitly says:
> CRITICAL: DO NOT INCLUDE IN PRODUCTION APPLY

## G-H2 — Production baseline made Supabase-safe

**Updated file:** `supabase/migrations/20260831000000_phase_g_canonical_greenfield_baseline.sql` (15,734 B, was 14,335 B)

**Removed from production baseline:**
- `CREATE SCHEMA IF NOT EXISTS auth` (Supabase platform)
- `DO $$ ... CREATE ROLE anon/authenticated/service_role $$` (Supabase platform)
- `CREATE TABLE IF NOT EXISTS auth.users` (Supabase platform)
- `CREATE OR REPLACE FUNCTION auth.uid()` (Supabase platform helper)
- `CREATE OR REPLACE FUNCTION auth.jwt()` (Supabase platform helper)
- `CREATE OR REPLACE FUNCTION auth.role()` (Supabase platform helper)
- `CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions`
  (kept; safe IF NOT EXISTS, Supabase already has pgcrypto)

**Kept in production baseline:**
- `CREATE SCHEMA IF NOT EXISTS extensions` (safe; Supabase has this)
- `CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions` (safe)
- All 6 foundational tables (customers, partners, drivers, onderaannemers, bookings, booking_lifecycle_events)
- All indexes
- All REFERENCES to `auth.users(id)` (satisfied by Supabase platform)

**Verification:** the production baseline now has zero references to
`CREATE SCHEMA auth`, `CREATE ROLE`, `CREATE TABLE auth.users`, or
`CREATE OR REPLACE FUNCTION auth.*`. The only Supabase-managed
dependency it has is `REFERENCES auth.users(id)` which is read-only.

## G-H3 — Foundational PK/FK type doctrine proven + comments aligned

**Reconciliation result:** the comments were wrong. The executable
schema is correct. The provenance docs were updated to match the
schema exactly.

| Table | PK type | Provenance |
|-------|---------|------------|
| `customers.id` | TEXT | "CUST-2024-001" pattern; e.g. baseline + phase4_identity_closure + 18 migrations |
| `partners.id` | **BIGSERIAL** | BIGSERIAL PK; BIGINT in all FKs (bookings.partner_id, drivers.partner_id) |
| `drivers.id` | **UUID** | UUID PK; UUID in all FKs (bookings.assigned_driver_id, lifecycle events driver_id) |
| `bookings.id` | TEXT | "BK-2024-001234" pattern; e.g. baseline + 30 migrations |
| `onderaannemers.id` | BIGSERIAL | BIGSERIAL; synonym for partners |
| `booking_lifecycle_events.id` | TEXT | TEXT (gen_random_uuid()::text); matches bookings.id type |

**FK column types (verified across migrations):**

| FK column | Type | References |
|-----------|------|-----------|
| `customers.user_id` | UUID | `auth.users(id)` |
| `partners.user_id` | UUID | `auth.users(id)` |
| `partners.primary_dispatch_driver_id` | UUID | `drivers(id)` (was incorrectly TEXT in old comments) |
| `drivers.user_id` | UUID | `auth.users(id)` |
| `drivers.partner_id` | BIGINT | `partners(id)` |
| `onderaannemers.user_id` | UUID | `auth.users(id)` |
| `onderaannemers.primary_dispatch_driver_id` | UUID | `drivers(id)` |
| `bookings.user_id` | UUID | `auth.users(id)` |
| `bookings.customer_id` | TEXT | `customers(id)` |
| `bookings.partner_id` | BIGINT | `partners(id)` |
| `bookings.assigned_driver_id` | UUID | `drivers(id)` |
| `booking_lifecycle_events.booking_id` | TEXT | `bookings(id)` |
| `booking_lifecycle_events.driver_id` | UUID | `drivers(id)` |
| `booking_lifecycle_events.partner_id` | BIGINT | `partners(id)` |
| `booking_lifecycle_events.previous_driver_id` | UUID | `drivers(id)` |

**Provenance verification (the comment change):**

The old comment at line 33 of the baseline said:
> customers.id, partners.id, drivers.id, bookings.id are ALL TEXT

The old comment at line 201 said:
> id is TEXT (per migration cross-reference: bookings.assigned_driver_id is set to v_driver.id which is TEXT)

**This was wrong.** The actual schema has `drivers.id UUID`, and
`bookings.assigned_driver_id UUID` — these match because the
migration `20260612040000_phase_a444_live_blocker_hardening.sql`
sets `assigned_driver_id = v_driver.id` where `v_driver` is a
`public.drivers` row. The "TEXT" claim was an error in PRIME's
provenance work, not a defect in the schema.

The new header comment (lines 50-72 of the rewritten baseline)
documents the actual type mix with full FK type matching.

## G-H4 — Phase 4 identity closure idempotency fix (authorized)

**Updated file:** `supabase/migrations/phase4_identity_closure.sql`
**Change:** added `DROP POLICY IF EXISTS` before the two service-role
policies on lines 69-70.

```sql
-- Before (non-idempotent):
CREATE POLICY "Service role full access on bookings" ON bookings FOR ALL TO service_role USING (true);
CREATE POLICY "Service role full access on customers" ON customers FOR ALL TO service_role USING (true);

-- After (idempotent):
DROP POLICY IF EXISTS "Service role full access on bookings" ON bookings;
CREATE POLICY "Service role full access on bookings" ON bookings FOR ALL TO service_role USING (true);
DROP POLICY IF EXISTS "Service role full access on customers" ON customers;
CREATE POLICY "Service role full access on customers" ON customers FOR ALL TO service_role USING (true);
```

**Semantic policy unchanged** (full access for service_role). The fix
is purely structural idempotency. Authorized per Lux d3a5d92 §4 as a
"minimal additive correction".

**No other historical migration was modified.** Per Lux §4: "Do not
alter unrelated historical behavior."

## G-H5 — Strict clean reconstruction + documented second-apply checks

**Environment:** local disposable Postgres 16.15, database
`phase_g_h_v3` (dropped + recreated).

### First-apply (empty-to-current)

```
[1/52] OK: 20260831000000_phase_g_canonical_greenfield_baseline.sql
... (all 52 OK)
[52/52] OK: 20260831000001_phase_f_dispatch_mailbox.sql

=== RESULT: 52/52 applied in 6.9s, errors=0 ===
```

### Second-apply (idempotency tests, on the populated DB)

Test 1: Re-apply production-safe baseline → exit=0 (idempotent ✓)

Test 2: Re-apply `phase4_identity_closure.sql` → exit=0 (was FAILING
  before; now passes ✓)

Test 3: Re-apply ALL 52 migrations → 52/52 OK, 0 errors in 6.5s

### State invariant check (counts must match pre-second-apply)

| Metric | Pre | Post | Match |
|--------|-----|------|-------|
| Public tables | 21 | 21 | ✓ |
| Public functions | 77 | 77 | ✓ |
| Public policies | 50 | 50 | ✓ |
| RLS on 5 mailbox tables | 5/5 | 5/5 | ✓ |
| 0 anon grants on Tier 1 | 0 | 0 | ✓ |
| 0 anon EXECUTE on authorize_admin_role | 0 | 0 | ✓ |

**Zero drift, zero errors, all security invariants preserved.**

## G-H6 — config.toml validation

**Tool:** Supabase CLI v2.6.8 (installed locally; latest is v2.116.0).
The v2.6.8 CLI does not have a `config lint` subcommand; PRIME
performed structural validation using `tomllib` (Python 3.11 stdlib)
+ semantic sanity checks.

### Validation results

```
config.toml parsed successfully.
  top-level keys: [project_id, api, db, realtime, studio, inbucket,
                   storage, auth, edge_runtime, analytics, functions]
  project_id: wjbxrgbyhqpiujifwqcf
  functions: [send-email, create-checkout-session, process-refund,
              stripe-webhook, dispatch-mail-inbox, dispatch-mail-send,
              dispatch-mail-flag]
  analytics.enabled: False

=== Sanity checks ===
  ✓ project_id = wjbxrgbyhqpiujifwqcf
  ✓ no secrets in file (no sk_live_, sk_test_, RESEND_API_KEY=,
                        MAILBOX_IMAP_PASSWORD=, STRIPE_SECRET_KEY=,
                        STRIPE_WEBHOOK_SECRET=, eyJ JWT prefix)
  ✓ all 7 functions declared
  ✓ stripe-webhook verify_jwt = false (correct — Stripe signs callbacks)
  ✓ send-email verify_jwt = true
  ✓ create-checkout-session verify_jwt = true
  ✓ process-refund verify_jwt = true
  ✓ dispatch-mail-inbox verify_jwt = true
  ✓ dispatch-mail-send verify_jwt = true
  ✓ dispatch-mail-flag verify_jwt = true
  ✓ analytics.enabled = false (no third-party beacon)
  auth.site_url: https://fleetconnect.be
  additional_redirect_urls: 8 entries
  ✓ [api] port 54321 (local-only)
  ✓ [studio] enabled (local-only)
```

**PRIME recommendation:** upgrade Supabase CLI to v2.116.0 (latest) at
Wave 2 deploy time so the v2.6.8 → v2.116.0 command changes (if any)
are validated by Founder in their environment, not by PRIME.

## G-H7 — Founder cutover runbook (authenticated flows only)

**New file:** `evidence/r056-phase-g-h-founder-cutover-runbook.md`
(12,873 B, 4 sections)

Key principle (per Lux d3a5d92 §6): **Founder uses authenticated
Dashboard / CLI flows. NO `/tmp/<key>` + `sed` workflow. NO
credentials in chat / Bridge / evidence / repo / shell.**

The runbook covers all 5 waves with exact Founder-authenticated
steps (Dashboard SQL Editor, `supabase login` + `supabase link`,
Dashboard Secrets UI, Stripe Dashboard, DNS registrar UI) and
explicitly says what the runbook does NOT require (no DB password
in chat, no service_role in chat, no CLI access token in chat, no
anon key in chat).

## G-H8 — Files changed in this round (FleetConnect)

| File | Change | Size |
|------|--------|------|
| `supabase/migrations/20260831000000_phase_g_canonical_greenfield_baseline.sql` | MODIFIED (Supabase-safe, type-comments aligned) | 15,734 B |
| `supabase/migrations/phase4_identity_closure.sql` | MODIFIED (idempotency fix, 4 lines added) | +237 B |
| `supabase/apply_manifest.sh` | MODIFIED (header updated, MANIFEST unchanged) | 4,872 B |
| `supabase/local_harness/00_local_auth_stubs.sql` | NEW (test-only auth stubs) | 3,517 B |
| `supabase/local_harness/apply_with_harness.sh` | NEW (test harness apply script) | 5,707 B |
| `evidence/r056-phase-g-h-founder-cutover-runbook.md` | NEW (authenticated-flow runbook) | 12,873 B |
| `evidence/r056-phase-g-h-correction-summary.md` | NEW (this file) | ~10,000 B |

## G-H9 — Compliance with Lux d3a5d92

| § | Direction | Status |
|---|-----------|--------|
| §1 | Material progress accepted | acknowledged |
| §2 | Split local auth stubs from production baseline; make Supabase-safe | [implemented] — G-H1, G-H2 |
| §3 | Prove PK/FK types; align comments | [implemented] — G-H3 |
| §4 | Authorized minimal phase4 idempotency fix | [implemented] — G-H4 |
| §5 | Validate config.toml | [implemented] — G-H6 (CLI doesn't have `config lint` in v2.6.8; PRIME did structural + semantic validation) |
| §6 | Runbook uses authenticated Dashboard/CLI flows | [implemented] — G-H7 |
| §7 | Security finding preserved as migration acceptance requirement | [implemented] — G-G from prior round (5 Tier 1 + 4 Tier 2 + 4 Tier 3 + reproducible probe) |
| §8 | Do all of §1-§7 without Founder credentials or remote writes | [implemented] — no Supabase writes, no credential requests |
| §9 | Founder provisioning remains deferred until production-safe baseline passes | [acknowledged] — awaiting Lux review of this round |

## LUX — SYNC NEEDED

This round (Phase G-H, cc10c8f → new commit) addresses all three
Lux d3a5d92 blockers. The local-harness split is complete, the
production baseline is Supabase-safe, the type doctrine is proven
and aligned, the phase4 idempotency fix is applied, the second-apply
checks pass with zero drift, the config.toml is validated, and the
runbook uses authenticated flows only.

**Five items for Lux to confirm:**

1. Local auth stubs are properly isolated in `supabase/local_harness/`
   and the production baseline has zero auth.* CREATE/REPLACE statements
2. Foundational PK/FK type doctrine matches the executable schema
   exactly (no contradiction between comments and schema)
3. Phase 4 identity closure idempotency fix is minimal, additive,
   and does not alter the semantic policy
4. Second-apply check passes (52/52, 0 errors, no state drift)
5. Runbook uses authenticated Dashboard/CLI flows only — no sed/awk
   with /tmp keys, no credentials in chat/Bridge/evidence/repo

After Lux accept: Founder 5-wave authenticated provisioning can begin.
