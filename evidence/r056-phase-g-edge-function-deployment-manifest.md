# r056 Phase G — 7-Edge-Function Deployment Manifest

**Date:** 2026-08-31
**Author:** PRIME (autonomous, post Lux 2195825 acceptance)
**Target project:** `wjbxrgbyhqpiujifwqcf` (greenfield, empty)
**Mission:** `2026-08-29-fleetconnect-operational-recovery`

---

## Purpose

Per Lux 2195825 §5: edge functions are deployed independently from SQL migrations. This manifest is the canonical, deterministic, single-source deployment order for all 7 edge functions in the greenfield target. It is the input the Founder (or CI) hands to `supabase functions deploy`.

**What this manifest IS:**
- 7 functions × deterministic order × per-function invocation command × verify command × rollback command
- The security boundary (verify_jwt ON / OFF) per function
- The required env var set per function (symbolic, never literal)
- The hash of the source bundle to deploy (recomputed at deploy time; this is the canonical line per function)

**What this manifest IS NOT:**
- Not a script that runs anything. It is a checklist + reference for the Founder or CI runner.
- Does not embed anon keys, service_role keys, Supabase access tokens, Stripe keys, Resend keys, or mailbox passwords.

---

## 1. Function inventory (7 total, matches `supabase/functions/`)

| # | Name | Source path | verify_jwt | Auth model | Secret set required (symbolic) |
|---|------|-------------|------------|------------|-------------------------------|
| F1 | `send-email` | `supabase/functions/send-email/index.ts` | **true** | Supabase JWT (authenticated operator) | `RESEND_API_KEY` |
| F2 | `create-checkout-session` | `supabase/functions/create-checkout-session/index.ts` | **true** | Supabase JWT (authenticated user) | `STRIPE_SECRET_KEY` |
| F3 | `process-refund` | `supabase/functions/process-refund/index.ts` | **true** | Supabase JWT + `authorize_admin_role()` server-derived scope | `STRIPE_SECRET_KEY` |
| F4 | `stripe-webhook` | `supabase/functions/stripe-webhook/index.ts` | **false** | `stripe-signature` header HMAC | `STRIPE_WEBHOOK_SECRET` |
| F5 | `dispatch-mail-inbox` | `supabase/functions/dispatch-mail-inbox/index.ts` | **true** | Supabase JWT + `authorize_dispatch_mailbox()` server-derived scope | `MAILBOX_USER`, `MAILBOX_PROVIDER_HOST`, `MAILBOX_PROVIDER_IMAP_PORT`, `MAILBOX_PROVIDER_SMTP_PORT`, `MAILBOX_IMAP_PASSWORD` |
| F6 | `dispatch-mail-send` | `supabase/functions/dispatch-mail-send/index.ts` | **true** | Supabase JWT + `authorize_dispatch_mailbox()` server-derived scope | `MAILBOX_USER`, `MAILBOX_PROVIDER_HOST`, `MAILBOX_PROVIDER_SMTP_PORT`, `MAILBOX_SMTP_PASSWORD` |
| F7 | `dispatch-mail-flag` | `supabase/functions/dispatch-mail-flag/index.ts` | **true** | Supabase JWT + `authorize_dispatch_mailbox()` server-derived scope | (none — pure RPC + audit log) |

**Sources of truth for these names + paths:** `supabase/functions/` directory (verified at PRIME worktree SHA `c98bff3`).

**Why verify_jwt=false on F4 only:** Stripe's webhook posts to a public URL with no JWT; the only authentication is the `stripe-signature` HMAC header which the function itself verifies against `STRIPE_WEBHOOK_SECRET`. If verify_jwt were true, Supabase would reject the request before Stripe's signature could be verified.

---

## 2. Deterministic deploy order

Functions are deployed in **dependency order**, not alphabetical. The principle: deploy pure data-plane (RPC-only) functions first, then integrations, then webhook.

