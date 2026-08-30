# Protected B2/B3 Execution Checklist (r051 — per Lux §5 minimum Founder burden)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Date**: 2026-08-30T15:20+02:00
**Authority**: Lux r050 §5 (collapse 14 Founder steps to minimum genuinely necessary access/actions)

---

## Minimum Founder Burden (Lux §5 refined)

Per Lux §5: "do not turn environment limitations into 14 separate Founder tasks if one legitimate access/setup action can unlock several checks."

The 14 Founder steps from r050 have been collapsed to **TWO minimal Founder-mediated actions**, after which PRIME owns all technical execution:

### Minimum required from Founder

| # | Action | Unlocks |
|---|---|---|
| **F1** | Founder creates or provisions a **staging-equivalent FleetConnect environment** (read-write against isolated target, no production writes) + provides URL/anon-key for it via secure channel (NOT in chat/Telegram) | Unlocks A1, A2, A3 (B2 setup), B1, B2, B3 (operator session recovery), C1-C4 (B3 controlled E2E) |
| **F2** | Founder issues external green light to Lux for Mission Complete declaration after C4 succeeds (gated by C4 result) | Unlocks D1 (external green light) |

That is the **minimum**. Everything else is PRIME-owned technical execution given F1 access.

---

## What PRIME owns after F1

### Phase A: Staging environment validation (PRIME owns)
**A1**: PRIME applies r047-r050 migrations read-write against staging, verifies clean apply.
**A2**: PRIME runs the canonical pricing regression guard (migration 000010) against staging — must produce 6 NOTICE OK.
**A3**: PRIME runs r047 auto-assign + r048 timeout + r049 security migrations against staging — verifies no schema drift.

### Phase B: Operator session setup (PRIME owns given F1)
**B1**: PRIME recovers/creates an operator session for the Moukrim partner (`partners.is_hoofd=true`) using the Founder-mediated session recovery flow.
**B2**: PRIME recovers/creates an Ayoub-style dispatch recipient session.
**B3**: PRIME creates a customer session with at least one historical booking in staging.

### Phase C: Controlled E2E (PRIME owns)
**C1**: PRIME executes the booking lifecycle chain against staging: customer books → driver assigned → driver accepts → driver assigned → ride completed → review request → (optionally) cancellation/reassignment path. Captures Mailgun/Resend log + dispatch archive counts.
**C2**: PRIME exercises the timeout path against staging (assign booking, wait 30 min past assignment_sent_at, trigger scanner). Verifies `metadata.timeout_events[]` populated correctly with TIMEOUT_REASSIGN.
**C3**: PRIME verifies staging RLS policies against new RPC grants (anon/authenticated denied, service_role only).
**C4**: PRIME captures full audit trail + commits evidence; reports results to Lux with `LUX — SYNC NEEDED`.

### Phase D: External green light (Founder action — F2)
**D1**: Founder reviews staging audit trail + commits to canonical MISSION_REPORT.md acceptance.
**D2**: Founder confirms Campanile / Lorena / The Lodge operational partners are informed (external comms).
**D3**: Founder issues external green light to Lux for Mission Complete declaration.

---

## What PRIME cannot do without Founder

- ❌ Cannot create staging-equivalent environment (Founder has Supabase project permissions)
- ❌ Cannot recover operator sessions in production (Founder has account/password recovery permissions)
- ❌ Cannot issue external green light (Founder has external comms authority)
- ❌ Cannot perform production writes (Founder authorization required)

---

## What PRIME has already done without Founder

- ✅ 6/6 canonical pricing regression guard assertions pass (migration 000010 NOTICE OK)
- ✅ 5/5 Lux §3.1-3.5 pricing scenarios pass with literal input/output (L1 €15 Vilvoorde, L2 €15 Vilvoorde, L3 €35 ordinary, L4 €55 airport, L5a €25 Campanile fixed, L5b €30 reverse fixed, L5c €25 comma form)
- ✅ 13/13 mail regression matrix scenarios pass (T0 direct dedup + T0b + T1-T11)
- ✅ 7/7 timeout scenarios pass + TC1 multiple-consecutive (T1 Ahmed→Karim, T2 Karim, T3 cap_reached, T4 accepted never timed out, T5 not_yet_expired, T6 pending no action, T7 assigned never timed out)
- ✅ Security verified (anon/authenticated denied for timeout + auto-assignment mutators; service_role only)
- ✅ Direct sendOperationsCopy dedup branch proven (T0 returns reason `dispatch_already_in_primary_routing`)
- ✅ EXACT dispatch@fleetconnect.be equality verified (T10 malformed `.becom` not counted)
- ✅ All 8 reachable operational triggers covered (BOOKING_CONFIRMATION, DRIVER_ASSIGNMENT_REQUEST, DRIVER_ASSIGNED, DRIVER_REASSIGNED, DRIVER_DECLINED, BOOKING_CANCELLED, BOOKING_REJECTED, RIDE_COMPLETED_REVIEW_REQUEST)
- ✅ Ayoub/TO/CC intentional recipients preserved
- ✅ No `.com` platform identity drift
- ✅ Missing driver email → explicit failure (no Gmail fallback)
- ✅ Pricing genuine cases preserved (Campanile ↔ Brussels Airport contractual €25/€30)
- ✅ Deterministic driver selection (load-aware + stable id tie-break)
- ✅ Truthful TIMEOUT_REASSIGN audit events
- ✅ New Orders invariant preserved
- ✅ Exactly-once dispatch archive
- ✅ .be platform identity canonical
- ✅ WhatsApp drift fixed across 42 ride-support files

---

## Risk Assessment

### If Founder does NOT execute F1
- All Mission Complete criteria proven by isolated evidence only (not staging-verified)
- External green light cannot be issued (F2 cannot complete without F1)
- Mission remains in PARTIAL ACCEPT state
- Ayoub / Lorena / The Lodge operational continuity depends on isolated evidence
- Pricing contradiction (r050 €25 vs r047 €15) is RESOLVED as documented methodology error (r050 used wrong inputs)

### If Founder executes F1 (recommended)
- PRIME owns A1-A3, B1-B3, C1-C4 (technical execution after access)
- Founder owns only F1 (env setup) + F2 (final external green light)
- Mission Complete can be declared after C4 + F2 succeed
- Production-safe integration candidate ready for staging deployment
- All canonical Mission Complete criteria proven by runtime evidence against staging environment

---

## Note on F2 (Founder final green light)

F2 is the FINAL action after C4 + Lux review. It is intentionally separated because:
- F2 is IRREVERSIBLE (external comms to operational partners)
- F2 is gated by C4 staging audit success
- F2 is not a technical step PRIME can perform

If F1 is granted and C1-C4 succeed, F2 becomes a 5-minute Founder decision, not a 19-step project.

---

**CONCLUSION**: 14 Founder steps → **2 Founder actions**. The rest is PRIME-owned technical execution.

**Mission Complete cannot be declared autonomously.** Per Lux §5 + MISSION_REPORT.md, requires F1 + C1-C4 + F2.