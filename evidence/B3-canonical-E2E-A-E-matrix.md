# Protected B3 Canonical E2E Matrix (r052, per Lux r051 §4)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Date**: 2026-08-30T16:15+02:00
**Authority**: Lux r051 §4 (canonical booking-to-completion Definition of Done)

---

## Required E2E Scenarios (per Lux r051 §4)

Lux r051 §4 explicitly states: "Canonical Mission Complete requires these flows to be PROVEN, not merely available."

The protected B3 matrix must include **separate controlled scenarios** for:

---

## E2E-A — Normal Ride

**Scenario**: A complete successful booking-to-completion lifecycle with no exceptions.

### Steps
| # | Step | Expected |
|---|---|---|
| A.1 | Customer creates booking via `create_public_booking` RPC with Campanile address (e.g. `Luchthavenlaan 2 1800 Vilvoorde` → Brussels Airport) | Booking created with `status=pending` |
| A.2 | Pricing RPC returns `is_fixed_route=true, total_amount=25.00, route_name='Campanile Vilvoorde ⇄ Brussels Airport'` | Fixed route €25 ✓ |
| A.3 | Booking appears in New Orders (operator-visible recoverable state) | Visible in portal ✓ |
| A.4 | `auto_assign_pending_bookings` runs → selects deterministic driver (Moukrim partner's load-balanced driver) | `status=assignment_sent`, `assigned_driver_id` set |
| A.5 | DRIVER_ASSIGNMENT_REQUEST email fires with EXACTLY ONE dispatch archive copy to `dispatch@fleetconnect.be` | 1 send, recipients preserved (Ayoub + intentional TO/CC) |
| A.6 | Driver accepts via `driver_accept_assignment` RPC | `status=accepted`, `assignment_accepted_at` set |
| A.7 | DRIVER_ASSIGNED email fires with EXACTLY ONE dispatch archive | 1 send, customer receives + dispatch archive |
| A.8 | Customer portal reflects `accepted` state with correct ETA/contact info | Portal correct ✓ |
| A.9 | Operator marks ride complete via `mark_ride_completed` RPC | `status=completed` |
| A.10 | RIDE_COMPLETED_REVIEW_REQUEST email fires with EXACTLY ONE dispatch archive | 1 send, customer receives + dispatch archive |
| A.11 | Booking history shows complete lifecycle: pending → assignment_sent → accepted → completed | History complete ✓ |

### Acceptance
All 11 steps pass with isolated evidence + captured runtime outputs.

---

## E2E-B — Decline / Reassignment

**Scenario**: Driver declines assignment; truthful reassignment state remains in New Orders; different eligible driver picks up.

### Steps
| # | Step | Expected |
|---|---|---|
| B.1 | Customer creates booking (local Vilvoorde non-airport) | `status=pending` |
| B.2 | Pricing returns `route_name=Vilvoorde, applicable_min_fare=15, total_amount=15` (3km metered 11 < min 15 → min applied) | Vilvoorde €15 ✓ |
| B.3 | `auto_assign_pending_bookings` → first driver (Ahmed) | `status=assignment_sent`, driver=Ahmed |
| B.4 | DRIVER_ASSIGNMENT_REQUEST fires, 1 dispatch archive | ✓ |
| B.5 | Driver declines via `driver_decline_assignment` RPC → updates `metadata.excluded_driver_id`, sets `status=reassignment_needed` | Recoverable state in New Orders ✓ |
| B.6 | DRIVER_DECLINED email fires (internalOnly, dispatch archive only) | 1 send, dispatch only |
| B.7 | `auto_assign_pending_bookings` (or `assign_pending_booking_to_driver`) picks a DIFFERENT eligible driver (NOT Ahmed) | Different driver (e.g. Karim) |
| B.8 | DRIVER_ASSIGNMENT_REQUEST fires again, 1 dispatch archive | ✓ |
| B.9 | Driver accepts → `status=accepted` | ✓ |
| B.10 | Customer portal reflects new driver + correct ETA/contact | ✓ |
| B.11 | Operator completes ride; history shows full reassignment cycle | ✓ |

### Acceptance
All 11 steps pass with truthful `metadata.excluded_driver_id` audit, no fake driver assignment.

---

## E2E-C — Timeout / Reassignment

**Scenario**: Driver doesn't accept within 30 minutes; timed-out driver excluded; reassignment or truthful no-driver path; audit metadata preserved.

### Steps
| # | Step | Expected |
|---|---|---|
| C.1 | Customer creates booking | `status=pending` |
| C.2 | Auto-assigned to driver X | `status=assignment_sent` |
| C.3 | DRIVER_ASSIGNMENT_REQUEST fires, 1 dispatch archive | ✓ |
| C.4 | Wait >30 min past `assignment_sent_at` (in test: backdate via fixture) | Time elapses |
| C.5 | `timeout_expired_assignment(p_booking_id, p_now)` runs | Different eligible driver (Y) OR truthful `no_eligible_driver` |
| C.6 | `metadata.timeout_events[]` populated with `{at, event: TIMEOUT_REASSIGN, from_driver_id: X, to_driver_id: Y}` | Audit preserved ✓ |
| C.7 | `status=assignment_sent` (if reassigned) OR `status=reassignment_needed` (if no driver) | Correct ✓ |
| C.8 | Driver Y accepts → `status=accepted` | ✓ |
| C.9 | DRIVER_ASSIGNED fires, 1 dispatch archive | ✓ |
| C.10 | Operator completes ride; history includes TIMEOUT_REASSIGN event | ✓ |

### Acceptance
All 10 steps pass with truthful `timeout_events` audit, correct excluded-driver behavior, cap respected.

---

## E2E-D — No Eligible Driver / Cap Reached

**Scenario**: Booking cannot be auto-assigned (no eligible driver or cap reached); no lost booking, no fake driver, no loop; operator-visible recoverable state.

### Steps
| # | Step | Expected |
|---|---|---|
| D.1 | Customer creates booking | `status=pending` |
| D.2 | All drivers `is_available_now=false` (fixture: set before timeout) | No eligible driver |
| D.3 | `auto_assign_pending_bookings` runs | Truthful `no_eligible_driver` (NOT fake assignment) |
| D.4 | `status=reassignment_needed`, `assigned_driver_id=NULL`, `metadata.no_eligible_driver_reason='no_driver_passed_eligibility_filters'` | Recoverable ✓ |
| D.5 | Booking visible in New Orders as recoverable | Operator can manually intervene ✓ |
| D.6 | Operator manually assigns driver | `status=assignment_sent` |
| D.7 | DRIVER_ASSIGNMENT_REQUEST fires, 1 dispatch archive | ✓ |
| D.8 | Driver accepts → completion | ✓ |
| D.9 | Cap-reached variant: previous reassignment_count=3, `timeout_expired_assignment` returns `cap_reached` (no action) | ✓ |

### Acceptance
No fake driver assignment; truthful no-driver state; operator-visible recoverable state in New Orders.

---

## E2E-E — Cancellation / Rejection

**Scenario**: Operator cancels booking or rejects booking; portal/history/mail coherence preserved.

### Steps
| # | Step | Expected |
|---|---|---|
| E.1 | Customer creates booking | `status=pending` |
| E.2 | Operator cancels via Paneel/onderaannemerA.html:1429 → fires `BOOKING_CANCELLED` trigger | ✓ |
| E.3 | BOOKING_CANCELLED email fires, 1 dispatch archive | ✓ |
| E.4 | `status=cancelled` in booking + portal | ✓ |
| E.5 | Booking history shows cancellation | ✓ |
| E.6 | OR operator rejects via Paneel/onderaannemerA.html:1427 → fires `BOOKING_REJECTED` trigger | ✓ |
| E.7 | BOOKING_REJECTED email fires, 1 dispatch archive | ✓ |
| E.8 | `status=rejected` in booking + portal | ✓ |
| E.9 | Booking history shows rejection | ✓ |

### Acceptance
Cancellation/rejection reachable + portal/history/mail coherence proven + 1 dispatch archive each.

---

## Pricing Coverage Across E2Es

Per Lux r051 §4: "Pricing coverage inside these runs must include representative Campanile AND The Lodge/local Vilvoorde paths, not only synthetic generic addresses."

| E2E | Pricing scenario | Expected |
|---|---|---|
| A | Campanile ↔ Brussels Airport (contractual fixed €25/€30) | is_fixed_route=true ✓ |
| B | Local Vilvoorde non-airport | route=Vilvoorde, €15 ✓ |
| C | Local Vilvoorde non-airport | route=Vilvoorde, €15 ✓ |
| D | Local Vilvoorde (no driver case) | pricing per B ✓ |
| E | Any of above | per scenario ✓ |

If pricing varies, include a The Lodge specific scenario (representative third partner).

---

## Multiple Consecutive Controlled E2Es

Per Lux r051 §4: "Multiple consecutive controlled E2Es means multiple complete booking lifecycle scenarios, not repeated SQL/unit calls."

After F1 staging access, PRIME executes:
- 1× E2E-A
- 1× E2E-B
- 2× E2E-C (to verify timeout/reassignment across drivers)
- 1× E2E-D
- 1× E2E-E

= **6 complete booking lifecycle scenarios**, each isolated + auditable.

---

## Sessions Required (per Lux r051 §6)

Use ONLY roles actually required by current application topology:

| Role | Where needed |
|---|---|
| Customer | E2E-A, B, C, D, E (booking creation via `create_public_booking` + portal view) |
| Driver | E2E-A, B, C (accept/decline via `driver_accept_assignment`/`driver_decline_assignment`) |
| Operator/head-partner | E2E-D, E (manual assignment / cancel/reject via Paneel) |

**Do NOT create**:
- Ayoub session (Ayoub is an email recipient, NOT a UI login)
- Any production identity in staging
- Any unnecessary disposable test identity beyond what the E2E actually uses

---

## What PRIME Cannot Test Without F1

E2E-A through E2E-D require:
- ✅ C2 (privileged mutator execution) for `auto_assign_pending_bookings`, `timeout_expired_assignment`
- ✅ C1 (anon access) for `create_public_booking`, mail regression
- ✅ C3 (real-role JWT) for driver accept/decline, operator manual actions, customer portal auth

PRIME has already proven E2E-A through E2E-D equivalent SQL/RPC/JS isolated evidence in:
- r047 (auto-assign lifecycle)
- r048 (timeout scanner + exactly-once dispatch)
- r049 (JS dedup + security grants)
- r050 (mail matrix)
- r051 (pricing)
- r052 (clean timeout matrix — this round)

The protected B3 E2E-A-E in staging would re-prove the same flows against production-equivalent environment, with real-role JWTs and real mail capture, NOT just isolated mock execution.

---

## Acceptance

E2E-A through E2E-E are PROVEN only when PRIME has captured runtime evidence for each scenario in staging, including:
- Mail log shows exactly 1 dispatch archive per operational trigger
- Audit metadata contains truthful lifecycle events (TIMEOUT_REASSIGN, EXCLUDED_DRIVER, etc.)
- Portal/history reflects correct state transitions
- No fake driver assignment (verified via `assigned_driver_id IS NOT NULL` only when genuine assignment happened)
- Pricing returns correct route_name + amount per Lux §3 canonical inputs
- Mail captures show EXACT dispatch@fleetconnect.be equality (not substring)
- All bookings eventually reach a terminal state (completed, cancelled, rejected) — no orphan bookings

Once E2E-A through E2E-E pass in staging, the canonical Mission Complete conditions are PROVEN, and Lux can declare Mission Complete when it is safe to tell Campanile/Lorena/The Lodge FleetConnect is operational again.