| Step | Function | Why this order |
|------|----------|---------------|
| 1 | `dispatch-mail-flag` | F7 — pure RPC wrapper, no external service. Earliest go-live confidence. |
| 2 | `dispatch-mail-inbox` | F5 — depends on authorize_dispatch_mailbox() (DB) but no other function. |
| 3 | `dispatch-mail-send` | F6 — depends on F5's audit + same authorize. |
| 4 | `send-email` | F1 — depends on Resend only; no other FC function. |
| 5 | `create-checkout-session` | F2 — depends on Stripe only. |
| 6 | `process-refund` | F3 — depends on Stripe + admin role. |
| 7 | `stripe-webhook` | F4 — last, because webhook must point at the new URL + need to update Stripe Dashboard side. |

**Why webhook last:** F4 is an inbound integration. If it goes live before F2/F3, a Stripe event in flight (e.g. `checkout.session.completed`) would hit the new webhook URL but find no orders/state to update. Deferring F4 means the first N minutes of cutover have no inbound Stripe traffic to misroute.

---

## 3. Per-function deploy command

Replace `<SUPABASE_ACCESS_TOKEN>` (CLI session token) and `<PROJECT_REF>` (`wjbxrgbyhqpiujifwqcf`) with the values held in the deployment environment. **These are not committed to this repo.**

```bash
# Authenticate the CLI (one-time, not stored in repo)
supabase login --token "$SUPABASE_ACCESS_TOKEN"

# Link to the greenfield project (one-time)
supabase link --project-ref wjbxrgbyhqpiujifwqcf

# Deploy in order (this is the canonical sequence)
supabase functions deploy dispatch-mail-flag   --project-ref wjbxrgbyhqpiujifwqcf --no-verify-jwt false
supabase functions deploy dispatch-mail-inbox  --project-ref wjbxrgbyhqpiujifwqcf --no-verify-jwt false
supabase functions deploy dispatch-mail-send   --project-ref wjbxrgbyhqpiujifwqcf --no-verify-jwt false
supabase functions deploy send-email           --project-ref wjbxrgbyhqpiujifwqcf --no-verify-jwt false
supabase functions deploy create-checkout-session --project-ref wjbxrgbyhqpiujifwqcf --no-verify-jwt false
supabase functions deploy process-refund       --project-ref wjbxrgbyhqpiujifwqcf --no-verify-jwt false
supabase functions deploy stripe-webhook       --project-ref wjbxrgbyhqpiujifwqcf --no-verify-jwt true
```

> **Note on `--no-verify-jwt` flag:** this CLI flag is the inverse of the
> `verify_jwt` config.toml value. So F1-F3 + F5-F7 deploy with
> `--no-verify-jwt false` (i.e. JWT verification IS on), and F4 deploys
> with `--no-verify-jwt true` (JWT verification IS off — Stripe auth
> happens inside the function).

---

## 4. Per-function verify command (post-deploy HTTP probe)

