# r051 Integration Candidate — Pricing Contradiction Resolved + Minimum Founder Burden Refined

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Round**: r051
**Author**: PRIME
**Date**: 2026-08-30T15:30+02:00
**Base SHA**: `afe5435` (r050 head)
**Head SHA**: `pending` (this commit)
**Branch**: `integration-r051` (pushed to `Javalin13/FleetConnect`)

---

## TL;DR

r051 resolves the **CRITICAL pricing contradiction** flagged by Lux r050 §3 and refines the B2/B3 checklist per Lux §5 minimum Founder burden.

**Resolution finding**: The runtime IS correct (returns €15 canonical for Luchthavenlaan 18 → Vilvoorde Centrum). The r050 evidence was a **methodology error**: r050 ran `calculate_booking_fare_fixed(10, 'Luchthavenlaan 18 Vilvoorde', 'Vilvoorde Centrum', false)` (4 args, distance 10km, no partner_id) instead of the canonical regression guard pattern `calculate_booking_fare(3, 'luchthavenlaan 18, vilvoorde', 'vilvoorde centrum', false, 1)` (5 args, distance 3km, partner_id=1). The €25 in r050 was the legitimate metered fare for 10km × 2 + 5 base = €25, NOT a regression.

**5/5 Lux §3 scenarios PASS** with literal input/output. Migration 000010 regression guard produces 6 NOTICE OK. NO pricing regression introduced.

**B2/B3 refined per Lux §5**: 14 Founder steps → **2 Founder actions** (F1: staging env, F2: external green light). Everything else is PRIME-owned.

---

## 1. Pricing Contradiction Resolution (Lux §3)

### Root cause analysis

The r050 evidence reported `Luchthavenlaan 18 Vilvoorde → Vilvoorde Centrum = €25`. The r047 canonical accepted guard requires `€15`. The literal r050 SQL call was:

```sql
-- r050 (WRONG inputs)
SELECT * FROM public.calculate_booking_fare_fixed(
    10,                          -- distance_km: 10 (BUG: should be 3)
    'Luchthavenlaan 18 Vilvoorde', -- pickup: missing ', 1800' (BUG: should be 'luchthavenlaan 18, 1800 vilvoorde')
    'Vilvoorde Centrum',         -- dropoff (case mismatch vs canonical lowercase)
    false
);                              -- MISSING partner_id arg (canonical: 1)
```

With these inputs:
- distance 10km × 2 = €20 + 5 base = €25 (metered fare)
- route_name inferred as 'Vilvoorde' (because 'vilvoorde' in pickup string)
- applicable_min_fare = €15 (default for partner_id=null falls back to id=1)
- total_amount = €25 (metered €25 > Vilvoorde min €15, so min NOT applied)

The €25 result was mathematically correct for those inputs but the inputs did NOT match the canonical regression guard pattern. The r047 migration 000010 regression guard signature is:

```sql
SELECT public.calculate_booking_fare(
    3,                          -- distance_km: 3 (local Vilvoorde)
    'luchthavenlaan 18, vilvoorde', -- pickup: lowercase + ', ' + lowercase
    'vilvoorde centrum',        -- dropoff: lowercase
    false,
    1                           -- partner_id: 1 (default)
);
```

Which returns:
```json
{"raw_amount": 11, "route_name": "Vilvoorde", "distance_km": 3, "total_amount": 15, "is_fixed_route": false, "minimum_applied": true, "applicable_min_fare": 15}
```

€15 minimum IS applied because metered 11 < min 15.

### All 5 Lux §3 scenarios with literal input/output

| # | Scenario | Input | Output | Expected |
|---|---|---|---|---|
| §3.1 | Luchthavenlaan 18 → Vilvoorde Centrum | `(3, 'luchthavenlaan 18, 1800 vilvoorde', 'vilvoorde centrum', false, 1)` | `route=Vilvoorde, total=€15, min_applied=true, applicable_min=15` | €15 ✓ |
| §3.2 | Luchthavenlaan 27 → Vilvoorde Centrum | `(3, 'luchthavenlaan 27, 1800 vilvoorde', 'vilvoorde centrum', false, 1)` | `route=Vilvoorde, total=€15, min_applied=true, applicable_min=15` | €15 ✓ |
| §3.3 | Luchthavenlaan 18 → Mechelen | `(15, 'luchthavenlaan 18, 1800 vilvoorde', 'mechelen centrum', false, 1)` | `route=Vilvoorde, total=€35, min_applied=false, applicable_min=15` | NOT Luchthaven ✓ |
| §3.4 | Brussels Airport → Mechelen | `(25, 'brussels airport', 'mechelen centrum', false, 1)` | `route=Luchthaven, total=€55, min_applied=false, applicable_min=30` | Airport preserved ✓ |
| §3.5a | Campanile (no-comma) → Brussels Airport | `(15, 'luchthavenlaan 2 1800 vilvoorde', 'brussels airport', false, 1)` | `fixed_route=true, total=€25.00, route=Campanile Vilvoorde ⇄ Brussels Airport` | €25 ✓ |
| §3.5b | Brussels Airport → Campanile | `(15, 'brussels airport', 'luchthavenlaan 2 1800 vilvoorde', false, 1)` | `fixed_route=true, total=€30.00, route=Brussels Airport ⇄ Campanile Vilvoorde` | €30 reverse ✓ |
| §3.5c | Campanile (with-comma) → Brussels Airport | `(15, 'luchthavenlaan 2, 1800 vilvoorde', 'brussels airport', false, 1)` | `fixed_route=true, total=€25.00, route=Campanile Vilvoorde ⇄ Brussels Airport` | €25 multi-pattern ✓ |

