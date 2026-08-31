# r056 Phase G Cutover Assessment — `rreqjjrmvytnwnsidmqi` → `wjbxrgbyhqpiujifwqcf`

**Date:** 2026-08-31
**Author:** PRIME (autonomous, post Founder decision lock + override)
**Founder directive:** FleetConnect fully migrates to `wjbxrgbyhqpiujifwqcf`. Historical project `rreqjjrmvytnwnsidmqi` becomes legacy/read-only and will be retired after verified cutover. Do NOT create new production dependencies on the old Supabase. Do NOT write to the old project unless separately authorized.

---

## 1. Verification of new target `wjbxrgbyhqpiujifwqcf` (read-only, anon key verified)

| Check | Result |
|---|---|
| DNS resolves | ✅ 6 Supabase infra IPs (IPv6 + IPv4-mapped) |
| Anon key valid | ✅ JWT decodes to `ref: wjbxrgbyhqpiujifwqcf`, `role: anon`, `exp: 2100812763` |
| Auth test (REST `/`) | 401 admin-only (expected; service_role required) |
| Auth test (PGRST probe) | `PGRST205` on nonexistent table → key IS valid |
| Storage API | responds `200` with empty `[]` bucket list |
| Edge function inventory | **EMPTY** — all 11 candidate names return `404 NOT_FOUND` |
| Anon-readable tables | **43/43 = all PGRST205 (404)** — schema cache empty |
| Tables present | **0 of 67 common SaaS table names** found |
| Buckets present | 0 |
| Functions deployed | 0 |

**Conclusion:** `wjbxrgbyhqpiujifwqcf` is a **valid, healthy, EMPTY greenfield Supabase project**. Zero schema, zero functions, zero buckets. Suitable for greenfield reconstruction.

---

## 2. Verification of legacy project `rreqjjrmvytnwnsidmqi` (read-only)

| Asset | Status |
|---|---|
| `bookings` | ✅ exists, anon-readable |
| `customers` | ✅ exists, anon-readable |
| `partners` | ✅ exists, anon-readable |
| `drivers` | ✅ exists, anon-readable |
| `account_requests` | ✅ exists, anon-readable |
| `payments` | ✅ exists |
| `pricing_profiles` | ✅ exists |
| `fixed_routes` | ✅ exists |
| `invoices` | ✅ exists |
| `settlements` | ✅ exists |
| `ride_reviews` | ✅ exists |
| `refunds` | ✅ exists |
| `transaction_ledger` | ✅ exists |
| `dispatch_mailbox_messages/attachments/audit/folders/session_state` | ❌ **NOT applied** (404) |
| Edge function `send-email` | ✅ deployed |
| Edge function `create-checkout-session` | ✅ deployed |
| Edge function `process-refund` | ✅ deployed |
| Edge function `stripe-webhook` | ✅ deployed |
| Edge function `dispatch-mail-inbox` | ❌ NOT deployed (404) |
| Edge function `dispatch-mail-send` | ❌ NOT deployed (404) |
| Edge function `dispatch-mail-flag` | ❌ NOT deployed (404) |
| Storage buckets (anon-readable) | empty |

**Conclusion:** Legacy has the 13 core tables + 4 prior edge functions. Phase F mailbox schema + 3 mailbox functions never applied/deployed to legacy.

---

## 3. Migration inventory (PRIME-side, verified)

| Asset | Count | Source |
|---|---|---|
| Pre-Phase-F timestamped migrations | 49 | `supabase/migrations/20260521000000...20260830000016_*.sql` |
| Unprefixed `phase4_identity_closure.sql` | 1 | `supabase/migrations/phase4_identity_closure.sql` |
| Phase F migration | 1 | `supabase/migrations/20260831000001_phase_f_dispatch_mailbox.sql` (21,321 bytes) |
| Phase F edge functions | 3 | `supabase/functions/{dispatch-mail-inbox,send,flag}/index.ts` |
| Existing edge functions (in repo) | 4 | `supabase/functions/{send-email,create-checkout-session,process-refund,stripe-webhook}/index.ts` |
| `supabase/config.toml` | 0 | NOT present — needs to be created for new project |

---

## 4. Cutover Assessment

### 4.1 What exists ONLY in historical production `rreqjjrmvytnwnsidmqi`?

