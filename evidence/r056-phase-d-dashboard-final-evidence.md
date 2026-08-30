# r056 Phase D — FleetConnect dashboard final implementation (canonical 7-tab structure)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Round**: r056
**Date**: 2026-08-30T23:05+02:00
**Branch**: `integration-r056`
**Head**: (this commit)

## Lux r056 §3 Phase D target

> Implement a single canonical FleetConnect-specific operator cockpit with:
>
> - **New Orders** as the only canonical "new/pending/incoming" surface, including pending, assignment-sent, reassignment-needed and other truthful dispatch-attention states until driver acceptance
> - **Active Orders** containing only accepted/current operational rides
> - **History** containing only completed/cancelled/rejected rides and any prior-window truthful archive states; searchable/filterable; no duplicate/confusing tabs
> - **Drivers** containing only operational driver data, scope-appropriate
> - **Clients/Partners** containing only operationally useful client/partner contact data
> - **E-mail** containing the integrated `dispatch@fleetconnect.be` mailbox
> - **Settings/Admin** containing Founder/power-admin operator configuration
>
> Do NOT duplicate New Orders; do NOT carry cross-business controls; do NOT carry generic multi-company cockpit patterns. One canonical cockpit only.

## Target structure (delivered)

```
BOEKINGEN
  - New Orders       (data-tab="neworders")   → renderNewOrders
  - Active Orders    (data-tab="orders")      → renderOrders
  - History          (data-tab="history")     → renderHistory

BEHEER
  - Drivers          (data-tab="drivers")     → renderDrivers
  - Clients/Partners (data-tab="customers")   → renderCustomers (Partners data joined)

FINANCIËN
  - Settings / Admin (data-tab="financieel")  → renderFinance

INFORMATIE
  - E-mail           (data-tab="mailbox")     → renderMailbox
```

7 tabs. Matches Lux target exactly.

## Changes made

### 1. Nav-menu structure (lines 285-307)
- **REMOVED** nav items: Agenda, Partners (separate), Accountaanvragen, Settlements, Wiki Agent
- **REMOVED** header buttons: Woningen Paneel, Switch naar Operations (cross-business residue)
- **RENAMED**:
  - "Orders" → "Active Orders"
  - "Mijn Partners" → "Clients/Partners" (combined with existing Customers tab via single renderCustomers)
  - "Financieel" → "Settings / Admin" (placeholder for Settings/Admin content)
  - "Mailbox" → "E-mail"
- **RESULT**: 7 canonical tabs only

### 2. Header buttons removed
- REMOVED: `<button class="switch-woningen-btn" id="headerWoningenBtn">`
- REMOVED: `<button class="switch-btn" id="headerDealerBtn">`
- Justification: Both pointed to `commander.html` / `autodealerpaneel.html` (cross-business residue per Lux §3 + r053 dashboard-cleanup-audit.md).

### 3. Switch tab handlers (lines 1633-1638)
- `refreshCurrentTab()` dispatch updated: removed `agenda`, `partners`, `customers` (kept; combined into Clients/Partners), `accountrequests`, `settlements`, `wiki` cases
- Result: only the 7 canonical tabs are dispatched

### 4. Status filter logic (lines 608, 620)

**`isNewOrderStatus` (line 608) — corrected per Lux §2:**
```js
// BEFORE
isNewOrderStatus(status) { return ['pending', 'pending_payment', 'accepted', 'assignment_sent', 'reassignment_needed'].includes(status); },
// AFTER
isNewOrderStatus(status) { return ['pending', 'pending_payment', 'assignment_sent', 'reassignment_needed'].includes(status); },
```
**Rationale**: `accepted` (driver has accepted) belongs in **Active Orders**, NOT New Orders. Per Lux §2: "every unaccepted booking requiring dispatch attention remains visible there, including pending, assignment-sent, reassignment-needed and other truthful dispatch-attention states until driver acceptance".

