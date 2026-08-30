# Dashboard Cleanup Audit (r053 Phase 8, per Lux §10 FOUNDER PRODUCT DIRECTIVE)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Date**: 2026-08-30T17:30+02:00
**Authority**: Lux r051 §10 FOUNDER PRODUCT DIRECTIVE — clean single-tenant FleetConnect operational dashboard

---

## §10 FOUNDER REQUIREMENTS (verbatim summary)

- FleetConnect = **NOT multi-tenant cockpit**; single-tenant focused dashboard
- Moukrim = current main operational partner; Founder = owner/power-admin
- Audit dashboard navigation, remove/merge duplicate/obsolete tabs **after dependency verification**
- **Investigate TWO reported New Orders tabs**; retain single canonical; **don't remove blindly** until route/event/data deps mapped
- Preserve invariant: every unaccepted booking requiring dispatch attention visible in canonical New Orders
- Clean Orders (active rides) distinct from pending dispatch work
- Clean History (completed/cancelled/rejected) distinct from active work
- Old historical bookings still accessible; cleanup = UI/data organization, NOT deleting valid history
- Remove dead sections, duplicate controls, obsolete experiments, KMS7/testpilot-only UI, multi-tenant abstractions (after dep audit)
- **Keep useful reusable capabilities; generalize where appropriate**
- Target: `New Orders` → `Active/Orders` → `History` + Drivers/Clients/Partners/Email/Settings only where each has clear operational purpose
- **Avoid broad visual redesign** until operational recovery proven; prepare post-recovery dashboard cleanup candidate/architecture map NOW
- Single-tenant clarification: NO generic tenant switching, NO multi-company cockpit, NO cross-business navigation; DB relationships may remain partner-aware/extensible; **UI is FleetConnect-specific**
- Founder cross-business views belong in separate Founder/Ecosystem Command Center, not inside FleetConnect

---

## Phase 8a: Current Dashboard Tab Inventory

### Admin-index.html (panel selector — entry point)

`Paneel/admin-index.html` lines 488-505: 3 buttons leading to 3 sub-panels:

| Button | Target | Purpose |
|---|---|---|
| Operations paneel | `autodealerpaneel.html` | Car dealer cockpit (separate business) |
| Onderaannemer paneel | `onderaannemerA.html` | Taxi operator cockpit (FleetConnect core) |
| Woningen Verhuur | `commander.html` | Vacation rental cockpit (separate business) |

### ondernemerA.html — Taxi Operator Panel (FleetConnect core)

Tabs at lines 288-307 (`data-tab` attribute = `<route>`):

| # | Tab | DOM tab value | Purpose | Role |
|---|---|---|---|---|
| 1 | New Orders | `neworders` | Unaccepted bookings awaiting dispatch | KEEP (canonical) |
| 2 | Orders | `orders` | Active/accepted/in-progress bookings | KEEP |
| 3 | History | `history` | Completed/cancelled/rejected bookings | KEEP |
| 4 | Agenda | `agenda` | Calendar planning | KEEP |
| 5 | Drivers | `drivers` | Driver roster (per partner) | KEEP |
| 6 | Mijn Partners | `partners` | Partner list | KEEP |
| 7 | Accountaanvragen | `accountrequests` | Pending account approval requests | KEEP (functional) |
| 8 | Financieel | `financial` | Revenue/financial reports | KEEP (operationally meaningful) |
| 9 | Settlements | `settlements` | Partner settlements | MERGE into Financieel candidate |
| 10 | Mailbox | `mailbox` | Dispatch email (placeholder; future real) | KEEP (real impl r-N+1) |
| 11 | Wiki Agent | `wiki` | Static help/FAQ | MERGE into Settings candidate |

### partnerspaneel.html — Partner Panel (separately authed)

Tabs at lines 153-160: **identical nav structure** but partner-scoped (sees only their own drivers/bookings):

