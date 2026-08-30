# r056 Phase E round 1 corrections review — feedback corrections — evidence

## Context

Lux r056 Phase E r1 corrections review (`6403bdd`) returned:

**ACCEPTED:**
- §1: Partner/driver/PWA account requests reachable in canonical Clients/Partners surface ✅
- §2: Head-partner hard-delete safety server-enforced ✅

**REMAINING DEFECTS:**
- §3: New Clients/Partners surface still not multilingual end-to-end (filtered customer results regress to Dutch)
- §4: Stale `viewMailboxMessage('request')` still routes to removed `accountrequests` tab — falls through to New Orders

## Fix #3 — Full 4-language coverage for merged Clients/Partners surface

Added **43 NEW translation keys** × 4 languages = 172 new definitions (combined with 15 round-1 keys = **58 keys × 4 langs = 232/232**).

New keys (grouped by surface area):

**Partner actions / metrics:**
- `partnerActionEdit`, `partnerActionDetails`, `partnerActionReactivate`, `partnerActionArchive`, `partnerActionDelete`
- `loginIconTitle` (Heeft FleetConnect login)
- `metricDriver`, `metricDrivers`, `metricRide`, `metricRides`, `partnerMetricPrefix`
- `keyYes`, `keyNo`

**Customer surface:**
- `customerDefaultPickup`, `customerCreated`, `customerAuthLinked`
- `customerStatusActive`, `customerStatusArchived`
- `customerActionEdit`, `customerActionDetails`, `customerActionReactivate`, `customerActionArchive`, `customerActionDelete`
- `noCustomersFound`, `archivedCustomers`

**Account request surface:**
- `kindLabelClient`, `kindLabelAccount`
- `requestFieldEmail`, `requestFieldPhone`, `requestFieldCompany`, `requestFieldVehicle`, `requestFieldRegion`, `requestFieldRequested`, `requestFieldAuthLinked`
- `requestActionApprove`, `requestActionReject`

**Filter bar:**
- `search`, `searchNameEmail`, `sort`, `sortNewestFirst`, `sortOldestFirst`, `sortByName`, `sortByEmail`, `btnReset`

Replaced all hardcoded Dutch strings in:
- `renderPartner()` (used by both `renderPartners` and `renderClientsPartners`): partner action titles, login icon title, partner metrics (chauffeur/drivers, rit/ritten, Prefix)
- `renderAccountRequestItem()`: bedrijf/voertuig/regio labels, aangevraagd/auth-gekoppeld labels, kind badge (Client/Driver PWA/Partner PWA/Operations/Account), action buttons
- `renderClientRequest()`: same fields plus default pickup address
- `renderCustomer()` (used in both full render and filtered list): status, default pickup, created, auth-linked, all action titles
- `renderCustomersList()` (filtered customer results): added `const t = translations[currentLang];` lookup, all status/field/action strings now use translation keys
- Page template: filter bar labels/placeholders/options, "no customers found" empty state, archived customers section header

**Lux §3 required: rerun factual 4-language visible-surface check, not just key-count check.**
- Factual visible-surface check: searched `renderClientsPartners` block + `renderCustomersList` block for common Dutch words (Bewerken, Details, Heractiveren, Archiveren, Verwijderen, Standaard ophaaladres, Aangemaakt, Aangevraagd, Auth gekoppeld, Goedkeuren, Afwijzen, Bedrijf, Voertuig, Regio, Hoofdpartner, Sub-partner, Gearchiveerd, Actief, Klanten, Naam of email, Nieuwste eerst, Oudste eerst, Zoeken, Sorteer, Reset, ja, nee, chauffeur, rit)
- Result: **0 hardcoded Dutch strings remain** in both blocks
- (3 false positives found: "Details" / "Regio" / "Reset" — all are substrings of `t.partnerActionDetails` / `t.requestFieldRegion` / `t.btnReset` which are fully translated)

## Fix #4 — Stale accountrequests routing

Original:
```js
viewMailboxMessage(kind) {
  if (kind === 'request') { this.currentTab = 'accountrequests'; this.refreshCurrentTab(); }
}
```

`refreshCurrentTab()` has no `accountrequests` case after Phase D nav removal → falls through to New Orders → misleading.

Replacement:
```js
viewMailboxMessage(kind) {
  // PRIME r056 Phase E round 1 corrections: route request placeholders to canonical Clients/Partners tab
  // (not the removed accountrequests tab — falls through to New Orders and is misleading)
  if (kind === 'request') { this.currentTab = 'customers'; this.refreshCurrentTab(); return; }
  if (kind === 'booking' || kind === 'order') { this.currentTab = 'neworders'; this.refreshCurrentTab(); return; }
  this.showToast('Dit bericht kan nog niet geopend worden in de operator cockpit.');
}
```

- `request` → routes to canonical `customers` tab (Clients/Partners) — request is reachable via account request sub-sections
- `booking`/`order` → routes to canonical `neworders` tab (New Orders) — booking/order placeholders
- Other kinds → operator toast (placeholder for future Phase F mailbox UI)

**Factual removed-tab routing scan** (Lux §4 required: scan for any other stale internal transitions to removed tabs):
- Searched all `currentTab = '<value>'` assignments
- Found **only 1 stale path** (`viewMailboxMessage`) — now fixed
- No remaining transitions to `accountrequests`, `partners`, `agenda`, `settlements`, or `wiki` tabs

## Verification

- Syntax: `node --check` PASS on both script blocks (ESM module + main IIFE)
- CRLF line endings: preserved (1764 CRLF, 0 LF only)
- Translation coverage: 232/232 (58 keys × 4 languages); 43 NEW keys verified each present in 4 languages
- Visible-surface check: 0 hardcoded Dutch strings in `renderClientsPartners` block + `renderCustomersList` block
- Stale routing scan: 0 remaining transitions to removed tabs
- Diff stat: `Paneel/onderaannemerA.html | 80 +++++++++++++++++++++++++++++-----------------` (51 insertions, 29 deletions) — small conservative batch
- Backward compat preserved: `renderCustomers()` alias kept, `applyFiltersCustomers()` unchanged

## Scope discipline (per Lux §3 reliability-first)

- Only the 2 specific defects Lux identified (i18n completeness + stale routing)
- Did NOT modify `loadOperatorDashboardSnapshot()` RPC contract
- Did NOT delete any existing translation keys
- Did NOT add new tabs
- Did NOT refactor action handlers
- Kept `renderAccountRequests()` standalone function intact for deep-linking from email/notification links
- Kept `getAccountRequestKindLabel()` semantics (returns "Driver PWA" / "Partner PWA" / "Operations" / "Account" — these are not translated because they're internal labels for the kind of access request, not customer-facing strings; the badge style differentiates them visually)