- **Operational data** in 13 core tables (row counts not visible to anon probe; require service_role)
- **Edge function code**: 4 prior functions deployed (source is also in the repo, but the deployed instances may differ from repo HEAD)
- **Project-specific secrets**: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `RESEND_API_KEY` (or equivalent email provider), origin allowlists, JWT signing keys, project URL, anon/service_role keys
- **Auth users**: `auth.users` table populated with operator/customer/driver accounts
- **Storage objects**: private buckets may exist (not anon-visible)

### 4.2 What exists in the new project `wjbxrgbyhqpiujifwqcf`?

**NOTHING.** Empty greenfield Supabase project. All migrations need to be applied. All edge functions need to be deployed. All secrets need to be configured.

### 4.3 What must be migrated to make the new project production-equivalent?

**A. Schema (50 migrations total):**
- All 49 pre-Phase-F timestamped migrations
- `phase4_identity_closure.sql` (sorts last)
- `20260831000001_phase_f_dispatch_mailbox.sql` (Phase F)

**B. Edge functions (7 total):**
- 4 prior functions: `send-email`, `create-checkout-session`, `process-refund`, `stripe-webhook` (source in repo)
- 3 Phase F functions: `dispatch-mail-inbox`, `dispatch-mail-send`, `dispatch-mail-flag` (source in repo, KAS host = `w021ae07.kasserver.com`)

**C. Secrets (Founder-only via approved mechanism):**
- `SUPABASE_URL` (auto-set on deploy)
- `SUPABASE_ANON_KEY` (auto-set on deploy)
- `SUPABASE_SERVICE_ROLE_KEY` (auto-set on deploy)
- `FLEETCONNECT_ALLOWED_ORIGINS` (configurable)
- For each edge function:
  - `dispatch-mail-*` → `MAILBOX_USER`, `MAILBOX_PROVIDER_HOST`, `MAILBOX_PROVIDER_IMAP_PORT`, `MAILBOX_PROVIDER_SMTP_PORT`, `MAILBOX_IMAP_PASSWORD`, `MAILBOX_SMTP_PASSWORD`
  - `send-email` → `RESEND_API_KEY` (or equivalent)
  - `create-checkout-session` / `process-refund` / `stripe-webhook` → `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`

**D. Auth users:**
- All operator/customer/driver accounts from `auth.users`
- PRIME cannot export from old project (no service_role key for old project)
- Options: (i) Founder exports via Dashboard + provides CSV; (ii) Founder resets + re-creates; (iii) re-onboard from scratch

**E. Operational data (13 core tables):**
- PRIME cannot export from old project (no service_role key)
- Options: (i) Founder exports via Dashboard SQL Editor; (ii) PRIME applies migrations + Founder imports data manually

**F. Storage objects:**
- Old project shows empty buckets to anon
- May have private buckets with documents/attachments
- Founder lists + exports via Dashboard if any

**G. Repo linkage:**
- New `supabase/config.toml` with `project_id = "wjbxrgbyhqpiujifwqcf"`
- Update `Paneel/onderaannemerA.html` anon key + URL (commit when ready for cutover)
- Update any other hard-coded project refs

### 4.4 Is a safe controlled cutover preferable to waiting for recovery of the old account?

**YES, controlled cutover is preferable**, because:

1. **Old project is BLOCKED on edge function deploys.** Two consecutive Founder acks did not result in functions being live on `rreqjjrmvytnwnsidmqi`.
2. **Old project lacks Phase F migrations.** Mailbox tables don't exist there yet.
3. **Recovery decision is locked.** Founder has decided cutover to `wjbxrgbyhqpiujifwqcf` is the path forward.
4. **New project is empty + healthy** — ideal for greenfield reconstruction.
5. **Rollback path is preserved.** Old project remains accessible as read-only legacy.

**Risks to manage:**
- Data loss if operational data not migrated
- Auth users need re-provisioning
- Browser code update + DNS/domain changes at cutover time
- Stripe webhook URL update at cutover time
- Email sender identity re-verification

---

## 5. PRIME's Autonomous Surface (exhausted paths)

**What PRIME can do autonomously (no Founder action needed):**
- ✅ Read-only verification of new project (DONE in this evidence batch)
- ✅ Read-only audit of old project (DONE)
- ✅ Write cutover assessment (this document, DONE)
- ✅ Update repo `supabase/config.toml` to point at new project (CAN DO NOW)
- ✅ Build new anon key wiring in repo (CAN DO NOW — anon key is public)
- ✅ Plan + design migration apply order (CAN DO NOW)
- ✅ Prepare rollback-safe cutover runbook (CAN DO NOW)

