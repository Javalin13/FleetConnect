# r050 Integration Candidate — Dedup Branch Test + Complete Operational Trigger Matrix

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Round**: r050
**Author**: PRIME
**Date**: 2026-08-30T15:00+02:00
**Base SHA**: `3c2dc16` (r049 head)
**Head SHA**: `pending` (this commit)
**Branch**: `integration-r050` (pushed to `Javalin13/FleetConnect`)

---

## TL;DR

r050 addresses **ALL FOUR Lux r049 corrections**:

1. ✅ **Dedup branch test repaired (Lux §3)**: direct `sendOperationsCopy()` call with `lastDispatchOptions.bcc` containing `dispatch@fleetconnect.be` proves ZERO additional ops send PLUS returned reason `dispatch_already_in_primary_routing`. **No longer flaky T8 that got overwritten by trigger routing.**
2. ✅ **Complete operational trigger matrix (Lux §4)**: ALL 8 reachable operational triggers tested. NEW coverage: `DRIVER_REASSIGNED` (via driver-accept reassignment), `BOOKING_CANCELLED` (operator cancel), `BOOKING_REJECTED` (operator reject), `RIDE_COMPLETED_REVIEW_REQUEST` (operator complete).
3. ✅ **EXACT dispatch equality (Lux §4)**: assertions use `.includes('dispatch@fleetconnect.be')` (exact), NOT substring `.includes('dispatch@fleetconnect')`. Malformed `.becom` not falsely counted.
4. ✅ **Mission status discipline (Lux §5)**: NO completion fraction published. Per MISSION_REPORT.md still OPEN regardless of isolated progress.

---

## 1. Trigger Topology (per Lux §4 enumeration)

### Operational ride lifecycle triggers (reachable from current source)

| Trigger | Reachable from | Class |
|---|---|---|
| `BOOKING_CONFIRMATION` | PV.html:1293, PV_en.html:859, PV_fr.html:892, klantenportaalpv.html:1130, b2b/webbooker.html:131 | Operational customer lifecycle |
| `DRIVER_ASSIGNMENT_REQUEST` | index.js:70 (auto-fired), Paneel/onderaannemerA.html:663,1431 | Operational driver lifecycle |
| `DRIVER_ASSIGNED` | driver-accept.html:90 (`notification_trigger` default) | Operational customer lifecycle |
| `DRIVER_REASSIGNED` | driver-accept.html:90 (`notification_trigger` when `v_is_reassignment=true`) | Operational customer lifecycle |
| `DRIVER_DECLINED` | driver-decline.html:90 (with `operationsOnly: true`) | Internal-only (no customer primary) |
| `BOOKING_CANCELLED` | Paneel/onderaannemerA.html:1429 | Operational customer lifecycle |
| `BOOKING_REJECTED` | Paneel/onderaannemerA.html:1427 | Operational customer lifecycle |
| `RIDE_COMPLETED_REVIEW_REQUEST` | Paneel/onderaannemerA.html:1430 | Operational customer lifecycle |

### Internal-only lifecycle triggers (no customer primary)

| Trigger | Reachable from |
|---|---|
| `BOOKING_ACCEPTED` | internalOnlyTriggers set (driver accepts) — NOT directly triggered in current source |
| `DRIVER_DECLINED` | internalOnlyTriggers set + explicit `operationsOnly:true` from driver-decline.html |

### Non-ride / account / technical (Founder doctrine does NOT apply per Lux §4)

| Trigger | Reachable from |
|---|---|
| `ACCOUNT_ONBOARDING` | NOT reachable |
| `CUSTOMER_REGISTRATION_CONFIRMATION` | NOT reachable |
| `ACCOUNT_WELCOME` | NOT reachable |
| `RIDE_COMPLETED` | NOT reachable (alias for BOOKING_COMPLETED only) |
| `BOOKING_COMPLETED` | NOT reachable (alias only) |
| `PAYMENT_REFUND_CONFIRMATION` | NOT reachable |

---

## 2. Direct Dedup Branch Proof (Lux §3)

### T0 — Direct sendOperationsCopy with dispatch in primary routing
```js
const result = await service.sendOperationsCopy(
    'BOOKING_CONFIRMATION',
    snap,  // lastDispatchOptions.bcc = ['dispatch@fleetconnect.be']
    'Test Subject', '<html>Test</html>',
    'customer@example.com', makeMockSupabase()
);
```

**Result**: dispatch_sends=0, skipped=true, reason=`dispatch_already_in_primary_routing`

### T0b — Direct sendOperationsCopy WITHOUT dispatch in primary routing
```js
const result = await service.sendOperationsCopy(
    'BOOKING_CONFIRMATION',
    snap,  // lastDispatchOptions.bcc = []
    'Test Subject', '<html>Test</html>',
    'customer@example.com', makeMockSupabase()
);
```

**Result**: dispatch_sends=1, success=true (no dedup, ops copy sent normally)

---

## 3. Mail Regression Matrix — 13/13 PASS

