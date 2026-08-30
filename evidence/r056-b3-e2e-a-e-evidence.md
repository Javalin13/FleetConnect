# r056 Phase A — B3 E2E-A-E protected execution (reliability-first per Lux §2)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Round**: r056
**Date**: 2026-08-30T18:30+02:00
**Branch**: `integration-r056`
**Base SHA**: `4cd308e` (r055 head)

---

## Why Phase A first (per Lux r056 §2)

> "Do not let the large cleanup batch run ahead of the operational recovery proof in a way that makes root-cause analysis harder."

Lux r056 review explicitly directed reliability-first sequencing: B3 E2E-A–E in isolated/protected environment BEFORE broad cleanup runs ahead. Phase A executes this directive.

---

## Phase A — B3 E2E-A–E + pricing scenarios (5/5 + 6/6 PASS)

### E2E-A — Normal Ride (canonical happy path)

**File**: `evidence/r056-b3-e2e-a-e/e2e_a_normal_ride_v2.sql`

| Step | Result |
|---|---|
| Booking insert (Vilvoorde local €15) | ✅ `metadata.price = 15` |
| Auto-assign (`assign_pending_booking_to_driver`) | ✅ `status=assignment_sent, driver=Ahmed (11111111-...)` |
| Driver accept (status transition to `assigned`/`accepted`) | ✅ |
| Complete (`status='completed'`) | ✅ |
| Lifecycle events (ASSIGNMENT_ACCEPTED, COMPLETED) | ✅ both recorded |
| History contains booking | ✅ `status=completed` |

### E2E-B — Decline → Different Driver

**File**: `evidence/r056-b3-e2e-a-e/e2e_b_decline.sql`

| Step | Result |
|---|---|
| First assignment | ✅ `driver=Ahmed (11111111-...)` |
| Driver declines (status=reassignment_needed + declined_driver_id in metadata) | ✅ |
| Reassign | ✅ `driver=Yassine (33333333-...)` (DIFFERENT from Ahmed) |

### E2E-C — Timeout → Reassignment

**File**: `evidence/r056-b3-e2e-a-e/e2e_c_timeout.sql`

| Step | Result |
|---|---|
| Initial assign (Ahmed) | ✅ |
| Backdate `assignment_sent_at` to 31 min ago | ✅ |
| Run `scan_and_timeout_expired_assignments(now())` | ✅ `total_expired=1, no_eligible_driver=0, reassigned_to_different_driver=1` |
| Booking reassigned (Ahmed → Karim) | ✅ |
| TIMEOUT_REASSIGN lifecycle event | ✅ recorded |

### E2E-D — No Eligible Driver

**File**: `evidence/r056-b3-e2e-a-e/e2e_d_no_driver.sql`

| Step | Result |
|---|---|
| All drivers `is_available_now = false` | ✅ |
| Assign attempt | ✅ `status=no_eligible_driver, reassignment_count=1` |
| Booking state | ✅ `status=reassignment_needed, assigned_driver_id=NULL` (NOT fake-assigned) |
| Truthful recoverable New Orders state | ✅ |

### E2E-E — Cancellation

**File**: `evidence/r056-b3-e2e-a-e/e2e_e_cancel.sql`

| Step | Result |
|---|---|
| Cancel booking | ✅ `status=cancelled` |
| CANCELLED lifecycle event | ✅ recorded with reason |

### Pricing scenarios (Campanile + The Lodge + canonical guards)

**File**: `evidence/r056-b3-e2e-a-e/pricing_scenarios.sql`

| Scenario | Result | Expected | Status |
|---|---|---|---|
| Campanile → Brussels Airport | `€25 fixed, route_name="Campanile Vilvoorde ⇄ Brussels Airport"` | €25 fixed | ✅ |
| Brussels Airport → Campanile | `€30 fixed, route_name="Brussels Airport ⇄ Campanile Vilvoorde"` | €30 fixed | ✅ |
| Campanile (no-comma) → Airport | `€25 fixed` | €25 (multi-pattern match) | ✅ |
| The Lodge → Vilvoorde Centrum | `€15 (Vilvoorde min applied, raw=11)` | €15 | ✅ |
| Luchthavenlaan 18 → Vilvoorde Centrum | `€15 (Vilvoorde guard)` | €15 | ✅ |
| Brussels Airport → Mechelen | `€55 (airport rule, applicable_min=30)` | €55 (airport) | ✅ |

---

## Phase A summary

**5/5 E2E-A–E PASS** + **6/6 pricing scenarios PASS**.

This is the literal end-to-end proof Lux r056 §7 required:
- ✅ Booking creation → correct Vilvoorde €15 pricing
- ✅ Auto-assignment → correct Moukrim driver
- ✅ Accept/decline → reassignment to different driver
- ✅ Timeout → TIMEOUT_REASSIGN → different driver
- ✅ No eligible driver → truthful recoverable state (NO fake assignment, NO loop)
- ✅ Cancellation → status=cancelled
- ✅ Campanile ↔ Airport €25/€30 contractual pricing preserved
- ✅ The Lodge local Vilvoorde €15 minimum preserved

---

## What Phase A does NOT cover (parked per Lux §8)

| Item | Why parked |
|---|---|
| Customer ETA/contact (SMS/email driver arrival notification) | Isolated env has no email/SMS provider; requires staging |
| Real New Orders/Active/History UI coherence | Tested at DB state level; UI integration pending Phase D |
| Real email routing (BOOKING_CONFIRMATION, etc.) | Inbucket not running in current isolated config |
| Multiple consecutive complete booking-to-completion runs | Requires time-passing scenarios + driver workflow simulation |

These require Founder F1 staging env to test against real infrastructure.

---

## Next steps (r056)

Per Lux r056 §2 reliability-first sequencing:

**Phase A: ✅ DONE** (this commit)

**Phase B: Fix any runtime lifecycle defects** — none found in Phase A

**Phase C: Repository cleanup** — small dependency-proven batches (NH/, bravo, Landingfleet, Horizon) per r053 inventory

**Phase D: Dashboard final implementation** — canonical New Orders, Active/History clean separation, remove cross-business from operator paneel

**Phase E: Portal rationalization** — Driver KEEP, Customer KEEP, Moukrim = primary operator scope (already done in r055), Partner dormant

**Phase F: Mailbox adapter + UI shell** — server-side IMAP/SMTP with env-var secrets; mocked initial; real connection requires Founder F-M1

**Phase G: Full regression rerun** — pricing/assignment/timeout/mail/auth/portal/history after every material batch

**Phase H/I/J: BLOCKED on Founder** — staging access + mailbox credential + hands-on acceptance

---

## Files in r056 Phase A

- `evidence/r056-b3-e2e-a-e/e2e_a_normal_ride_v2.sql` (E2E-A canonical happy path)
- `evidence/r056-b3-e2e-a-e/e2e_b_decline.sql` (E2E-B decline → different driver)
- `evidence/r056-b3-e2e-a-e/e2e_c_timeout.sql` (E2E-C timeout → reassignment)
- `evidence/r056-b3-e2e-a-e/e2e_d_no_driver.sql` (E2E-D no eligible driver / cap)
- `evidence/r056-b3-e2e-a-e/e2e_e_cancel.sql` (E2E-E cancellation)
- `evidence/r056-b3-e2e-a-e/pricing_scenarios.sql` (6 canonical pricing scenarios)
- `evidence/r056-b3-e2e-a-e-evidence.md` — THIS FILE

Total insertion count: ~480 lines new.

---

## Mission Status

Mission ACTIVE. r056 Phase A complete. Phases B-J per Lux r056 §9 execution order.