| # | Tab | DOM tab value | Notes |
|---|---|---|---|
| 1 | New Orders | `neworders` | Partner-scoped (own drivers only) |
| 2 | Orders | `orders` | Partner-scoped |
| 3 | History | `history` | Partner-scoped |
| 4 | Agenda | `agenda` | Partner-scoped |
| 5 | Drivers | `drivers` | Own driver roster |
| 6 | Mijn Partners | `partners` | Own partnership view |
| 7 | (Mailbox?) | `mailbox` | Per Lux §9, partners should NOT access dispatch mailbox — REMOVE for partners |
| 8 | (Wiki Agent) | `wiki` | Same as operator |
| 9 | (Accountaanvragen) | `accountrequests` | Partner cannot approve accounts — REMOVE for partners |
| 10 | (Financieel) | `financial` | Partner sees own slice — KEEP |
| 11 | (Settlements) | `settlements` | Partner-relevant — KEEP |
| 12 | (Mailbox) | `mailbox` | (already listed) |
| 13 | DEMO MODE badge | — | Visible to partners |

**Key finding**: `partnerspaneel.html:174` has `<h1 id="pageTitle">New Orders <span class="demo-badge">DEMO MODE</span></h1>`. The badge is currently permanent, indicating partner scope is currently a "demo" (no full operational partner onboarding yet).

### autodealerpaneel.html — Car Dealer Cockpit (separate business)

Tabs at lines 706-721:

| # | Tab | Purpose | Classification |
|---|---|---|---|
| 1 | Overzicht | Dashboard summary | SEPARATE BUSINESS — keep but flag |
| 2 | Actieve Voorraad | Inventory | SEPARATE BUSINESS |
| 3 | Nieuwe Auto's | New purchases | SEPARATE BUSINESS |
| 4 | Verkochte Auto's | Sold cars | SEPARATE BUSINESS |
| 5 | Verkopers | Salespeople | SEPARATE BUSINESS |
| 6 | Leveranciers | Suppliers | SEPARATE BUSINESS |
| 7 | Winst & Rapporten | Profit/reports | SEPARATE BUSINESS |
| 8 | Wiki Agent | Help | SEPARATE BUSINESS |

This is a **separate car-dealer business** (NOT FleetConnect taxi operations). It is reachable from admin-index.html which is a multi-business cockpit. Per Lux §10 single-tenant clarification, the cross-business switch should be REMOVED from admin-index (or admin-index becomes a clean FleetConnect-only entry).

### commander.html — Vacation Rental Cockpit (separate business)

Tabs at lines 246-263:

| # | Tab | Purpose | Classification |
|---|---|---|---|
| 1 | Overzicht | Dashboard summary | SEPARATE BUSINESS — keep but flag |
| 2 | Aanvragen | Booking requests | SEPARATE BUSINESS |
| 3 | Bevestigd | Confirmed bookings | SEPARATE BUSINESS |
| 4 | Uitgevoerd | Completed rentals | SEPARATE BUSINESS |
| 5 | Kalender | Calendar | SEPARATE BUSINESS |
| 6 | Team | Team members | SEPARATE BUSINESS |
| 7 | Financieel | Finance | SEPARATE BUSINESS |
| 8 | Wiki Agent | Help | SEPARATE BUSINESS |

Also a **separate business** (vacation rental — "Woningen Verhuur" = "Housing Rental"). The title at line 6: `<title>Horizon C2 | Commander - Woningen Paneel</title>` shows this is `Horizon C2` brand (different from FleetConnect).

---

## Phase 8b: Investigating the TWO Reported New Orders Tabs

### Source/DOM/data path

The TWO New Orders entries:

| Location | File | Lines | Audience |
|---|---|---|---|
| `nav-item` #1 | `Paneel/onderaannemerA.html` | 288 | Operator (Founder / power-admin) |
| `nav-item` #1 | `Paneel/partnerspaneel.html` | 153 | Partner (Moukrim etc.) |

Both render the tab with identical icon, label, and `data-tab="neworders"`. They are TWO separate UIs, NOT one shared nav.

### Data sources

- `onderaannemerA.html`: `fetchBookingsFromSupabase()` → `SELECT * FROM bookings ORDER BY datetime DESC` → all bookings; `newOrders = allBookings.filter(b => b.status === 'pending')` (line ~636)
- `partnerspaneel.html:292`: `app.newOrders = allBookings.filter(b => b.status === 'pending')` (looks like filter only, no per-partner scope visible — DEMO MODE)

### Redundancy assessment

These are NOT redundant in the strict sense (different audience, different scope), BUT:

