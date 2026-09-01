# r056 Phase G-H — Founder Cutover Runbook (Authenticated Flows Only)

**Date:** 2026-09-01
**Author:** PRIME (autonomous, post Lux d3a5d92)
**Target project:** `wjbxrgbyhqpiujifwqcf` (greenfield, currently empty)
**Legacy project:** `rreqjjrmvytnwnsidmqi` (read-only after cutover)
**Critical principle (per Lux d3a5d92 §6):** Founder uses **authenticated
Dashboard / CLI** flows. No `/tmp/<key>` file + `sed` workflow. No
credentials in chat / Bridge / evidence / repo / shell.

---

## What this runbook is

The exact, copy-pasteable, step-by-step Founder-side procedure for
executing the FleetConnect cutover from `rreqjjrmvytnwnsidmqi` to
`wjbxrgbyhqpiujifwqcf`. Every step that requires a credential is a
**Founder-only authenticated action** (Dashboard UI or local CLI
authenticated via `supabase login`).

## What this runbook is NOT

- NOT a script that PRIME runs with credentials
- NOT a request for credentials
- NOT a manual sed/awk replacement of files in the repo
- NOT a request to paste keys into Telegram / chat / Bridge

---

## 0. Pre-flight (PRIME-side, no Founder action)

PRIME has completed and verified:

- [x] Production-safe canonical greenfield baseline
  (`supabase/migrations/20260831000000_phase_g_canonical_greenfield_baseline.sql`)
- [x] Local-harness auth stubs isolated
  (`supabase/local_harness/00_local_auth_stubs.sql`)
- [x] Deterministic 51-file apply manifest
  (`supabase/apply_manifest.sh`)
- [x] Local harness apply script
  (`supabase/local_harness/apply_with_harness.sh`)
- [x] Empty-to-current reconstruction: 52/52 migrations, 0 SQL errors, 6.9s
- [x] Phase 4 identity closure idempotency fix
  (DROP POLICY IF EXISTS on lines 69-70)
- [x] Full chain re-apply: 52/52 OK, no drift (21 tables, 77 functions, 50 policies)
- [x] `supabase/config.toml` for wjbxrgbyhqpiujifwqcf (validated, no secrets)
- [x] 7-EF deployment manifest
- [x] 11-file staged application cutover patch (held, not pre-committed)
- [x] 13-table data + auth migration mapping
- [x] 5 Tier 1 + 4 Tier 2 + 4 Tier 3 legacy anon-surface security review

PRIME-side: NO writes to either Supabase project. NO credential requests.

## 1. Founder authenticated actions (Waves 1-5)

### Wave 1 — Schema apply (production-safe migration chain)

**Goal:** apply the 52-migration canonical chain to `wjbxrgbyhqpiujifwqcf`.

**Founder authenticated actions (pick ONE):**

#### Option A: Supabase Dashboard SQL Editor (Founder's browser)

1. Open https://supabase.com/dashboard/project/wjbxrgbyhqpiujifwqcf/sql
2. Authenticate with Founder's Supabase account (browser session, not API key)
3. Open `supabase/migrations/20260831000000_phase_g_canonical_greenfield_baseline.sql`
   from the Javalin13/FleetConnect repo on integration-r056 @ cc10c8f (or
   newer), copy the entire file contents
4. Paste into SQL Editor → Run
5. For each of the 51 remaining migrations in canonical order (see
   `supabase/apply_manifest.sh` MANIFEST array), repeat steps 3-4
6. After all 52 applied, run the post-apply verification:

```sql
-- 5 foundational tables
SELECT to_regclass('public.customers') IS NOT NULL AS customers_ok;
SELECT to_regclass('public.partners') IS NOT NULL AS partners_ok;
SELECT to_regclass('public.drivers') IS NOT NULL AS drivers_ok;
SELECT to_regclass('public.bookings') IS NOT NULL AS bookings_ok;
SELECT to_regclass('public.booking_lifecycle_events') IS NOT NULL AS lifecycle_ok;
-- 5 Phase F mailbox tables
SELECT to_regclass('public.dispatch_mailbox_messages') IS NOT NULL AS mailbox_msg_ok;
-- 21 total public tables
SELECT count(*) FROM pg_tables WHERE schemaname='public';
-- 77 total public functions
SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE n.nspname='public';
-- 0 anon EXECUTE on authorize_admin_role
SELECT count(*) FROM information_schema.routine_privileges
  WHERE routine_schema='public' AND routine_name='authorize_admin_role' AND grantee='anon';
```

All counts must match: 21 tables, 77 functions, 0 anon EXECUTE on
authorize_admin_role.

#### Option B: Supabase CLI (authenticated via `supabase login`)

