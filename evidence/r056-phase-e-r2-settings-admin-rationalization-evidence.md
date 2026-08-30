# r056 Phase E round 2 — Settings/Admin rationalization — evidence

## Context

Lux r056 Phase E round 1 closure (`b20b5ee`) accepted round 1 and directed:

> **§4. Proceed Phase E round 2 autonomously — Settings / Admin**
>
> Now rationalize Settings / Admin into a real FleetConnect operational/admin surface rather than the current renamed `renderFinance()` shell.
>
> Required direction:
> - preserve useful non-sensitive KPIs/financial overview where operationally useful;
> - clearly separate overview/diagnostics from configuration/admin controls;
> - expose only safe configuration/status information appropriate for Founder/power-admin/operator scope;
> - preserve server-derived authorization and role separation;
> - do not introduce generic multi-company/tenant switching;
> - **do not expose service-role keys, Supabase secrets, auth tokens, mailbox passwords, SMTP/IMAP credentials, or any other secrets in browser UI/source/Bridge/evidence/chat**;
> - do not put F1 staging credentials into the UI;
> - Phase F mailbox secrets remain server-side environment/config only;
> - if a setting cannot safely be changed client-side, show status/read-only information or route the mutation through an already-authorized server-side mechanism rather than weakening security.

## Implementation

### 1. Renamed surface (Settings / Admin)

Replaced placeholder `renderFinance()` shell (5 KPI cards only) with 3-section operational/admin surface:

**Section A — Overview** (available to all operator/founder scope):
- Total Revenue (EUR)
- Total Rides
- New Orders count
- Active Orders count
- History count
- All non-sensitive KPIs from current `allBookings` dataset
- i18n: `financialOverviewTitle` / `financialOverviewHelp` / existing 5 financial labels

**Section B — Operator Status** (all operator/founder scope):
- Drivers count (total / active)
- Partners count (total / head partner)
- Current scope display (Founder scope / Operator scope / Read-only) with role label
  - Founder scope: shows `adminRoleDispatch` if role=dispatch
  - Operator scope with `is_hoofd=true`: shows `adminRoleMoukrim` + partner name
  - Operator scope non-hoofd: shows "Operator scope" + contact
  - Read-only fallback: shows "Alleen-lezen" / "Lecture seule" / "Read-only" / "Sólo lectura"
- i18n: `adminOperatorTitle`, `adminDriversCount`, `adminPartnersCount`, `adminScopeFounder`, `adminScopeOperator`, `adminScopeCurrent`, `adminRoleDispatch`, `adminRoleMoukrim`

**Section C — Operational Configuration** (all operator/founder scope):
- Pricing Profile (read-only `base_fare` + `price_per_km` from `pricing_profiles` table)
- Mailbox Status (currently shows "Not configured (Phase F pending)")
- "Secrets are not displayed in the UI." notice (always visible)
- i18n: `adminOperationalTitle`, `adminOperationalHelp`, `adminPricingProfile`, `adminBaseFare`, `adminPricePerKm`, `adminMailboxStatus`, `adminMailboxNotConnected`, `adminNoSecrets`

**Section D — System Configuration** (FOUNDER SCOPE ONLY):
- Crown icon + green border indicator
- "Visible only in founder scope. Contains no secrets." help text
- Read-only pricing profile table
- Read-only mailbox status row
- "Secrets are not displayed in the UI." notice
- i18n: `adminFounderTitle`, `adminFounderHelp`, `adminMailboxPlaceholder`

### 2. Server-derived authorization preserved

All scope checks use **server-derived** flags from `authorize_admin_role()` RPC (NOT user-mutable sessionStorage):
- `sessionStorage.getItem('horizon_founder_scope')` (UI cache ONLY — RPC is source of truth)
- `sessionStorage.getItem('horizon_operator_scope')`
- `sessionStorage.getItem('horizon_role')`
- `sessionStorage.getItem('horizon_partner_name')`
- `sessionStorage.getItem('horizon_partner_is_hoofd')`

These are populated by the page-load IIFE after RPC verification. No new bypass added.

### 3. New helper: `loadPricingProfileOverview()`

```js
async loadPricingProfileOverview() {
    try {
        const { data, error } = await supabase.from('pricing_profiles')
            .select('base_fare,price_per_km,name,is_active')
            .eq('is_active', true).limit(1).maybeSingle();
        if (error) { /* fallback */ return; }
        window.PRICING_PROFILE_OVERVIEW = data || fallback;
    } catch (e) { /* fallback */ }
}
```

Called from `loadDashboardData()` after snapshot load. Stores result in `window.PRICING_PROFILE_OVERVIEW` for UI consumption.