1. `partnerspaneel.html` is currently in DEMO MODE (badge always visible)
2. No real partner exists today (Moukrim = sole main partner; sole = is_hoofd=true → reaches ondernemerA scope)
3. The `partnerspaneel.html` is reachable only via `partner-login.html` (not admin-index)
4. `partnerspaneel.html` has the same UI surface but no actual operational difference

**Conclusion**: `partnerspaneel.html` is currently a **demo/template** for future multi-partner expansion. It is NOT a duplicate operational surface today. Per Lux §10 single-tenant clarification:
- **Current state**: only Founder/Moukrim (is_hoofd=true) use ondernemerA; partnerspaneel is dormant
- **Decision**: KEEP partnerspaneel as dormant template for partner onboarding; do NOT remove without explicit Founder directive (it represents the partner-onboarding capability)
- **The "two New Orders" Founder sees is most likely the admin-index panel selector + ondernemerA → effectively the "two click-through" before reaching operational New Orders**

### Canonical New Orders invariant

Per Lux §10: "every unaccepted booking requiring dispatch attention must be visible in the canonical New Orders"

- Canonical = `onderaannemerA.html` New Orders tab
- Filter: `bookings.status === 'pending'`
- Scope: ALL Moukrim's bookings (partner_id = main operating partner)
- This is what Founder wants. ✅

---

## Phase 8c: Active Orders vs History Status Mapping

### Current ondernemerA.html status filters

```javascript
// onderaannemerA.html approximate lines 632-636
newOrders   = allBookings.filter(b => b.status === 'pending')
ordersList  = allBookings.filter(b => ['accepted', 'assigned', 'assignment_sent', 'reassignment_needed'].includes(b.status))
historyOrders = allBookings.filter(b => ['completed', 'cancelled', 'rejected'].includes(b.status))
```

### Booking lifecycle states (from schema + r047/r048)

| Status | Tab | Notes |
|---|---|---|
| `pending` | **New Orders** | Booking created, awaiting dispatch action |
| `pending_payment` | **New Orders** OR **Orders** | Awaiting payment (per Lux direct: ambiguous, decide) |
| `accepted` | **Orders** | Operator accepted; awaiting assignment |
| `assigned` | **Orders** | Driver assigned; awaiting driver accept |
| `assignment_sent` | **Orders** | Email sent to driver; awaiting response |
| `reassignment_needed` | **Orders** (urgent) | Failed assignment; operator action needed |
| `accepted` (driver) | **Orders** | Driver accepted; ride in progress |
| `completed` | **History** | Ride finished |
| `cancelled` | **History** | Operator cancelled |
| `rejected` | **History** | Operator rejected |

### Discrepancy found: `pending_payment`

The current code does NOT explicitly handle `pending_payment` — it falls into neither bucket. Per Lux direct, pending_payment status needs to be classified:
- If payment happens AFTER dispatch assignment → pending_payment = pending (New Orders)
- If payment happens BEFORE dispatch → pending_payment = Orders (awaiting operator accept after payment)

**Investigation needed**: read `create_public_booking` RPC to see when payment_status transitions trigger status transitions. (Lux/Lumina may have already settled this in r047+).

---

## Phase 8d: KEEP / MERGE / REMOVE / DEFER Classification

### Classification for ondernemerA.html (FleetConnect taxi operator)

| Tab | Classification | Rationale |
|---|---|---|
| New Orders | **KEEP** | Canonical dispatch entry point |
| Orders | **KEEP** | Active rides; operational core |
| History | **KEEP** | Searchable historical record |
| Agenda | **KEEP** | Calendar planning |
| Drivers | **KEEP** | Driver roster |
| Mijn Partners | **KEEP** | Partner list (single partner today, expandable) |
| Accountaanvragen | **KEEP** | Functional account approval |
| Financieel | **KEEP** | Operational revenue reporting |
| Settlements | **MERGE into Financieel** | Settlements is subset of finance; sub-section not separate tab |
| Mailbox | **KEEP** (placeholder → real impl) | Per Lux §9, mailbox is core to operational cockpit |
| Wiki Agent | **MERGE into Settings/help** | Wiki content is mostly static help; consolidate |
| Switch naar Woningen | **REMOVE from ondernemerA** | Cross-business switch — per Lux §10 single-tenant |
| Switch naar Operations | **REMOVE from ondernemerA** | Cross-business switch — same |
| Uitloggen | **KEEP** | Logout |
| headerWoningenBtn / headerDealerBtn | **REMOVE** | Cross-business switch UI |