| # | Test | Result |
|---|---|---|
| T0 | Direct dedup branch proof | ✓ dispatch_sends=0, reason=dispatch_already_in_primary_routing |
| T0b | Direct sendOperationsCopy (no dedup) | ✓ dispatch_sends=1, success=true |
| T1 | BOOKING_CONFIRMATION | ✓ dispatch=1, preserved={customer@example.com, dispatch@fleetconnect.be} |
| T2 | DRIVER_ASSIGNMENT_REQUEST | ✓ dispatch=1, preserved={driver, ayoubgaddar05@gmail.com, fleetconnect.os@gmail.com, info@fleetconnect.com, dispatch@fleetconnect.be} |
| T3 | DRIVER_ASSIGNED | ✓ dispatch=1, preserved={customer, dispatch@fleetconnect.be} |
| T4 | DRIVER_REASSIGNED (NEW) | ✓ dispatch=1, preserved={customer, dispatch@fleetconnect.be} |
| T5 | DRIVER_DECLINED (operationsOnly) | ✓ dispatch=1, preserved={dispatch@fleetconnect.be} |
| T6 | BOOKING_CANCELLED (NEW) | ✓ dispatch=1, preserved={customer, dispatch@fleetconnect.be} |
| T7 | BOOKING_REJECTED (NEW) | ✓ dispatch=1, preserved={customer, dispatch@fleetconnect.be} |
| T8 | RIDE_COMPLETED_REVIEW_REQUEST (NEW) | ✓ dispatch=1, preserved={customer, dispatch@fleetconnect.be} |
| T9 | missing driver email | ✓ explicit failure (success=false), no Gmail fallback |
| T10 | EXACT dispatch equality (not substring) | ✓ initial=0 final=1 (malformed `.becom` not counted) |
| T11 | no .com platform identity drift | ✓ hasComDrift=false |

---

## 4. Timeout + Security Regression — re-verified

### Timeout (T1-T7 + TC1 from r049)
- T1: Ahmed → Karim (different driver) ✓
- T2: no_eligible_driver (all unavailable) ✓
- T3: cap_reached (count=3, no action) ✓
- T4: accepted (status=accepted, NEVER timed out) ✓
- T5: not_yet_expired (29 min, no action) ✓
- T6: not_in_assignment_sent (pending, no action) ✓
- T7: assigned (status=assigned, NEVER timed out) ✓

### Security
- anon: DENIED ✓
- authenticated: DENIED ✓
- service_role: executes ✓

### Pricing (re-verified)
- L1: Luchthavenlaan 18 Vilvoorde → Vilvoorde Centrum → route=Vilvoorde, €25 ✓
- Brussels Airport → Campanile Vilvoorde → route=Luchthaven ✓
- Non-Campanile Luchthavenlaan 27 → Brussels Airport → route=Luchthaven ✓

---

## 5. Protected B2/B3 Execution Checklist

See `evidence/protected-b2-b3-execution-checklist.md` for full enumeration of Founder-mediated environment setup, operator session recovery, controlled E2E execution, and external green light.

**Summary**: 19 steps across 4 phases (A: staging setup, B: operator sessions, C: controlled E2E, D: external green light). 14 steps require Founder action; 5 steps PRIME can execute given Founder-provided access.

---

## 6. Files changed in r050

### Added
- `evidence/mail-regression-harness-r050.mjs` (328 lines — 13/13 test scenarios)
- `evidence/protected-b2-b3-execution-checklist.md` (Founder-mediated B2/B3 checklist)
- `evidence/r050-dedup-and-complete-matrix-evidence.md` (this file)

### No code changes
- r050 is a test-coverage + documentation round
- All r047/r048/r049 fixes preserved unchanged

### Base + Head SHAs
- Base: `3c2dc16` (r049 head)
- Head: `pending` (this commit)
- Branch: `integration-r050` (pushed to `Javalin13/FleetConnect`)

---

## 7. Mission Complete Status (no fraction per Lux §5)

Per `MISSION_REPORT.md`, **canonical Mission Complete** requires (per Lux §5):
- protected B2 live Supabase/runtime parity — **OPEN** (Founder-mediated staging required)
- protected B3 controlled UI/auth booking lifecycle — **OPEN** (Founder-mediated environment required)
- correct customer ETA/contact proof in real lifecycle — **OPEN**
- portal/New Orders/Orders/history coherence in runtime — **OPEN**
- repeated consecutive controlled production-like/live scenarios — **OPEN** (canonical E2E means booking-to-completion chain)
- no known critical defect open — **NO KNOWN CRITICAL DEFECT** per r050 13/13 pass
- final independent PRIME + Lux review of final evidence — **OPEN** (awaiting Lux r050 review)
- safe external green light for Campanile/Lorena and The Lodge — **OPEN**

Mission Complete requires Founder action on B2/B3 per the checklist. PRIME cannot declare Mission Complete autonomously.

---

## 8. OPEN / FLAGGED

- [LUX REVIEW NEEDED] r050 dedup branch proof (T0 direct sendOperationsCopy call)
- [LUX REVIEW NEEDED] r050 extended mail matrix 13/13 (T4 DRIVER_REASSIGNED, T6 BOOKING_CANCELLED, T7 BOOKING_REJECTED, T8 RIDE_COMPLETED_REVIEW_REQUEST)
- [LUX REVIEW NEEDED] r050 EXACT dispatch@fleetconnect.be equality (not substring)
- [LUX REVIEW NEEDED] r050 protected B2/B3 execution checklist
- [PROVEN] 13/13 mail matrix scenarios pass (isolated mock execution)
- [PROVEN] Direct sendOperationsCopy dedup branch proven (T0)
- [PROVEN] EXACT dispatch equality (T10)
- [PROVEN] No .com drift (T11)
- [PROVEN] Timeout T1-T7 + TC1 re-verified
- [PROVEN] SECURITY re-verified (anon/authenticated denied)
- [PROVEN] Pricing re-verified (L1 Vilvoorde €25 + airport cases preserved)
- [PARKED] Founder-mediated B2/B3 execution per checklist
- [PARKED] Final Lux review (awaiting this PR)
- Mission remains ACTIVE; Mission Complete requires Founder-mediated B2/B3 execution + external green light per Lux §5