**What PRIME cannot do without Founder action:**
- ❌ DB password for new project (for direct `psql` apply)
- ❌ Service role key for new project (for SQL Editor / API migrations)
- ❌ Supabase CLI access token for new project (for `supabase functions deploy`)
- ❌ Edge function secrets (RESEND_API_KEY, STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, MAILBOX_IMAP_PASSWORD, MAILBOX_SMTP_PASSWORD)
- ❌ Export auth.users from old project
- ❌ Export operational data from old project

---

## 6. Required Founder Actions (blocking PRIME from continuing cutover)

To proceed past the read-only verification phase:

**Wave 1 — Schema apply:**
- DB password OR service_role key for `wjbxrgbyhqpiujifwqcf`
- PRIME then applies 50 migrations + verifies post-apply state

**Wave 2 — Edge function deploy:**
- Supabase CLI access token for `wjbxrgbyhqpiujifwqcf`
- PRIME then deploys 7 edge functions + verifies HTTP boundary

**Wave 3 — Secrets configuration (Founder-only via Secrets UI):**
- All edge function secrets set via Supabase Dashboard → Edge Functions → Secrets
- PRIME then probes runtime, confirms auth reaches IMAP/SMTP

**Wave 4 — Data migration:**
- Founder exports operational data + auth users from old project
- PRIME imports + verifies

**Wave 5 — Cutover (Founder hands-on):**
- Browser code update (PRIME prepares patch, Founder commits)
- DNS / domain-level Supabase URL updates
- Stripe webhook URL update in Stripe Dashboard
- Founder confirms first real booking + email + payment on new project
- Old project marked read-only

---

## 7. Rollback-Safe Cutover Plan (preview)

1. **PRE-CUT (PRIME autonomous):**
   - Update `supabase/config.toml` with new project ref (NOT YET COMMITTED)
   - Stage updated `Paneel/onderaannemerA.html` anon key + URL (NOT YET COMMITTED)
   - Prepare rollback patch (single git revert)

2. **SCHEMA APPLY (Founder provisions secrets, PRIME executes):**
   - Apply 49 pre-Phase-F + Phase F + phase4 migrations
   - Verify 5 mailbox tables + 2 RPCs + 12 RLS policies
   - Verify zero anon grants
   - Run idempotency check

3. **EDGE FUNCTION DEPLOY (Founder provisions token, PRIME executes):**
   - Deploy 4 prior + 3 Phase F functions
   - Verify deployment via HTTP probe

4. **SECRETS (Founder-only via Secrets UI):**
   - All secrets set via Dashboard
   - PRIME probes runtime, confirms auth reaches IMAP/SMTP

5. **DATA MIGRATION (Founder provisions exports, PRIME imports):**
   - Founder exports from old project (CSV/SQL dump)
   - PRIME imports + verifies

6. **AUTH USERS (Founder-only):**
   - Founder decides export vs reset vs re-onboard

7. **CUTOVER (Founder hands-on):**
   - Browser code commit
   - DNS / Stripe webhook updates
   - First real booking verification

8. **POST-CUT VERIFICATION (PRIME autonomous):**
   - Run Phase G full regression on new project
   - Verify zero traffic to old project (Founder confirms)
   - Old project retained as rollback target for 30 days

---

## 8. Evidence Status

- ✅ STEP 1 — Read-only verification of new project (this document, §1)
- ✅ STEP 2 — Read-only audit of old project (this document, §2)
- ✅ STEP 3 — Cutover assessment (this document, §3-§7)
- ⏸ STEP 4 — Repo linkage prep (BLOCKED on Founder: anon key for repo wiring is OK, but DB password + service_role needed for migration apply)
- ⏸ STEP 5+ — Migration apply + edge function deploy + secrets + data (BLOCKED on Founder)

---

## 9. LUX — SYNC NEEDED

This evidence batch is ready for Lux review:
- Confirm cutover strategy is sound
- Validate rollback plan
- Review read-only verification findings (new project empty; legacy partially complete with Phase F absent)
- Acknowledge PRIME is blocked on Founder provisioning for further autonomous execution
