# r056 Phase G-I — Founder Cutover Runbook (Corrected Execution Contract)

**Date:** 2026-09-01
**Author:** PRIME (autonomous, post Lux 7aac5aa acceptance)
**Target project:** `wjbxrgbyhqpiujifwqcf` (greenfield, currently empty)
**Legacy project:** `rreqjjrmvytnwnsidmqi` (read-only after cutover)
**Critical principle (per Lux 7aac5aa §6/§7/§8):**
- **NO `sed` + `/tmp` workflows** for application wiring (Wave 5)
- **NO server-side `COPY TO '/tmp/...'`** for data export (Wave 4)
- **NO raw `auth.users` / `auth.identities` CSV import** as canonical auth migration (Wave 4)

---

## What this runbook is

The exact, copy-pasteable, step-by-step Founder-side procedure for
executing the FleetConnect cutover from `rreqjjrmvytnwnsidmqi` to
`wjbxrgbyhqpiujifwqcf`. Every step that requires a credential is a
**Founder-only authenticated action** (Dashboard UI or local CLI
authenticated via `supabase login`).

## What this runbook is NOT (per Lux 7aac5aa)

- ❌ NOT a script that PRIME runs with credentials
- ❌ NOT a request for credentials
- ❌ NOT a manual `sed` / `awk` / shell-substitution replacement of
  files in the repo
- ❌ NOT a server-side `COPY ... TO '/tmp/...'` export
- ❌ NOT a raw `auth.users` / `auth.identities` CSV import

## What this runbook replaces (per Lux 7aac5aa §6/§7/§8)

| Old path (REJECTED) | New path (CANONICAL) |
|---------------------|---------------------|
| Wave 5: founder runs `sed -i "s\|rreqjjrm...\nwjbxrg...\g" Paneel/*.html b2b/*.html` in worktree | Wave 5: PRIME prepares one deterministic reviewed commit on `integration-r056`; Founder reviews the diff and gives explicit cutover approval; only then is the commit promoted |
| Wave 4: founder runs `COPY (SELECT ...) TO '/tmp/<table>.csv'` in legacy SQL Editor | Wave 4: founder uses SQL Editor `SELECT ...` with Dashboard result export, or Table Editor export, or `pg_dump`/`psql \copy` from a Founder-authenticated local environment |
| Wave 4: founder exports `auth.users` + `auth.identities` CSVs and hands them to PRIME for import | Wave 4: auth migration is split from application data; default is re-onboarding/password-reset; raw auth CSV import is NOT the canonical path (see §3 below) |

---

## 0. Pre-flight (PRIME-side, no Founder action)

PRIME has completed and verified:

- [x] Production-safe canonical greenfield baseline
  (`supabase/migrations/20260831000000_phase_g_canonical_greenfield_baseline.sql`,
  15,734 B, Supabase-safe — no `auth.*` CREATE/REPLACE, no role creation)
- [x] Local-harness auth stubs isolated
  (`supabase/local_harness/00_local_auth_stubs.sql`, 3,517 B)
- [x] Deterministic 51 historical SQL files + 1 new baseline = 52-step apply
  (`supabase/apply_manifest.sh`)
- [x] Local harness apply script
  (`supabase/local_harness/apply_with_harness.sh`, 5,707 B)
- [x] Empty-to-current reconstruction: 52/52 migrations, 0 SQL errors, 6.9s
- [x] Second-apply check: 52/52 OK, 0 errors, 0 state drift
  (21t / 77f / 50p, 5/5 mailbox RLS, 0 anon grants on Tier 1,
  0 anon EXECUTE on authorize_admin_role)
- [x] Phase 4 identity closure idempotency fix
  (DROP POLICY IF EXISTS on lines 69-70; semantic policy unchanged)
- [x] `supabase/config.toml` for wjbxrgbyhqpiujifwqcf (validated, no secrets)
- [x] 7-EF deployment manifest
- [x] 11-file staged application cutover (held in evidence, applied
  via PRIME-prepared reviewed commit, not sed)
- [x] 13-table data + auth migration mapping
- [x] 5 Tier 1 + 4 Tier 2 + 4 Tier 3 legacy anon-surface security review

PRIME-side: NO writes to either Supabase project. NO credential requests.

## 1. Founder authenticated actions (Waves 1-5)

### Wave 1 — Schema apply (production-safe migration chain)

**Goal:** apply the 52-step canonical chain to `wjbxrgbyhqpiujifwqcf`.

