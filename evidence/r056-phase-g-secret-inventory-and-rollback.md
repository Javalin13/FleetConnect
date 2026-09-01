# r056 Phase G — Secret Inventory + Rollback Plan

**Date:** 2026-08-31
**Author:** PRIME (autonomous, post Lux 2195825 acceptance)
**Target project:** `wjbxrgbyhqpiujifwqcf` (greenfield)
**Legacy project:** `rreqjjrmvytnwnsidmqi` (read-only after cutover)

---

## Why this document exists (per Lux 2195825 §6 + cross-session-sync)

> "credentials/secrets only in secure server environment/config, never
> browser/repo/Bridge/evidence/chat/Telegram"

This document names every secret that the new project needs. **It never
contains a literal secret value.** Symbolic identifiers only. Each
secret is mapped to:
- Where it is set (Supabase Dashboard, env file, CI secret, ...)
- Who can set it (Founder-only vs PRIME)
- Rollback procedure (how to invalidate or rotate)

---

## 1. Secret inventory (canonical, 12 symbolic identifiers)

| # | Symbolic name | Purpose | Bound to function / system | Set by | Stored in |
|---|---------------|---------|----------------------------|--------|-----------|
| S1 | `SUPABASE_URL` | Project public URL (auto-injected by Supabase) | Platform (every function) | **Auto** (Supabase) | n/a (runtime env) |
| S2 | `SUPABASE_ANON_KEY` | Public anon JWT (browser-side) | Browser HTML / anon-rest | **Auto** (Supabase) | Hardcoded in `Paneel/*.html` + `b2b/*.html` (this is public) |
| S3 | `SUPABASE_SERVICE_ROLE_KEY` | Privileged service role (server-side) | All 7 edge functions | **Auto** (Supabase) | n/a (runtime env) |
| S4 | `SUPABASE_DB_URL` | Direct Postgres connection | Local `psql` apply | **Auto** (Supabase) | CI / deploy env |
| S5 | `RESEND_API_KEY` | Resend transactional email | F1 `send-email` | **Founder** | Dashboard → Edge Functions → Secrets |
| S6 | `STRIPE_SECRET_KEY` | Stripe API (live or test) | F2 `create-checkout-session`, F3 `process-refund` | **Founder** | Dashboard → Edge Functions → Secrets |
| S7 | `STRIPE_WEBHOOK_SECRET` | Stripe webhook signing secret | F4 `stripe-webhook` | **Founder** | Dashboard → Edge Functions → Secrets |
| S8 | `MAILBOX_USER` | Mailbox identity (default `dispatch@fleetconnect.be`) | F5/F6 | **Founder** (optional — default set) | Dashboard → Edge Functions → Secrets |
| S9 | `MAILBOX_PROVIDER_HOST` | All-Inkl KAS account-specific host | F5/F6 | **Founder** (default `w021ae07.kasserver.com` per Lux be9be92/eb4a9bf) | Dashboard → Edge Functions → Secrets |
| S10 | `MAILBOX_PROVIDER_IMAP_PORT` | IMAP port (default 993) | F5 | **Founder** (optional) | Dashboard → Edge Functions → Secrets |
| S11 | `MAILBOX_PROVIDER_SMTP_PORT` | SMTP submission port (default 465) | F5/F6 | **Founder** (optional) | Dashboard → Edge Functions → Secrets |
| S12 | `MAILBOX_IMAP_PASSWORD` | IMAP password for `dispatch@fleetconnect.be` | F5 | **Founder** | Dashboard → Edge Functions → Secrets |
| S13 | `MAILBOX_SMTP_PASSWORD` | SMTP submission password | F6 | **Founder** | Dashboard → Edge Functions → Secrets |

> **S1–S4 are auto-managed** by the Supabase platform. They are not secrets
> in the strict sense (S2 is intentionally public; S3/S4 are server-side
> but rotated by Supabase). They are listed for completeness.
>
> **S5–S7 are external SaaS secrets.** The Founder holds them in
> 1Password/Bitwarden. PRIME never sees the literal value.
>
> **S8–S13 are mailbox secrets** per the existing
> `FOUNDER_DISPATCH_MAILBOX_SECRET_PROVISIONING.md` flow.

---

## 2. Per-secret set procedure

### 2.1 S5 `RESEND_API_KEY`

**Set via:** Supabase Dashboard → Project `wjbxrgbyhqpiujifwqcf` → Edge Functions → `send-email` → Secrets → Add secret `RESEND_API_KEY` → paste value → Save.

**Verify:** `curl -X POST https://wjbxrgbyhqpiujifwqcf.functions.supabase.co/send-email -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d '{"to":"verify@resend.dev","subject":"smoke","html":"smoke"}'` → expect 200 or 422 (Resend accepts the request). If the function returns 500 with `RESEND_API_KEY not configured`, secret was not set.

**Rotate:** Dashboard → Secrets → edit → save. No redeploy needed.

**Rollback:** Dashboard → Secrets → delete. Function returns 500 with `RESEND_API_KEY not configured`. Frontend renders friendly "email unavailable" panel (per Phase E r2 error handling).

### 2.2 S6 `STRIPE_SECRET_KEY`

**Set via:** Dashboard → Edge Functions → `create-checkout-session` → Secrets → Add `STRIPE_SECRET_KEY` → paste value (live key starts with `sk_live_`; test key starts with `sk_test_`).

**Verify:** Trigger one checkout from the browser on a test booking. If the Stripe Checkout URL is returned, the secret is wired.

**Also set on:** F3 `process-refund` (same secret).

**Rotate:** Same as 2.1.

**Rollback:** Same as 2.1.

### 2.3 S7 `STRIPE_WEBHOOK_SECRET`

