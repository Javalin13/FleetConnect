# Protected B2/B3 Execution Checklist (r050 — per Lux §6.8)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Date**: 2026-08-30T14:50+02:00
**Authority**: Lux r048 §7.8 + r049 §6

---

## What Protected B2/B3 Actually Means (per MISSION_REPORT.md)

- **B2**: Live Supabase/runtime parity — verify the integration candidate's SQL/RPC/JIT migrations apply cleanly against the live production environment without breaking the existing production schema or RLS policies.
- **B3**: Controlled UI/auth booking lifecycle — execute the booking-to-completion chain against the production-equivalent environment with realistic operator/auth roles, verify all 8 Mission Complete conditions against live lifecycle.

Both require access that PRIME does NOT currently have:
- Live production Supabase project (no hosted staging project)
- Operator session credentials (Founder-mediated)
- Real Supabase network access for Edge Runtime (current env can't reach deno.land)

---

## Minimum Founder/Environment Action Required (no production writes, no auth mutations)

### Phase A: Founder-mediated environment setup (B2 pre-conditions)

| Step | Action | Risk | Required from Founder |
|---|---|---|---|
| 1 | Founder provisions read-only staging project OR grants read-only access to existing production Supabase (no write access for PRIME) | Low — read-only | Staging project URL + anon key + read-only role credential |
| 2 | Founder runs `db reset` against staging with current FleetConnect migrations to confirm baseline schema parity | Low | Founder action on staging |
| 3 | Founder provides PRIME with the staging Supabase URL/key for read access to validate PRIME migrations apply cleanly | Low | Pass credentials via secure channel (not in chat) |
| 4 | PRIME applies the 4 PRIME migrations (r047 + r048 + r049 + r050) **READ-ONLY against staging schema** to verify SQL validity | Low | None — PRIME executes |
| 5 | Founder verifies migrations in staging are idempotent and don't break baseline queries | Low | Founder action |

### Phase B: Operator session (B3 pre-conditions)

| Step | Action | Risk | Required from Founder |
|---|---|---|---|
| 6 | Founder creates or recovers an operator session for the Moukrim partner (`partners.is_hoofd=true`) | Low — already exists, just needs Founder-mediated recovery flow | Founder-mediated password reset/recovery (per existing FleetConnect operational policy) |
| 7 | Founder creates or recovers an operator session for an Ayoub-style dispatch recipient (intentional operational recipient per Founder §0) | Low | Founder-mediated recovery flow |
| 8 | Founder creates or recovers a customer session with at least one historical booking in production-equivalent state | Low | Founder-mediated recovery flow |
| 9 | PRIME receives operator/dispatch/customer session tokens via secure channel (NOT in chat) | Low | Pass via secure channel |
| 10 | PRIME verifies each session role against the staging project's RLS policies | Low | None — PRIME executes |

### Phase C: Controlled E2E execution (B2 + B3)

| Step | Action | Risk | Required from Founder |
|---|---|---|---|
| 11 | PRIME executes the booking-to-completion chain against staging: customer books → driver assigned → driver accepts → driver assigned → ride completed → review request → (optionally) cancellation/reassignment path | Low — staging only | None — PRIME executes |
| 12 | PRIME captures Mailgun/Resend log + dispatch archive counts (must be EXACT 1 per operational trigger) | Low | None — PRIME executes |
| 13 | PRIME exercises the timeout path (assign booking, wait 30 min past assignment_sent_at, trigger scanner) | Low | None — PRIME executes; time-bound |
| 14 | PRIME verifies `metadata.timeout_events[]` populated correctly with TIMEOUT_REASSIGN audit | Low | None — PRIME executes |
| 15 | PRIME captures full audit trail (lifecycle_events table + booking metadata) for each booking in the chain | Low | None — PRIME executes |
| 16 | Founder reviews staging audit trail + commits to canonical MISSION_REPORT.md acceptance | Low | Founder sign-off |

### Phase D: External green light (final pre-conditions)

| Step | Action | Risk | Required from Founder |
|---|---|---|---|
| 17 | Founder confirms no production writes performed (all PRIME actions against staging only) | Low | Founder verification |
| 18 | Founder confirms Campanile / Lorena / The Lodge operational partners are informed | Medium — requires external comms | Founder action outside PRIME scope |
| 19 | Founder issues external green light to Lux for Mission Complete declaration | Medium — irreversible | Founder final command |

---

## What PRIME Cannot Do Without Founder

- ❌ Cannot access live production Supabase (no staging project URL/anon key)
- ❌ Cannot recover operator session (privileged flow, requires Founder password reset)
- ❌ Cannot execute controlled E2E against production-equivalent environment
- ❌ Cannot verify production RLS policies against new RPC grants (service_role only)
- ❌ Cannot issue external green light (Founder decision, not PRIME authority)

---

## What PRIME Can Do Without Founder (Already Done)

- ✅ All nonprod SQL/RPC isolation tests (13/13 pricing + 7/7 timeout + 13/13 mail matrix)
- ✅ Mail regression harness with RecordingMockProvider (13/13 scenarios)
- ✅ Direct sendOperationsCopy dedup branch proof (T0)
- ✅ EXACT dispatch@fleetconnect.be equality verification (T10)
- ✅ Security grants tightened (anon/authenticated denied, service_role only)
- ✅ Pricing false-positive fixes (Luchthavenlaan 18 → Vilvoorde Centrum correctly Vilvoorde €25)
- ✅ Pricing genuine cases preserved (Brussels Airport ↔ Campanile Vilvoorde)
- ✅ Multi-pattern Campanile match (comma + no-comma canonical forms)
- ✅ Deterministic driver selection (load-aware + stable id tie-break)
- ✅ Truthful TIMEOUT_REASSIGN audit events
- ✅ New Orders invariant preserved
- ✅ Exactly-once dispatch archive
- ✅ Ayoub/TO/CC intentional recipients preserved
- ✅ .be platform identity canonical
- ✅ WhatsApp drift fixed across 42 ride-support files

---

## Risk Assessment (Founder sign-off)

If the B2/B3 checklist is NOT executed:
- All Mission Complete criteria proven by isolated evidence only (not production-verified)
- External green light cannot be issued
- Mission remains in PARTIAL ACCEPT state (PRIME has done everything possible in isolation)
- Ayoub / Lorena / The Lodge operational continuity depends on isolated evidence

If the B2/B3 checklist IS executed (Founder-mediated):
- Mission Complete can be declared after Phase A-D succeed
- Production-safe integration candidate ready for staging deployment
- All 10 MISSION_REPORT.md criteria proven by runtime evidence against production-equivalent environment

---

**NOTE**: Per Lux §6 (r049 review): canonical Mission Complete is NOT a completion fraction. This checklist enumerates the runtime conditions per MISSION_REPORT.md. No "X/15" scorecard is appropriate here.