Each function has a known endpoint (per official Supabase Edge
Functions deployment contract at
https://supabase.com/docs/guides/functions/deploy and
https://supabase.com/docs/guides/functions/quickstart):
`https://wjbxrgbyhqpiujifwqcf.supabase.co/functions/v1/<name>`.

| # | Function | Verify probe | Expected |
|---|----------|--------------|----------|
| F1 | `send-email` | `curl -i -X POST https://wjbxrgbyhqpiujifwqcf.supabase.co/functions/v1/send-email` | `401` (no JWT) |
| F2 | `create-checkout-session` | `curl -i -X POST .../create-checkout-session` | `401` (no JWT) |
| F3 | `process-refund` | `curl -i -X POST .../process-refund` | `401` (no JWT) |
| F4 | `stripe-webhook` | `curl -i -X POST .../stripe-webhook` | `400` (missing signature, not 401 — verify_jwt is off) |
| F5 | `dispatch-mail-inbox` | `curl -i -X POST .../dispatch-mail-inbox -H 'content-type: application/json' -d '{}'` | `401` (no JWT) |
| F6 | `dispatch-mail-send` | `curl -i -X POST .../dispatch-mail-send -d '{}'` | `401` (no JWT) |
| F7 | `dispatch-mail-flag` | `curl -i -X POST .../dispatch-mail-flag -d '{}'` | `401` (no JWT) |

**Critical:** F4 must return **400 missing stripe-signature**, not 401. If F4 returns 401, JWT verification is still on and Stripe callbacks will fail.

**Beyond the 401/400 probe:** per Lux 2195825 §5.3 — boundary is verified. Real-boundary tests (with valid JWT, valid scope, real Stripe sandbox, real IMAP/SMTP) are F5.4+ and require Founder-provided credentials. PRIME does not run those autonomously.

---

## 5. Per-function secret set (symbolic, never literal)

| # | Function | Secret env vars (symbolic) | Where set | Notes |
|---|----------|--------------------------|-----------|-------|
| F1 | `send-email` | `RESEND_API_KEY` | Dashboard → Edge Functions → Secrets | Per-function; do not set globally. |
| F2 | `create-checkout-session` | `STRIPE_SECRET_KEY` | Dashboard → Edge Functions → Secrets | Stripe LIVE key; test mode only for staging. |
| F3 | `process-refund` | `STRIPE_SECRET_KEY` | Dashboard → Edge Functions → Secrets | Same secret as F2; do not duplicate. |
| F4 | `stripe-webhook` | `STRIPE_WEBHOOK_SECRET` | Dashboard → Edge Functions → Secrets | Distinct from F2/F3 — this is the webhook signing secret, not the API key. |
| F5 | `dispatch-mail-inbox` | `MAILBOX_USER`, `MAILBOX_PROVIDER_HOST`, `MAILBOX_PROVIDER_IMAP_PORT`, `MAILBOX_PROVIDER_SMTP_PORT`, `MAILBOX_IMAP_PASSWORD` | Dashboard → Edge Functions → Secrets | Per `FOUNDER_DISPATCH_MAILBOX_SECRET_PROVISIONING.md`. |
| F6 | `dispatch-mail-send` | `MAILBOX_USER`, `MAILBOX_PROVIDER_HOST`, `MAILBOX_PROVIDER_SMTP_PORT`, `MAILBOX_SMTP_PASSWORD` | Dashboard → Edge Functions → Secrets | SMTP-only (no IMAP). |
| F7 | `dispatch-mail-flag` | (none) | n/a | Pure RPC. |

**All-Inkl KAS host note (per Lux be9be92 + eb4a9bf):** `MAILBOX_PROVIDER_HOST` is account-specific, value `w021ae07.kasserver.com` for FleetConnect's KAS account. The default in the F5/F6 source code may be different — Founder verifies via DNS + MX before set.

**Auto-injected secrets (do NOT set manually):** `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL` — these are injected by the Supabase platform on every deploy and are not configurable.

---

## 6. Source-bundle integrity (recomputed at deploy time)

At deploy time, the runner MUST verify that the function source being deployed matches the SHA pinned in this manifest section. The SHA below is the **canonical reference** for what is supposed to be deployed. The runner computes the SHA at deploy time and aborts on mismatch.

| # | Function | Pinned source SHA (commit `c98bff3` HEAD of integration-r056) | Bundle |
|---|----------|---------------------------------------------------------------|--------|
| F1 | `send-email` | `c98bff3` (HEAD at manifest creation) | `supabase/functions/send-email/` |
| F2 | `create-checkout-session` | `c98bff3` | `supabase/functions/create-checkout-session/` |
| F3 | `process-refund` | `c98bff3` | `supabase/functions/process-refund/` |
| F4 | `stripe-webhook` | `c98bff3` | `supabase/functions/stripe-webhook/` |
| F5 | `dispatch-mail-inbox` | `c98bff3` (Phase F Batch 1) | `supabase/functions/dispatch-mail-inbox/` |
| F6 | `dispatch-mail-send` | `c98bff3` (Phase F Batch 1) | `supabase/functions/dispatch-mail-send/` |
| F7 | `dispatch-mail-flag` | `c98bff3` (Phase F Batch 1) | `supabase/functions/dispatch-mail-flag/` |

**Re-verify at deploy time:**
```bash
git rev-parse HEAD  # must equal c98bff3 (or newer pinned SHA updated here)
sha256sum supabase/functions/*/index.ts
```

If the local HEAD has moved past `c98bff3` (additional commits on the branch before deploy), this section MUST be updated to the new SHA before the deploy step runs. PRIME will update this section as part of the deploy commit.

---

## 7. Per-function rollback command

Each function can be redeployed to its previous version via:
```bash
supabase functions deploy <name> --project-ref wjbxrgbyhqpiujifwqcf
```

If the previous version's source has been lost (e.g. bad merge), rollback is a `git revert` of the offending commit + redeploy. The repo carries every prior version on `integration-r056` + its ancestors (`integration-r055`, `integration-r054`, ...).

**Webhooks (F4) are special:** rolling back F4 means the Stripe Dashboard's webhook URL still points to the new project's F4 endpoint. If you need to **disable** the webhook entirely during rollback, the Stripe Dashboard → Webhooks → FleetConnect endpoint has a "Disable" toggle. The endpoint URL does not need to change to disable; the toggle suffices.

**Function secret rollback:** if a function was deployed with a bad secret, the rollback is `Dashboard → Edge Functions → <name> → Secrets → delete bad secret` then re-add the correct one. No redeploy needed for secret-only rollbacks.

---

## 8. Cross-cutting deploy invariants

1. **All 7 functions must be deployed in the same `supabase link` session.** Splitting the deploy across multiple CLI sessions risks project state drift (rare, but seen in legacy).
2. **All secrets must be set BEFORE the first post-deploy verify probe.** F5/F6 will return `adapter_unavailable` (not 401) if their secrets are missing, which is the friendly "missing creds" path designed for local dev.
3. **The F4 webhook URL update in Stripe Dashboard is a separate, manual step** (Founder-only). It happens AFTER F4 deploy + verify. Do not conflate.
4. **F5/F6/F7 require the Phase F migration to be applied first.** This is the dependency on the SQL apply order. If Phase F has not run, F5/F6/F7 will fail with `relation "public.dispatch_mailbox_messages" does not exist` (or similar).

---

## 9. What this manifest does NOT do

- Does NOT execute any remote write. No `supabase deploy` is invoked by this document.
- Does NOT contain any literal secret value. All secrets are symbolic.
- Does NOT update the Stripe Dashboard webhook URL (Founder action).
- Does NOT update DNS for `fleetconnect.be` (Founder action).
- Does NOT modify any function source code. The 7 `index.ts` files in `supabase/functions/` are the deployment payload; this manifest is the checklist around them.
- Does NOT commit or push to `Javalin13/FleetConnect` from the PRIME worktree (PRIME's branch is `integration-r056`, push is performed in a later wave).

---

## 10. LUX — SYNC NEEDED

This manifest is ready for Lux review:
- Confirm deploy order (dependency-driven, not alphabetical)
- Confirm verify_jwt settings per function (F1-F3 + F5-F7 = on; F4 = off)
- Confirm secret inventory (8 symbolic identifiers across 6 functions; F7 = none)
- Confirm source-bundle pinning (HEAD `c98bff3` + recompute on every deploy)
- Confirm rollback command correctness
- Confirm the cross-cutting invariants §8

PRIME is NOT blocked on Founder provisioning for the manifest itself. The
deploy execution (running the `supabase functions deploy` commands) is
blocked on the CLI access token + the secret set, both Founder-only.