**Founder authenticated actions (pick ONE):**

#### Option A: Supabase Dashboard SQL Editor (Founder's browser)

1. Open https://supabase.com/dashboard/project/wjbxrgbyhqpiujifwqcf/sql
2. Authenticate with Founder's Supabase account (browser session)
3. For each of the 52 files in `supabase/apply_manifest.sh` MANIFEST
   array, in canonical order:
   - Open the file from the Javalin13/FleetConnect repo on
     integration-r056 (current head: `5356a58` or newer)
   - Copy the entire file contents
   - Paste into SQL Editor → Run
4. After all 52 applied, run the post-apply verification:

```sql
-- 5 foundational tables (TEXT / BIGSERIAL / UUID mix per §2)
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
3. Founder runs:
   ```bash
   DB_URL="<Founder's locally-stored DB connection string>" \
     ./supabase/apply_manifest.sh
   ```
   The `DB_URL` is held in Founder's local secret store (1Password,
   Bitwarden, or `~/.pgpass`). It is NEVER pasted into chat.

4. Verify the same way as Option A.

**Founder decision factors:**
- Option A: simpler, no CLI install, every step is auditable in
  Dashboard query history
- Option B: faster for the 52-step chain, but requires CLI setup
  (PRIME recommends upgrading to v2.116.0 first; v2.6.8 is too old)

**PRIME recommendation:** Option A for the initial Wave 1.

### Wave 2 — Edge function deploy (7 functions)

**Founder authenticated action (CLI):**

1. CLI login (same as Option B above, if not already done)
2. Upgrade CLI to v2.116.0+ (current is v2.6.8; new features)
3. Deploy in dependency order:
   ```bash
   supabase functions deploy dispatch-mail-flag    --project-ref wjbxrgbyhqpiujifwqcf
   supabase functions deploy dispatch-mail-inbox   --project-ref wjbxrgbyhqpiujifwqcf
   supabase functions deploy dispatch-mail-send    --project-ref wjbxrgbyhqpiujifwqcf
   supabase functions deploy send-email            --project-ref wjbxrgbyhqpiujifwqcf
   supabase functions deploy create-checkout-session --project-ref wjbxrgbyhqpiujifwqcf
   supabase functions deploy process-refund        --project-ref wjbxrgbyhqpiujifwqcf
   supabase functions deploy stripe-webhook        --project-ref wjbxrgbyhqpiujifwqcf
   ```
4. PRIME runs HTTP-boundary verify probes (see
   `evidence/r056-phase-g-edge-function-deployment-manifest.md` §4)

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

### Wave 4 — Application data migration + auth migration (SPLIT)

**This is the substantive change from the previous runbook.**
Per Lux 7aac5aa §7/§8, application data migration and auth
migration are SEPARATE procedures with DIFFERENT execution contracts.

#### 4A — Application data migration (13 core tables)

**Goal:** move operational data from legacy `rreqjjrmvytnwnsidmqi`
to new `wjbxrgbyhqpiujifwqcf` for the 13 core tables in
`evidence/r056-phase-g-data-auth-migration-mapping.md` §1.1.

**Founder authenticated action — supported paths ONLY (per Lux §7):**

##### Path A1: Dashboard SQL Editor result export (small tables)

For tables with a few hundred rows or less:
1. Open legacy Dashboard → SQL Editor
2. Run a `SELECT * FROM public.<table> ORDER BY <pk> LIMIT 1000;` query
3. Use the Dashboard "Export" button on the result grid to download
   the result as CSV
4. Repeat for each of the 13 tables

##### Path A2: Dashboard Table Editor export (medium tables)

For tables with up to ~10K rows:
1. Open legacy Dashboard → Table Editor → `<table>`
2. Click "..." menu → "Export" → CSV
3. Download the CSV
4. Repeat for each of the 13 tables

##### Path A3: pg_dump / psql \copy from Founder-authenticated local (large tables)

For tables with more than ~10K rows (e.g. bookings, transaction_ledger):
1. Founder has the legacy DB connection string stored in 1Password
2. From Founder's authenticated local environment:
   ```bash
   pg_dump "$LEGACY_DB_URL" \
     --table=public.bookings \
     --table=public.transaction_ledger \
     --data-only --no-owner --column-inserts \
     > fleetconnect-legacy-data-$(date +%Y%m%d).sql
   ```
   The `LEGACY_DB_URL` is in Founder's local secret store, never in
   chat/Bridge/evidence/repo.

**Founder hands the CSVs to PRIME** via Founder's local secret-share
mechanism (NOT chat, NOT Bridge, NOT email — use a Supabase Storage
private bucket with signed URL, or local rsync over a secure channel).

**PRIME imports the CSVs** into the new project using the
`psql \copy` commands in mapping §4.2.

#### 4B — Auth migration (DEFAULT: re-onboarding; NOT raw CSV import)

**Goal:** establish operator/customer/driver identity on the new
project. Per Lux 7aac5aa §8, raw `auth.users` / `auth.identities` CSV
import is NOT the canonical route.

**DEFAULT: Controlled re-onboarding / password reset.**

**Why this is the default:**
- Legacy `auth.users` hashes may be salted with a project-specific
  bcrypt salt that does not survive cross-project import
- `auth.identities` (Google OAuth etc.) rows have provider-specific
  invariants that are not preserved by naive CSV import
- Supabase Auth version drift between legacy and new projects is
  undocumented and may break token verification
- The operational user set is small (operators + a few dozen
  partners/drivers/customers); re-onboarding is operationally
  feasible

**Founder authenticated actions (re-onboarding flow):**

1. Inventory current users from legacy (via SQL Editor, Dashboard
   result export, or Founder's `psql` connection):
   ```sql
   SELECT id, email, raw_user_meta_data->>'role' AS role
   FROM auth.users
   ORDER BY created_at;
   ```
2. For each operator / partner / driver: trigger a password-reset
   email from the new project (Dashboard → Auth → Users → Send
   recovery email)
3. For each customer: send a "your account is on the new platform,
   please re-set your password" email from the new project
4. Document the old→new user-id mapping in
   `evidence/r056-phase-g-auth-user-id-mapping.md` (PRIME prepares
   the template; Founder fills the actuals)

**The old `user_id` UUID values in `customers`/`partners`/`drivers`/
`bookings` will NOT match the new project's `auth.users.id` values.**
This is expected. Application tables can either:
- (A) Be migrated with NULL `user_id` (re-link during re-onboarding
  by matching email), or
- (B) Be migrated with the old UUID preserved in a `legacy_user_id`
  column for audit (recommended)

**EXCEPTION path (use ONLY with explicit Lux approval):**

If re-onboarding is operationally infeasible AND Founder has
authenticated access to legacy `auth` schema (e.g. service_role
key via Founder-authenticated SQL Editor), the documented path is:

1. Founder exports `auth.users` schema (no hashes initially) via
   SQL Editor result export
2. PRIME checks current Supabase Auth docs for the supported
   cross-project auth transfer procedure
3. If the docs describe a supported procedure, Founder executes it
   via Dashboard + the documented steps
4. If the docs do NOT describe a supported procedure, the default
   (re-onboarding) is used

**PRIME does NOT import raw `auth.users` / `auth.identities` CSVs
into the new project.** This is a hard rule per Lux 7aac5aa §8.

### Wave 5 — Application cutover (PRIME-prepared reviewed commit, NOT sed)

**Per Lux 7aac5aa §6, this wave is a PRIME-prepared reviewed commit,
NOT a `sed` workflow.**

**Step 1: PRIME prepares the cutover commit on `integration-r056`**

1. PRIME works on a new branch `cutover-r057` (or similar) forked
   from current `integration-r056` head
2. PRIME updates the 11 HTML files (8 Paneel + 3 b2b) in the repo:
   - Replaces `rreqjjrmvytnwnsidmqi.supabase.co` →
     `wjbxrgbyhqpiujifwqcf.supabase.co`
   - Replaces the `eyJhbG...8MTA` placeholder with the **real
     new-project anon key** (read from Founder's local secret store
     via a Founder-supplied local file or environment variable;
     **NOT** from chat/Telegram)
3. The real anon key is the Supabase publishable key. It is
   intentionally client-visible. It may be committed where the raw
   static app architecture requires it (e.g. `Paneel/*.html`). It
   is NOT routed through `/tmp`, shell substitution, chat,
   Telegram, or Bridge
4. PRIME commits the change on `cutover-r057` and pushes the branch
5. PRIME opens a PR on `Javalin13/FleetConnect`:
   `cutover-r057` → `integration-r056`
6. PRIME's PR description includes:
   - The exact diff (URLs + anon key replacement)
   - The list of 11 files changed
   - A rollback reference (single `git revert`)
   - The "do not merge until Founder explicit cutover approval" notice

**Step 2: Founder reviews the PR**

1. Founder opens the PR in GitHub
2. Founder verifies the diff is exactly:
   - 11 files changed (8 Paneel + 3 b2b)
   - URL replacements are mechanical (`rreqjjrmvytnwnsidmqi` →
     `wjbxrgbyhqpiujifwqcf`)
   - The anon key is the **real** new-project key (not the
     placeholder)
3. Founder does NOT merge yet

**Step 3: Founder provides explicit cutover approval**

1. Founder responds on the PR (or in chat, if appropriate) with
   "cutover approved, merge now" (or similar)
2. PRIME merges the PR to `integration-r056`
3. Vercel auto-redeploys the branch (if Vercel is configured for
   `integration-r056`)

**Step 4: Founder performs the external cutover**

1. **Domain / DNS update:** in Founder's domain registrar, update
   DNS records to point at the new project's endpoints. (Or
   configure Supabase custom domain in the new project's Dashboard,
   then point DNS to Supabase's load balancer.)
2. **Stripe webhook URL update:** in Stripe Dashboard → Webhooks →
   FleetConnect endpoint, update URL to
   `https://wjbxrgbyhqpiujifwqcf.functions.supabase.co/stripe-webhook`.
   Copy the new signing secret back into the new project's
   `STRIPE_WEBHOOK_SECRET` (Wave 3 above).
3. **Resend sender domain verification:** in Resend Dashboard →
   Domains, verify the sender domain for `dispatch@fleetconnect.be`
   is configured for the new project. (Usually no action needed if
   domain ownership is independent of Supabase project.)

**Step 5: Founder first-real-booking verification**

1. Open the customer-facing booking page (now serving from new project)
2. Make a test booking
3. Verify email is sent (Resend Dashboard → Logs)
4. Verify payment intent is created (Stripe Dashboard → Payments)
5. Verify driver assignment (Operator dashboard)
6. Verify lifecycle event is created (PostgREST query:
   `SELECT * FROM booking_lifecycle_events ORDER BY created_at DESC LIMIT 1`)

**Step 6: Founder marks legacy read-only**

1. In legacy Supabase Dashboard: Settings → Database → Connection
   Pooling → set max connections to 0 (or revoke service_role from
   app)
2. Leave the project running (do NOT pause or delete) so it can
   be re-activated in the 30-day rollback window

## 2. Post-cutover (PRIME autonomous)

After Founder completes Wave 5, PRIME runs:

- Reproducible security probe (per
  `r056-phase-g-security-review-legacy-anon-surfaces.md` §7) on new
  project — must show 0 anon grants on Tier 1/2 surfaces
- Re-run mail regression matrix on F5/F6
- Run Phase G full regression on new project
- Re-execute the local harness apply (with stubs first, then
  production manifest) on a NEW local DB to confirm the chain is
  still robust post-cutover

## 3. Rollback

If at any point Founder decides the cutover must be reversed:

1. Founder flips DNS back to legacy project
2. Founder or PRIME reverts the application wiring commit (single
   `git revert <cutover-commit-sha>`)
3. Founder reverts Stripe webhook URL
4. Legacy project is still running (read-only, not paused) — traffic
   resumes
5. PRIME analyzes the failure, prepares a new cutover attempt

The 30-day legacy retention window is enforced by NOT pausing or
deleting the legacy project during the cutover window.

## 4. What this runbook does NOT require

- ❌ DB password in chat / Bridge
- ❌ Service role key in chat / Bridge
- ❌ Supabase CLI access token in chat / Bridge
- ❌ Edge function secret values in chat / Bridge / evidence
- ❌ Anon key in chat / Bridge (the anon key IS in the
  `Paneel/*.html` files at cutover time, but it is committed via a
  reviewed PR, not via `/tmp` + `sed`)
- ❌ `sed` / `awk` / shell substitution with `/tmp` files
- ❌ Server-side `COPY ... TO '/tmp/...'` (per Lux §7)
- ❌ Raw `auth.users` / `auth.identities` CSV import (per Lux §8)

All credential-bearing actions are authenticated (Dashboard OAuth /
CLI `supabase login`). PRIME never holds a Founder-issued secret.
The only credentials in the committed repo are:
- The new-project anon key (committed in `Paneel/*.html` via reviewed PR)
- The new-project URL (committed in `Paneel/*.html` via reviewed PR)

Both are intentionally public; no privileged secret is ever in chat,
Bridge, evidence, repo, or shell.
