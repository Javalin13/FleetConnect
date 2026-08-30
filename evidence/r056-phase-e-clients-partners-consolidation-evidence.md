# r056 Phase E round 1 — Clients/Partners consolidation

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Round**: r056 Phase E
**Date**: 2026-08-31T01:15+02:00
**Branch**: `integration-r056`
**Head**: (this commit)

## Goal (per Lux r056 §3.3-3.5)

Single visible `Clients/Partners` surface showing:
- Partner data (with head-partner badge)
- Customer data (existing)
- Account-request workflow (existing)

WITHOUT creating a second operational cockpit.

## Implementation (conservative batch)

### 1. Renamed `renderCustomers` → `renderClientsPartners`

Renamed the rendering method to semantically match the visible nav tab. The new method:
- Shows Partners section at TOP (with `+ Nieuwe partner` button)
- Shows Client account requests section in MIDDLE (existing)
- Shows Customers section at BOTTOM (existing)

Backward compatibility: added `renderCustomers() { this.renderClientsPartners(); }` as alias for any existing call sites.

### 2. Partner section uses rich data from `this.partners`

Each partner card shows:
- Name + Hoofdpartner/Sub-partner badge
- Contact + email + phone
- Driver count + ride count + prefix
- Action buttons: edit / details / archive / unarchive / delete (all existing handlers)

### 3. `refreshCurrentTab` dispatch updated

`case 'customers': this.renderClientsPartners();` — single visible tab dispatches to merged view.

### 4. Page title unified

`pageTitle` now shows: `Clients/Partners <count>` (where count = activePartners + active customers).

### 5. Reset button references renamed

`btn-reset onclick="app.renderClientsPartners()"` instead of `renderCustomers()` (in case anyone re-renders).

## Verifications

### Syntax check
```bash
node --check /tmp/onderaannemer_module.mjs
# rc=0, no errors
```

### Line endings preserved (CRLF, matches HEAD convention)

### Real diff stat (Phase E round 1)
```
Paneel/onderaannemerA.html | 46 ++++++++++++++++++++++++++-----
1 file changed, 41 insertions(+), 5 deletions(-)
```

### Audit — no second cockpit introduced

- Single visible nav tab `Clients/Partners` (unchanged from Phase D)
- 3 sub-sections (Partners / Account Requests / Customers) under one tab
- All action handlers preserved (editPartner, deletePartner, archivePartner, editCustomer, archiveCustomer, etc.)
- Existing load methods unchanged (loadPartners, loadCustomers, loadAccountRequests, loadOperatorDashboardSnapshot)

### Backward compatibility

- `renderCustomers()` kept as alias → calls `renderClientsPartners()`
- `applyFiltersCustomers()` preserved (still filters customer list)
- `renderCustomersList(customers)` preserved (renders filtered subset)
- All existing internal call sites (line 1014, 1070, 1079, 1087, 1325, 1499, 1500, 1542, 1268) reference `renderPartners` or `renderAccountRequests` — these are DEAD CODE per Phase D (currentTab can only be one of the nav tabs) but kept for safety per Lux §3.6 small-batch discipline

## Files modified

- `Paneel/onderaannemerA.html` (added Partners section + renamed render method + alias)
- `evidence/r056-phase-e-clients-partners-consolidation-evidence.md` (NEW, this file)

## Out of scope (deferred to follow-up rounds)

- **Settings/Admin rationalization** (current `renderFinance()` shell — needs real operator configuration UI)
- **Dead CSS / dead translation keys / dead render methods cleanup** (per Lux §3.6 small batches only)
- **Account-request workflow further consolidation** (already folded into Clients/Partners — no separate tab needed)
- **Partner sub-tabs or filters** (current single-section Partners display is sufficient for operational use)

## Round identity

This commit: continuation of `r056-phase-e-portal-rationalization` round 1.

Next round: `r056-phase-e-round-2-settings-admin-content` (after Lux review acceptance).