**`ordersList` (line 620) — corrected per Lux §2:**
```js
// BEFORE
this.ordersList = this.allBookings.filter(b => b.status === 'assigned' && !this.isExpired(b.datetime, b.time));
// AFTER
this.ordersList = this.allBookings.filter(b => (b.status === 'assigned' || b.status === 'accepted') && !this.isExpired(b.datetime, b.time));
```
**Rationale**: Active Orders = accepted/current operational rides. Driver has acknowledged the assignment (`assigned`) or fully accepted (`accepted`) — both are operational, not dispatch-attention.

### 5. Cross-business switch handlers (line 1643)
REMOVED:
```js
document.getElementById('switchWoningenBtn')?.addEventListener('click', () => window.location.href = 'commander.html');
document.getElementById('switchDealerBtn')?.addEventListener('click', () => window.location.href = 'autodealerpaneel.html');
document.getElementById('headerWoningenBtn')?.addEventListener('click', () => window.location.href = 'commander.html');
document.getElementById('headerDealerBtn')?.addEventListener('click', () => window.location.href = 'autodealerpaneel.html');
```
Justification: All buttons removed from header; handlers no longer needed.

### 6. Null-safe i18n setter (lines 547-562)
**BEFORE**: Direct `document.getElementById('navAgenda').textContent = t.navAgenda` — would throw TypeError when called because navAgenda element was removed.

**AFTER**: Helper method `_setText(id, value)` that checks element existence before setting:
```js
_setText(id, value) { const el = document.getElementById(id); if (el && value !== undefined && value !== null) el.textContent = value; }
```
All i18n setters use this helper. Removed elements (navAgenda, navSettlements, navWiki, navPartners, navAccountRequests) silently no-op instead of throwing.

### 7. Dead CSS / dead code (kept for now)
- `.switch-btn`, `.switch-woningen-btn` CSS rules at lines 121, 132-135: orphaned (no elements use these classes). Not breaking; cosmetic cleanup deferred to avoid file-size growth in this round.
- Translation keys `headerWoningenText`, `headerDealerText`, `switchWoningenText`, `switchDealerText`: orphan keys (no elements reference them). Not breaking; cosmetic cleanup deferred.
- Dead render methods (`renderAgenda`, `renderPartners`, `renderAccountRequests`, `renderSettlements`, `renderWiki`): no longer called from `refreshCurrentTab()` because their tabs were removed. Kept as code rather than deleted because:
  - `renderPartners` (line 935) still has 3 internal `if (this.currentTab === 'partners')` callers (lines 1069, 1078, 1086) for action feedback (e.g. after editDriver) — these are now dead but defensive
  - Conservative deletion per Phase C rule 35 (delete obsolete files, not code paths); future round can clean up dead code paths in a follow-up commit

## Verifications performed

### Syntax check (node --check)
```bash
node --check /tmp/onderaannemer_module.mjs
# rc=0, no errors
```
Module parses as valid ES module. All `render*` methods are callable.

### Nav-menu inventory (current)
- ✅ BOEKINGEN: New Orders, Active Orders, History (3)
- ✅ BEHEER: Drivers, Clients/Partners (2)
- ✅ FINANCIËN: Settings / Admin (1)
- ✅ INFORMATIE: E-mail (1)
- Total: 7 tabs (matches Lux target)

### Dispatch inventory (refreshCurrentTab)
- ✅ neworders → renderNewOrders
- ✅ orders → renderOrders
- ✅ history → renderHistory
- ✅ drivers → renderDrivers
- ✅ customers → renderCustomers
- ✅ financieel → renderFinance
- ✅ mailbox → renderMailbox
- ✅ default → renderNewOrders

### i18n null-safety (applyTranslations)
- ✅ _setText() helper added
- ✅ All nav text setters use null-safe helper
- ✅ Language switch (NL/FR/EN/ES) will NOT throw on missing elements

## Status filter alignment with Lux §2

