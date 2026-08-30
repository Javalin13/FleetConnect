# F1 — Secure Staging-Access Action (r052, per Lux r051 §3)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Date**: 2026-08-30T16:10+02:00
**Authority**: Lux r051 §3 (anon-key alone is INSUFFICIENT for service-role-only mutators)

---

## What F1 Actually Requires

r049 LOCKED these mutator functions to `service_role`:
- `assign_pending_booking_to_driver(p_booking_id text, p_driver_id uuid)`
- `auto_assign_pending_bookings(p_limit integer)`
- `timeout_expired_assignment(p_booking_id text, p_now timestamptz)`
- `scan_and_timeout_expired_assignments(p_now timestamptz)`

A standard staging Supabase URL + anon key CANNOT execute these via the PostgREST API (anon role lacks EXECUTE privilege). PRIME does NOT need to loosen the grants — that would be a security regression.

**The F1 ask is the minimum staging environment that gives the test runner these three capabilities simultaneously, without ever placing secret values in chat, Telegram, GitHub, evidence files, or bridge documents.**

---

## The Three Required Capabilities

| Capability | What it does | Why anon-key is insufficient |
|---|---|---|
| **C1: Public/client flow access** | Runs BOOKING_CONFIRMATION, DRIVER_ASSIGNMENT_REQUEST, DRIVER_ASSIGNED, BOOKING_CANCELLED, etc. that are triggered from PV.html/PV_en.html/PV_fr.html/klantenportaalpv.html/b2b webbooker using anon JWT | Anon role can trigger these via RPCs that allow `anon`/`authenticated` (e.g. `create_public_booking`, `calculate_booking_fare` etc.) |
| **C2: Privileged backend mutator execution** | Runs `assign_pending_booking_to_driver`, `auto_assign_pending_bookings`, `timeout_expired_assignment`, `scan_and_timeout_expired_assignments` which require `service_role` | Anon key returns `permission denied for function`; only service_role can EXECUTE |
| **C3: Test role sessions for UI/auth E2E** | Tests the operator/head-partner UI session, driver accept/decline session, customer portal/auth session in protected B3 | Real-role JWTs are needed (not anon), but NOT service-role |

---

## Required Founder Action (ONE concrete provisioning action)

The Founder performs **one single provisioning action** that creates a staging environment with these three capabilities baked in:

### Option A (preferred): Provision a staging project + scheduler endpoint

The Founder:

1. Creates a new Supabase project (or uses an existing staging project if one exists).
2. Applies the current FleetConnect baseline migrations (all migrations BEFORE PRIME's r047-r051 additions) to that staging project. This establishes the baseline schema and RLS policies.
3. Provisions a backend scheduler endpoint on that staging project that holds the `service_role` secret server-side and exposes a JSON-over-HTTPS endpoint for:
   - `POST /execute-mutator` with body `{ "rpc": "timeout_expired_assignment", "args": { "p_booking_id": "...", "p_now": "..." } }`
   - `POST /execute-mutator` with body `{ "rpc": "auto_assign_pending_bookings", "args": { "p_limit": 10 } }`
   - `POST /execute-mutator` with body `{ "rpc": "assign_pending_booking_to_driver", "args": { "p_booking_id": "...", "p_driver_id": "..." } }`
4. Provisions disposable test identities in the staging project (operator/head-partner UI, driver accept/decline, customer portal/auth). These are throwaway identities in staging — they MUST NOT be production identities.
5. Provides PRIME with:
   - **Staging Supabase project URL** (not a secret)
   - **Staging Supabase anon key** (not a secret — already safe for public use)
   - **Staging scheduler endpoint URL** (not a secret)
   - **A way to authenticate to the scheduler endpoint** — the FOUND'S choice, e.g.:
     - a separate staging-only API key that PRIME never sees the value of (Founder puts it in a secret manager and gives PRIME only the env-var name to reference, e.g. `STAGING_SCHEDULER_TOKEN`)
     - OR a username/password for the scheduler endpoint
     - OR mutual TLS with a client certificate PRIME references by path

**The scheduler endpoint is the secure boundary** — it holds the `service_role` secret on the server side. PRIME never sees that secret; PRIME only sees the scheduler endpoint URL and an authentication method.

### Option B: Provision staging + supply service-role secret via secure channel

If Option A is too much provisioning work, the Founder alternatively:

1. Creates the staging project + applies baseline migrations + provisions test identities (same as A.1, A.2, A.4).
2. Sends PRIME the **staging service_role secret** through ONE approved secure secret mechanism (e.g. a vault the Founder controls, or a one-time-share link with expiration, or a Founder-signed env file PRIME loads at runtime). **The secret value is NEVER placed in chat/Telegram/GitHub/evidence/bridge documents — only the secret name is documented**.

PRIME then uses the secret at runtime to call the service-role-only mutators via the Supabase admin API (which is what service_role is for).

---

## What the Founder does NOT need to do

- ❌ Do NOT request the staging environment manually for PRIME — Founder does ONE provisioning action, PRIME does the rest
- ❌ Do NOT ask PRIME to do provisioning work — that's Founder-only authority
- ❌ Do NOT mutate production auth or session recovery — staging only
- ❌ Do NOT move secrets across chat/Telegram/GitHub — use approved secure mechanisms
- ❌ Do NOT perform any technical step PRIME can execute given access

---

## What PRIME does after Founder F1 completes

| Step | Action | Risk |
|---|---|---|
| 1 | Apply r047-r051 migrations to staging | Low |
| 2 | Run pricing regression guard (migration 000010) — verify 6 NOTICE OK | Low |
| 3 | Run auto-assignment mutator smoke tests via scheduler endpoint (T1-T7 + TC1) | Low |
| 4 | Run mail regression matrix against staging public RPCs | Low |
| 5 | Run E2E-A through E2E-E canonical booking-to-completion chain | Low |
| 6 | Capture audit trail + commit evidence | Low |
| 7 | Report `LUX — SYNC NEEDED` with results | Low |

---

## Critical Anti-Patterns

- ❌ Do NOT loosen service-role-only mutator grants to make them anon-executable. That would undo r049 security hardening.
- ❌ Do NOT place any secret value (service_role key, anon key, JWT, password) in chat, Telegram, GitHub issues, PR descriptions, evidence files, or bridge documents. The vault holds the secret; the bridge holds only the secret *name*.
- ❌ Do NOT reuse production identities (Moukrim operator, customer accounts) for staging E2E. Staging identities are disposable test identities only.
- ❌ Do NOT mutate production auth or sessions for the staging test. Production is read-only from PRIME's perspective.
- ❌ Do NOT skip E2E-A through E2E-E. Each is required, not optional.

---

## F1 Completion Signal

F1 is complete when PRIME has:

1. Successfully authenticated to staging anon key + scheduler endpoint (or service-role secret in approved vault).
2. Successfully executed ONE privileged mutator call (e.g. `timeout_expired_assignment` on a test booking).
3. Reported `STAGING ACCESS VERIFIED` to Lux with the test mutator call result.

After F1, PRIME owns A1-C4 (B2/B3 staging validation) autonomously.