### Migration 000010 regression guard — all 6 assertions PASS

```
NOTICE: Regression guard OK: 0 rows use unanchored %luchthavenlaan 2% pattern
NOTICE: Regression guard OK: 8 rows with anchored patterns (covers both canonical address forms)
NOTICE: Regression guard OK: Luchthavenlaan 18 Vilvoorde -> Vilvoorde Centrum = Vilvoorde route, min €15 (was: Luchthaven/€30 BEFORE r047 fix)
NOTICE: Regression guard OK: Luchthavenlaan 18 Vilvoorde -> Mechelen = Vilvoorde route (NOT Luchthaven)
NOTICE: Regression guard OK: Campanile no-comma form (luchthavenlaan 2 1800 vilvoorde) -> Brussels Airport = €25 fixed
NOTICE: Regression guard OK: Luchthavenlaan 27 -> Brussels Airport NOT a fixed route (variable pricing)
```

---

## 2. Mail + Timeout + Security smoke regressions (per Lux §7.5)

### Mail regression — 13/13 PASS
(T0 direct dedup + T0b + T1-T11 — verified via `nodejs run.mjs` against isolated harness)

### Timeout — 7/7 PASS + TC1

| Scenario | Result |
|---|---|
| T1 Ahmed → Yassine (40min past) | `assigned`, driver=Yassine, TIMEOUT_REASSIGN, audit_event_count=1 ✓ |
| T2 All-Busy → Karim (40min past) | `assigned`, driver=Karim, TIMEOUT_REASSIGN, audit_event_count=1 ✓ |
| T3 At-Cap (reassignment_count=3) | `cap_reached`, no action ✓ |
| T4 accepted (5min ago) | `not_in_assignment_sent, current_status=accepted` (NEVER timed out) ✓ |
| T5 not_yet_expired (29min past) | `not_yet_expired` (under 30min window) ✓ |
| T6 pending (no assignment_sent) | `not_in_assignment_sent, current_status=pending` ✓ |
| T7 assigned (no accepted_at) | `not_in_assignment_sent, current_status=assigned` ✓ |

### Security — verified

| Role | timeout_expired_assignment |
|---|---|
| anon | DENIED ✓ |
| authenticated | DENIED ✓ |
| service_role | executes successfully ✓ |

---

## 3. B2/B3 Minimum Founder Burden (Lux §5)

Per Lux §5: "do not turn environment limitations into 14 separate Founder tasks if one legitimate access/setup action can unlock several checks."

**Refined from 14 Founder steps to 2 Founder actions**:

| # | Action | Unlocks |
|---|---|---|
| **F1** | Founder creates/provisions staging-equivalent environment + provides URL/anon-key for it via secure channel | Unlocks A1-A3 (B2), B1-B3 (sessions), C1-C4 (E2E) |
| **F2** | Founder issues external green light to Lux for Mission Complete declaration after C4 succeeds | Unlocks D1-D3 (final) |

**Everything else (A1-C4) is PRIME-owned technical execution given F1 access.**

See `evidence/protected-b2-b3-execution-checklist-minimum.md` for full enumeration.

---

## 4. Mission Complete Status (no fraction per Lux §5)

Per `MISSION_REPORT.md`, **canonical Mission Complete** requires:
- protected B2 live runtime/schema parity — **OPEN** (Founder F1 staging env required)
- protected B3 controlled UI/auth booking lifecycle — **OPEN** (Founder F1 + PRIME C1-C4)
- correct customer ETA/contact proof in real lifecycle — **OPEN**
- portal/New Orders/Orders/history coherence in runtime — **OPEN**
- repeated consecutive controlled booking-to-completion E2Es — **OPEN**
- no known critical defect remaining (pricing contradiction now RESOLVED) — **NO KNOWN CRITICAL DEFECT** per r051 verification
- final independent PRIME + Lux review of final evidence — **OPEN** (awaiting Lux r051 review)
- safe external green light for Campanile/Lorena and The Lodge — **OPEN** (Founder F2)

Mission Complete requires F1 + C1-C4 + F2. PRIME cannot declare autonomously.

---

## 5. Files changed in r051

### Added
- `evidence/protected-b2-b3-execution-checklist-minimum.md` (14 Founder steps → 2 Founder actions)
- `evidence/r051-pricing-resolution-and-minimum-burden-evidence.md` (this file)

### No code changes
- r051 is a verification + documentation round
- All r047-r050 fixes preserved unchanged

### Base + Head SHAs
- Base: `afe5435` (r050 head)
- Head: `pending` (this commit)
- Branch: `integration-r051` (pushed to `Javalin13/FleetConnect`)

---

## 6. OPEN / FLAGGED

- [LUX REVIEW NEEDED] r051 pricing contradiction resolution (Lux §3)
- [LUX REVIEW NEEDED] r051 minimum Founder burden B2/B3 checklist (Lux §5)
- [PROVEN] 5/5 Lux §3 pricing scenarios pass with literal input/output
- [PROVEN] 6/6 migration 000010 regression guard assertions pass
- [PROVEN] 13/13 mail regression matrix scenarios pass
- [PROVEN] 7/7 timeout scenarios pass (with TC1)
- [PROVEN] SECURITY re-verified (anon/authenticated denied)
- [DOCUMENTED] r050 pricing evidence was methodology error (wrong inputs), not regression
- [PARKED] Founder F1 (staging env access) + F2 (external green light)
- [PARKED] Final Lux review (awaiting this PR)
- Mission remains ACTIVE; Mission Complete requires F1 + C1-C4 + F2