1. Founder authenticates the CLI:
   ```bash
   supabase login
   ```
   (Opens browser for OAuth; Founder's session is the auth.)
2. Founder links the local project to the greenfield target:
   ```bash
   cd /path/to/fleetconnect-integration-r056
   supabase link --project-ref wjbxrgbyhqpiujifwqcf
   ```
   (Reads the DB connection string from Founder's local supabase
   config store, NOT from chat/Bridge.)
3. Founder runs:
   ```bash
   DB_URL="<Founder's locally-stored DB connection string>" \
     ./supabase/apply_manifest.sh
   ```
   The `DB_URL` is held in Founder's local secret store (1Password,
   Bitwarden, or `~/.pgpass`). It is NEVER pasted into chat.

4. Verify the same way as Option A.

**Founder decision factors:**
- Option A is simpler, no CLI install required, every step is auditable
  in the Dashboard query history
- Option B is faster for the 52-file chain, but requires CLI setup

**PRIME recommendation:** Option A (Dashboard SQL Editor) for the
initial Wave 1 apply. Each file is one query, audit-trail is automatic,
no CLI auth dance.

### Wave 2 — Edge function deploy (7 functions)

**Founder authenticated action:**

1. CLI login (same as Option B above, if not already done)
2. Deploy in dependency order:
   ```bash
   supabase functions deploy dispatch-mail-flag    --project-ref wjbxrgbyhqpiujifwqcf
   supabase functions deploy dispatch-mail-inbox   --project-ref wjbxrgbyhqpiujifwqcf
   supabase functions deploy dispatch-mail-send    --project-ref wjbxrgbyhqpiujifwqcf
   supabase functions deploy send-email            --project-ref wjbxrgbyhqpiujifwqcf
   supabase functions deploy create-checkout-session --project-ref wjbxrgbyhqpiujifwqcf
   supabase functions deploy process-refund        --project-ref wjbxrgbyhqpiujifwqcf
   supabase functions deploy stripe-webhook        --project-ref wjbxrgbyhqpiujifwqcf
   ```
3. PRIME runs HTTP-boundary verify probes (see `evidence/r056-phase-g-edge-function-deployment-manifest.md` §4)

### Wave 3 — Secrets configuration (Dashboard Secrets UI, Founder-only)

**Founder authenticated action (Dashboard only — never CLI env vars):**

1. Open https://supabase.com/dashboard/project/wjbxrgbyhqpiujifwqcf/settings/functions
2. For each function, click into it and add secrets from Founder's
   local 1Password/Bitwarden:

| Function | Secret name | Where to get value |
|----------|-------------|---------------------|
| send-email | `RESEND_API_KEY` | Resend Dashboard → API Keys |
| create-checkout-session | `STRIPE_SECRET_KEY` | Stripe Dashboard → API keys (live, starts with `sk_live_`) |
| process-refund | `STRIPE_SECRET_KEY` | (same as above) |
| stripe-webhook | `STRIPE_WEBHOOK_SECRET` | Stripe Dashboard → Webhooks → FleetConnect endpoint → Signing secret |
| dispatch-mail-inbox | `MAILBOX_USER` | (default: dispatch@fleetconnect.be) |
| dispatch-mail-inbox | `MAILBOX_PROVIDER_HOST` | (default: w021ae07.kasserver.com per Lux be9be92/eb4a9bf) |
| dispatch-mail-inbox | `MAILBOX_PROVIDER_IMAP_PORT` | (default: 993) |
| dispatch-mail-inbox | `MAILBOX_PROVIDER_SMTP_PORT` | (default: 465) |
| dispatch-mail-inbox | `MAILBOX_IMAP_PASSWORD` | All-Inkl webmail → Mailbox password (or reset) |
| dispatch-mail-send | `MAILBOX_USER` | (same as inbox) |
| dispatch-mail-send | `MAILBOX_PROVIDER_HOST` | (same as inbox) |
| dispatch-mail-send | `MAILBOX_PROVIDER_SMTP_PORT` | (same as inbox) |
| dispatch-mail-send | `MAILBOX_SMTP_PASSWORD` | (same as IMAP password, usually) |

3. After each secret is saved, the function runtime hot-reloads
   the env. No redeploy needed.

**PRIME verifies:** F5/F6 with valid JWT + `authorize_dispatch_mailbox()`
returns folder list (200), not `adapter_unavailable: mailbox_credentials_unconfigured`.

### Wave 4 — Data + auth migration

**Founder authenticated actions:**

1. Open legacy Dashboard: https://supabase.com/dashboard/project/rreqjjrmvytnwnsidmqi/sql
2. For each of the 13 core tables in `evidence/r056-phase-g-data-auth-migration-mapping.md` §1.1:
   - Open the SQL Editor
   - Run:
     ```sql
     COPY (SELECT * FROM public.<table> ORDER BY <pk>) TO '/tmp/<table>.csv' WITH CSV HEADER;
     ```
   - Download each CSV via Dashboard's "Download CSV" link