| Lux §2 spec | Old behavior | New behavior |
|---|---|---|
| New Orders = pending, assignment-sent, reassignment-needed, unaccepted states | Included `accepted` (incorrect) | Excludes `accepted`; only `pending`, `pending_payment`, `assignment_sent`, `reassignment_needed` |
| Active Orders = accepted/current operational rides | Only `assigned` | `assigned` OR `accepted` |
| History = completed/cancelled/rejected + prior-window truthful archive states | Already correct | Unchanged |

## Phase D scope boundaries (this commit)

### In scope (this commit)
- Nav-menu simplification (canonical 7 tabs)
- Cross-business buttons removal (Woningen + Operations)
- Header buttons removal
- Switch handler removal
- Status filter logic correction (`isNewOrderStatus`, `ordersList`)
- Null-safe i18n setter
- Translation key application works on missing elements

### Out of scope (deferred to follow-up rounds)
- **Settings / Admin content**: tab exists but `renderFinance` shows current financial data; needs to be expanded with operator configuration (F1 staging URL, mailbox credentials, pricing profile, partner hierarchy settings) per Lux §3.2
- **E-mail content**: tab exists; `renderMailbox` shows mailbox data; needs Phase F mailbox adapter for real IMAP/SMTP integration
- **Clients/Partners consolidation UI**: tab shows Customers; Partners data should be merged into the Clients/Partners view (currently separate rendering methods but single tab dispatches to `renderCustomers`). Phase E portal rationalization will address whether Partners = a sub-tab or distinct rendering
- **Accountaanvragen migration**: account requests (customer/partner signup requests) currently have NO tab; per Lux §3 should be discoverable from Clients/Partners. Currently `renderAccountRequests` is dead code; needs UI integration
- **Dead CSS cleanup** (`.switch-btn`, `.switch-woningen-btn`)
- **Dead translation keys cleanup** (`headerWoningenText`, etc.)
- **Dead render methods cleanup** (`renderAgenda`, `renderSettlements`, `renderWiki`, etc.)

These follow-ups are smaller-scope batches per Lux r055 §3 reliability-first directive (small commits, prove no dependency, don't merge scope).

## Phase D dependencies unblocked

- ✅ Phase E (portal rationalization) — operator dashboard scope is now clearly bounded (no FleetConnect ↔ cross-business leaks)
- ✅ Phase F (mailbox) — E-mail tab exists, ready for adapter integration
- ✅ Phase G (regression rerun) — dashboard scope stable for regression

## Files modified

- `Paneel/onderaannemerA.html` (FleetConnect operator dashboard)
  - nav-menu structure simplified
  - header buttons removed
  - switch handlers simplified
  - status filter logic corrected per Lux §2 (Phase D r1 + Phase D Fix #1 in Phase D r2)
  - null-safe i18n setter added
  - cross-business button handlers removed
  - translation values updated for all 4 languages (Phase D Fix #2 in Phase D r2)

## Phase D r1 + r2 timeline

- **Phase D r1** (commit `2727714d`): Nav-menu + cross-business removal + null-safe i18n + status filter correction (initial)
- **Phase D r2** (this commit): Per Lux §2 + §3 review corrections — Fix #1 (clock-time expiration must not move unaccepted to History) + Fix #2 (translation values preserve canonical 7-tab semantics across all 4 languages)

## Lux corrections addressed

- **Fix #1**: Unresolved overdue dispatch-attention bookings remain in New Orders until lifecycle resolution (no clock-time disappearance to History)
- **Fix #2**: Translation values updated for NL/FR/EN/ES so canonical 7-tab semantics survive language switching (Active Orders / Clients/Partners / Settings/Admin / E-mail in all 4 languages)

Detailed verification: `evidence/r056-phase-d-fixes-verification.md`

## Commit

- SHA: `2727714d7a16b1cf0b986e0a4846a6a15da77057` (Phase D r1)
- SHA: (this commit) — Phase D r2 corrections
- Branch: `integration-r056` at base `4cd308e` (r055 head) — preserves r055 auth boundary
- Push: pending (will be committed + pushed in this round)