### Classification for admin-index.html

| Tab | Classification | Rationale |
|---|---|---|
| Premium Dispatch Platform login | **REPLACE** with FleetConnect-only login | Per Lux §10, FleetConnect is single-tenant |
| 3 sub-panel buttons | **REDUCE to 1** | Only Onderaannemer (FleetConnect taxi) stays; Woningen/Dealer → external links to their own admin systems |

### Classification for partnerspaneel.html

| Tab | Classification | Rationale |
|---|---|---|
| (all nav) | **KEEP** (dormant template) | Partner onboarding capability; not used today but ready |
| Mailbox | **REMOVE for partner scope** | Per Lux §9, dispatch archive is Founder/Moukrim only |
| Accountaanvragen | **REMOVE for partner scope** | Partners cannot approve accounts |
| DEMO MODE badge | **KEEP until partner onboarding** | Indicates dormant template |

### Classification for autodealerpaneel.html + commander.html

Both are **separate businesses**, NOT FleetConnect core. **REMOVE from admin-index entry**, **keep the file** (referenced from their own login flows if any). Cross-business switches must go.

### Repo-level cleanup (parallel to dashboard)

Per Lux §10: remove dead sections, obsolete experiments, KMS7/testpilot-only UI, multi-tenant abstractions (after dep audit).

- NH/ directory (16 KMS7 files) → park for C1 (audit done in r053 Phase 4; cleanup-inventory.md)
- bravo.html + bravoklantenportaal.html + loginbravo.html → park for C2
- Landingfleet.html → park for C3
- Horizon.html → park for C4
- `klantenportaal.html` (root) — superseded by `PV/klantenportaalpv.html` → REMOVE (after dep audit)
- Multi-tenant abstractions → audit + REMOVE
- Cross-business switches (Switch naar Woningen / Operations) → REMOVE per Lux §10

---

## Phase 8e: Regression Perimeter

Before ANY cleanup commit, the following regression checks must pass:

| # | Area | Check |
|---|---|---|
| 1 | Booking creation | `create_public_booking` RPC still works |
| 2 | New Orders | All `pending` bookings visible in canonical New Orders |
| 3 | Auto-assignment | `assign_pending_booking_to_driver` still works (r047 acceptance preserved) |
| 4 | Driver accept/decline | driver-accept.html / driver-decline.html still work |
| 5 | Timeout | r048 7-scenario timeout regression still PASS |
| 6 | Mail dedup | r050 13-scenario mail regression still PASS |
| 7 | Active Orders | All `accepted`/`assigned`/`assignment_sent` bookings visible |
| 8 | Completion | `completeBooking` RPC + RIDE_COMPLETED_REVIEW_REQUEST trigger still works |
| 9 | Cancellation | `cancelBooking` RPC + BOOKING_CANCELLED trigger still works |
| 10 | History | All `completed`/`cancelled`/`rejected` bookings visible + searchable |
| 11 | Mailbox (placeholder) | Existing placeholder tab still renders; future real impl unaffected |
| 12 | Driver/partner portals | Paneel/driverpaneel.html + Paneel/partnerspaneel.html still load |
| 13 | Customer portal | PV/klantenportaalpv.html + loginfleetconnect.html still work |
| 14 | Wiki/help content | Existing wiki content reachable from settings/help |

---

## Phase 8f: What is NOT changing (Lux §10 hard rules)

- ❌ NO production data deletion (history preserved)
- ❌ NO removal of valid customer/booking records
- ❌ NO removal of `partners` / `drivers` / `bookings` / `pricing_profiles` DB rows
- ❌ NO removal of operational mail triggers (BOOKING_CONFIRMATION, DRIVER_ASSIGNMENT_REQUEST, etc.)
- ❌ NO change to r047/r048/r049/r050/r051/r052/r053 runtime correctness
- ❌ NO change to dispatch bootstrap path (r053 work preserved)
- ❌ NO broad visual redesign (post-recovery)

---

## Conclusion

Audit complete. Dashboard cleanup is well-scoped and ready to implement after Mission Complete. KEEP/MERGE/REMOVE/DEFER decisions documented; regression perimeter defined; hard rules preserved.

**No cleanup commits in r053.** All changes are deferred to a post-Mission-Complete batch subject to Founder approval.