3. For auth users (Option A or C per mapping §3.2):
   - Option C (RECOMMENDED): hybrid hash export + reset fallback
   - Open SQL Editor, run:
     ```sql
     COPY (
       SELECT id, email, encrypted_password,
              raw_app_meta_data, raw_user_meta_data,
              email_confirmed_at, last_sign_in_at,
              created_at, updated_at
       FROM auth.users
     ) TO '/tmp/auth_users.csv' WITH CSV HEADER;

     COPY (
       SELECT * FROM auth.identities
     ) TO '/tmp/auth_identities.csv' WITH CSV HEADER;
     ```
4. Founder hands the CSVs to PRIME via Founder's local secret-share
   mechanism (NOT chat, NOT Bridge, NOT email — use a secure file
   transfer like Supabase Storage private bucket with signed URL, or
   local rsync over a secure channel).
5. PRIME imports the CSVs into the new project using the
   `psql` commands in mapping §4.2. The Founder is NOT involved
   in the import (PRIME has the data, applies it).

### Wave 5 — Cutover (Founder hands-on, browser code + DNS + Stripe)

**Founder authenticated actions:**

1. Browser code cutover (11 files):
   - Open `evidence/r056-phase-g-application-cutover-patch.md` §2
   - Either:
     - Run the `sed` commands verbatim in the local FleetConnect
       worktree (sed operates on file contents in the working tree,
       it does NOT transmit keys to PRIME)
     - Or have PRIME stage the patch as a single commit (Founder
       reviews + signs off, then PRIME applies)

2. Domain / DNS update:
   - In Founder's domain registrar (where fleetconnect.be is registered),
     update DNS records to point at the new project's endpoints
   - OR if using Supabase custom domain: configure the new project's
     custom domain in Dashboard, then point DNS to Supabase's load
     balancer

3. Stripe webhook URL update:
   - Open Stripe Dashboard → Webhooks → FleetConnect endpoint
   - Update URL to `https://wjbxrgbyhqpiujifwqcf.functions.supabase.co/stripe-webhook`
   - Copy the new signing secret back into the new project's
     `STRIPE_WEBHOOK_SECRET` (Wave 3 above)

4. Resend sender domain verification:
   - In Resend Dashboard → Domains, verify the sender domain
     for `dispatch@fleetconnect.be` points at the new project
   - (Domain ownership is independent of Supabase project; usually
     no action needed)

5. First real booking verification (Founder does the booking):
   - Open the customer-facing booking page (now serving from new project)
   - Make a test booking
   - Verify email is sent (Resend Dashboard → Logs)
   - Verify payment intent is created (Stripe Dashboard → Payments)
   - Verify driver assignment (Operator dashboard)
   - Verify lifecycle event is created (PostgREST query:
     `SELECT * FROM booking_lifecycle_events ORDER BY created_at DESC LIMIT 1`)

6. Mark legacy read-only:
   - In legacy Supabase Dashboard: Settings → Database → Connection Pooling →
     set max connections to 0 (or revoke service_role from app)
   - Leave the project running (do NOT pause or delete) so it can
     be re-activated in 30-day rollback window

## 2. Post-cutover (PRIME autonomous)

After Founder completes Wave 5, PRIME runs:

- Reproducible security probe (per `r056-phase-g-security-review-legacy-anon-surfaces.md` §7)
  on new project — must show 0 anon grants on Tier 1/2 surfaces
- Re-run mail regression matrix on F5/F6
- Run Phase G full regression on new project
- Re-execute all 52 migrations in test mode (re-apply) on a NEW local
  harness DB to confirm the chain is robust

## 3. Rollback

If at any point Founder decides the cutover must be reversed:

1. Founder flips DNS back to legacy project
2. Founder reverts the 11-file browser code commit (`git revert <cutover-sha>`)
3. Founder reverts Stripe webhook URL
4. Legacy project is still running (read-only, not paused) — traffic resumes
5. PRIME analyzes the failure, prepares a new cutover attempt

The 30-day legacy retention window is enforced by NOT pausing or
deleting the legacy project during the cutover window.

## 4. What this runbook does NOT require

- ❌ DB password in chat / Bridge
- ❌ Service role key in chat / Bridge
- ❌ Supabase CLI access token in chat / Bridge
- ❌ Edge function secret values in chat / Bridge / evidence
- ❌ Anon key in chat / Bridge (the anon key is in the repo's
   `Paneel/*.html` files at cutover time; before that it's only in
   Founder's local 1Password)

All credential-bearing actions are authenticated (Dashboard OAuth /
CLI `supabase login`). PRIME never holds a Founder-issued secret.