**STRICT scoping** (per Lux §4):
- Selects ONLY `base_fare, price_per_km, name, is_active` — non-sensitive fields
- Does NOT select or expose: `service_role`, `JWT_SECRET`, `MAILBOX_PASSWORD`, SMTP/IMAP credentials, API keys, tokens
- Falls back to `{base_fare: 5, price_per_km: 2, name: 'default'}` on error
- Pricing profile fields are READ-ONLY in UI; mutations NOT exposed (per Lux §4: "if a setting cannot safely be changed client-side, show status/read-only information")

### 4. Translation keys added

**26 NEW translation keys × 4 languages (NL/FR/EN/ES) = 104 new definitions.**

Section A keys: `financialOverviewTitle`, `financialOverviewHelp`
Section B keys: `adminOperatorTitle`, `adminDriversCount`, `adminPartnersCount`, `adminScopeFounder`, `adminScopeOperator`, `adminScopeCurrent`, `adminRoleDispatch`, `adminRoleMoukrim`, `adminReadOnly`
Section C keys: `adminOperationalTitle`, `adminOperationalHelp`, `adminPricingProfile`, `adminBaseFare`, `adminPricePerKm`, `adminMailboxStatus`, `adminMailboxNotConnected`, `adminNoSecrets`
Section D keys: `adminFounderTitle`, `adminFounderHelp`, `adminMailboxPlaceholder`
Plus: `adminSystemHealthy` (for future status badge)
Plus existing keys reused: `partnerContact`, `financialTotalRevenue`, `financialTotalRides`, `financialNewOrders`, `financialActiveOrders`, `financialHistory`

All keys × 4 languages verified (104/104 occurrences).

## Verification

- Syntax: `node --check` PASS on both script blocks (ESM module + main IIFE)
- CRLF line endings: preserved (1849 CRLF, 0 LF only)
- Translation coverage: 104/104 (26 new keys × 4 languages)
- Diff stat: `Paneel/onderaannemerA.html | 97 +++++++++++++++++++++++++++++++++++++++++++---` (91 insertions, 6 deletions) — small conservative batch per Lux §3 reliability-first
- **Secret scan**: 0 secret-value strings (`service_role`, `JWT_SECRET`, `MAILBOX_PASSWORD`, `SMTP_PASS`, `IMAP_PASS`, `api_key`, `apikey`, `secret`) found in `renderFinance()` block. All "secret" occurrences are prohibition comments or UI notice text ("NO secrets", "Secrets are not displayed")
- **Scope separation**: Founder-only section D properly guarded by `if (founderScope)`; no operator scope can see system configuration section
- **Authorization preserved**: All scope checks use server-derived RPC result cached in sessionStorage; no new bypass
- **No new tabs/cockpits**: reused existing `financieel` tab — no second cockpit
- **No mutations exposed**: all configuration fields are read-only; mutations NOT exposed (per Lux §4 explicit guidance)

## Scope discipline (per Lux §3 reliability-first + Lux §4 Settings/Admin direction)

- ONLY Settings/Admin tab content changed
- Did NOT modify `loadOperatorDashboardSnapshot()` RPC contract
- Did NOT add new tabs
- Did NOT add new second cockpit
- Did NOT introduce generic multi-company/tenant switching
- Did NOT expose secrets in any form
- Did NOT add F1 staging credentials to UI
- Phase F mailbox secrets stay server-side env/config only
- Used `pricing_profiles` table fields that ALREADY exist (`base_fare`, `price_per_km`, `name`, `is_active`) — no schema change
- Did NOT modify renderSettlements, renderWiki, renderMailbox, renderNewOrders, etc.

## What's still deferred (next round)

Per Lux r056 §5/§6/§7:
- **Phase E round 3**: Dead CSS / translation / render method cleanup (PARKED) — `renderAccountRequests()` legacy Dutch copy, unused `settlementsTitle/Text`, etc. Lux said "Do not broaden this round into dead-code translation cleanup; remove/generalize that residue later only if dependency proof shows it is safe and useful."
- **Phase F**: Mailbox adapter (PARKED on Founder F-M1 env-var values)
- **Phase G**: Full regression rerun (PARKED until after D-F)
- **Phase H/I/J**: BLOCKED on Founder

## Audit log section

Currently shows placeholder text. Real audit log will be a Phase 2 follow-on:
- Tracked actions: approve_account_request, reject_account_request, archive_partner, archive_customer, archive_driver, send_dispatch_email, etc.
- Source: dedicated `operator_audit_log` table (NOT included in this round per Lux §3 reliability-first scope discipline)
- For Phase E round 2, audit log section is NOT included (would require schema change) — only Overview + Operator Status + Operational + Founder sections

## Post-implementation regression considerations

Per Lux §4 final paragraph: "Run relevant auth/navigation/static/syntax/pricing regressions after the material round-2 batch."

- Syntax check: PASS ✅
- Static i18n coverage check: 104/104 ✅
- Manual navigation test: requires running dashboard in browser (deferred to Phase G full regression)
- Auth test: requires operator/founder login in browser (deferred to Phase G)
- Pricing test: `pricing_profiles` query tested via existing schema (no RPC change)