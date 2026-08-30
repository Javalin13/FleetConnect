# FOUNDER STAGING ACTION — Single Concrete Provisioning Request

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Date**: 2026-08-30T16:20+02:00
**Authority**: Lux r051 §3 + §4 + §6 + §7.7

---

## ONE Action Required from Founder

Provision a **staging environment** with the three capabilities required for protected B3 E2E (canonical booking-to-completion per Lux r051 §4).

### What to provision

1. **Staging Supabase project** (new or existing):
   - Apply current FleetConnect baseline migrations (everything BEFORE PRIME's r047-r051 additions).
   - This establishes the baseline schema and RLS policies.

2. **Privileged backend execution mechanism** (only ONE of these two options):

   **Option A (preferred)**: A scheduler endpoint on the staging project that holds the `service_role` secret server-side and exposes JSON-over-HTTPS `POST /execute-mutator` calls for the four service-role-only mutators:
   - `timeout_expired_assignment`
   - `scan_and_timeout_expired_assignments`
   - `assign_pending_booking_to_driver`
   - `auto_assign_pending_bookings`

   **Option B**: Send PRIME the **staging service_role secret** via ONE approved secure secret mechanism (vault, one-time-share link with expiration, or env file PRIME loads at runtime). **Secret value NEVER in chat, Telegram, GitHub, evidence, or bridge documents — only the secret NAME is documented**.

3. **Disposable test identities** for staging-only use:
   - 1 operator/head-partner UI session
   - 1 driver session (accept/decline capability)
   - 1 customer session (booking creation + portal auth)

   These are **NOT** production identities. They are throwaway test identities in the staging project.

### What to provide PRIME with (NOT secrets, just identifiers)

- Staging Supabase project URL (not a secret)
- Staging Supabase anon key (already safe for public use — same level as a public API key)
- Staging scheduler endpoint URL (not a secret)
- Authentication method to the scheduler endpoint (e.g. env-var name `STAGING_SCHEDULER_TOKEN` whose value PRIME never sees, or a username/password pair sent via approved secure mechanism, or mutual TLS cert path)

### What PRIME does NOT need from Founder

- ❌ No manual test execution — PRIME owns all E2E-A through E2E-D/E
- ❌ No production auth mutation
- ❌ No production environment access
- ❌ No credentials placed in chat/Telegram/GitHub/evidence/bridge
- ❌ No Ayoub UI session (Ayoub is dispatch mail recipient, NOT a UI login)
- ❌ No reused production identities in staging

---

## What PRIME Does After F1

| # | Step | Owner |
|---|---|---|
| 1 | Apply r047-r051 migrations to staging | PRIME |
| 2 | Run migration 000010 pricing regression guard (expect 6 NOTICE OK) | PRIME |
| 3 | Run timeout matrix T1-T7 + TC1 against staging scheduler endpoint | PRIME |
| 4 | Run mail regression matrix against staging public RPCs | PRIME |
| 5 | Run E2E-A through E2E-E canonical booking lifecycle (6 complete scenarios) | PRIME |
| 6 | Capture audit trail + commit evidence | PRIME |
| 7 | Report `LUX — SYNC NEEDED` with staging results | PRIME |

---

## F1 Completion Signal

F1 is complete when PRIME has:

1. Successfully authenticated to staging anon key + scheduler endpoint (or service-role secret in approved vault).
2. Successfully executed ONE privileged mutator call (e.g. `timeout_expired_assignment` on a staging test booking).
3. Reported `STAGING ACCESS VERIFIED` to Lux with the test mutator call result.

After F1, PRIME owns the remaining technical execution autonomously.

---

## What Happens After B2/B3 E2E-A-E Pass in Staging

1. PRIME publishes final r053 evidence with literal staging outputs for all 6 E2E scenarios.
2. Lux independently reviews and may declare **MISSION COMPLETE** only when safe to tell Campanile/Lorena/The Lodge FleetConnect is operational again.
3. Founder remains final business decision-maker and may then choose/send external communication.

The Founder does NOT need to tell customers first in order to prove it is safe to tell customers. The technical criterion is Lux + PRIME evidence proving external green-light safety.

---

**This is the ONE concrete Founder action.** Nothing else is required.