**Set via:** Dashboard → Edge Functions → `stripe-webhook` → Secrets → Add `STRIPE_WEBHOOK_SECRET` → paste the value from Stripe Dashboard → Webhooks → FleetConnect endpoint → Signing secret.

**Verify:** `curl -X POST https://wjbxrgbyhqpiujifwqcf.functions.supabase.co/stripe-webhook -H "stripe-signature: t=0,v1=0" -d '{}'` → expect 400 `Webhook Error: No signatures found matching the expected signature for payload`. If 400 with that message, the secret is loaded (signature just doesn't match the test payload).

**Rollback:** Dashboard → Secrets → delete. The function will reject every Stripe callback with 400 (signature missing) until the secret is re-set.

### 2.4 S8–S13 Mailbox secrets

**Set via:** Per `FOUNDER_DISPATCH_MAILBOX_SECRET_PROVISIONING.md`. Dashboard → Edge Functions → `dispatch-mail-inbox` → Secrets → add each of S12, S9, S8, S10, S11. Same for `dispatch-mail-send` with S13, S9, S8, S11.

**Verify:** F5 with valid JWT + `authorize_dispatch_mailbox()` → `{action: 'folders'}` → expect 200 with folder list. If `adapter_unavailable: mailbox_credentials_unconfigured`, secrets are missing.

**Rollback:** Dashboard → Secrets → delete individually. Function returns `{ok: false, status: 'adapter_unavailable', reason: 'mailbox_credentials_unconfigured'}` — UI friendly path.

---

## 3. Rollback plan (whole-project)

### 3.1 Tier 1 — Function-secret-only rollback (no code change)

If a bad secret was set, do NOT redeploy. Just edit/delete in Dashboard.
Functions hot-reload secrets on next invocation. No downtime.

### 3.2 Tier 2 — Function-source rollback

If a function has a code bug introduced in the current deploy:

1. `git revert <bad-commit-sha>` on `integration-r056`.
2. Re-push the branch.
3. `supabase functions deploy <name> --project-ref wjbxrgbyhqpiujifwqcf`.
4. Re-run the verify probe (manifest §4).

### 3.3 Tier 3 — Function-source rollback + secret rotation

If a function was deployed with a leaked secret:

1. Rotate the secret at the source (Resend, Stripe, All-Inkl).
2. Update Dashboard → Secrets with the new value.
3. `git revert` + redeploy (same as Tier 2).

### 3.4 Tier 4 — Schema rollback (DB migration)

The migration chain is additive (per Phase G manifest). There is no
migration that DROPs tables or REVOKEs in a destructive way. If a
migration causes an issue:

1. `git revert <bad-commit-sha>`.
2. PRIME applies the revert migration to a test DB.
3. Founder runs the revert migration on production (this is the
   irreversibility bound; PRIME does not auto-revert production schemas).

### 3.5 Tier 5 — Whole-project rollback to legacy

If the entire cutover must be reversed (catastrophic — the new project
turns out to be unrecoverable):

1. Founder flips DNS / Vercel rewrites back to `rreqjjrmvytnwnsidmqi.supabase.co`.
2. Browser code is reverted via the cutover patch (single git revert).
3. Stripe Dashboard → Webhooks → URL reverted to legacy function URL.
4. Legacy was preserved as read-only per cutover plan; resume operation
   from there. Data not yet migrated to new is still in legacy.

**Key principle:** legacy is NEVER deleted during the cutover window. The
30-day retention is enforced by leaving the project untouched (not
paused, not deleted, not paused-billed).

---

## 4. Pre-cutover secret rotation recommendations

Before cutover, the Founder should rotate:

| Secret | Why rotate | Where |
|--------|------------|-------|
| `RESEND_API_KEY` | Project change | Resend Dashboard → API Keys → rotate |
| `STRIPE_SECRET_KEY` | Project change | Stripe Dashboard → API keys → roll key |
| `STRIPE_WEBHOOK_SECRET` | URL change | Stripe Dashboard → Webhooks → roll signing secret |
| `MAILBOX_IMAP_PASSWORD` | Already done in Phase F prep | All-Inkl webmail → reset |
| `MAILBOX_SMTP_PASSWORD` | Same as above | All-Inkl webmail → reset |

**Why rotate pre-cutover:** even if the old project's secrets were not
leaked, rotating on the day of cutover ensures the legacy keys are
inert (no path of accidental use). It also means the new project is
the only place those secrets are valid.

---

## 5. CI / deploy-environment secrets (out of scope for this PR)

For the CI runner (when this manifest is consumed by GitHub Actions or
similar), additional secrets are needed:

| Symbolic name | Purpose | Who sets |
|---------------|---------|----------|
| `SUPABASE_ACCESS_TOKEN` | CLI session token (scoped to the org) | Founder (manual, 1Password → CI secret store) |
| `SUPABASE_DB_URL` (for CI) | Direct DB connection for `psql` apply | Founder |

These are CI-side and are NOT referenced by the running edge functions
(the functions get `SUPABASE_DB_URL` from the platform auto-inject).
They are listed here for completeness only.

---

## 6. What this document does NOT contain

- **No literal key values.** Every secret is a symbolic name.
- **No environment file (`*.env`).** All secrets go to Dashboard, not repo.
- **No CI YAML.** That is a separate document.
- **No instructions for the Founder to paste keys anywhere except Dashboard.**

---

## 7. LUX — SYNC NEEDED

- Confirm 12-entry secret inventory (S1–S13; S2–S4 are auto-managed)
- Confirm per-secret set / verify / rollback procedures
- Confirm Tier 1–5 rollback ladder
- Confirm pre-cutover rotation list
- Confirm CI-side secret list (out of scope for this PR)
