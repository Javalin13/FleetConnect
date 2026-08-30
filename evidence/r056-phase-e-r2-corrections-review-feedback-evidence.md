# r056 Phase E round 2 corrections review feedback — evidence

## Context

Lux r056 Phase E r2 review (`9502af5`) returned:

**Direction ACCEPTED** (Lux §1):
- Settings/Admin redesign is directionally correct
- Overview, Operator Status, Operational Configuration, Founder-only System Configuration
- No second cockpit; no secrets in UI; pricing/configuration read-only
- Multilingual preserved

**REMAINING DEFECTS:**
- §2 REQUIRED FIX #1: `renderFinance()` trusted scope from sessionStorage (mutable). Must use fresh `authorize_admin_role()` server response.
- §3 REQUIRED FIX #2: `loadPricingProfileOverview()` fabricates `{base_fare: 5, price_per_km: 2}` on failure → must show "Unavailable" instead.
- §3 REQUIRED FIX #2b: `activeDriversCount` uses `d.user_id` (auth link presence) instead of operational state.

## Fix #1 — Trusted server-derived scope (r055 authorization boundary preserved)

Changed `renderFinance()` from synchronous (sessionStorage-driven) to **async** with fresh `authorize_admin_role()` RPC call:

```js
async renderFinance() {
    // Trusted re-authorization via server-side authorize_admin_role() RPC.
    // sessionStorage may MIRROR this trusted response, but the gate is the RPC.
    let trustedAuthz = null;
    let trustedError = null;
    try {
        const rpcRes = await supabase.rpc('authorize_admin_role');
        if (rpcRes.error) throw rpcRes.error;
        trustedAuthz = rpcRes.data || null;
    } catch (e) {
        trustedError = e?.message || String(e);
        console.warn('renderFinance: trusted re-authorization failed:', trustedError);
    }
    const founderScope = !!(trustedAuthz && trustedAuthz.founder_scope);
    const operatorScope = !!(trustedAuthz && trustedAuthz.operator_scope);
    const trustedAuthorized = !!(trustedAuthz && trustedAuthz.authorized);
    const role = (trustedAuthz && trustedAuthz.role) || '';
    const partnerScope = (trustedAuthz && trustedAuthz.partner_scope) || null;
    const partnerName = partnerScope?.partner_name || '';
    const partnerIsHoofd = !!(partnerScope && partnerScope.is_hoofd);
    // ...
}
```

**Founder-only section** now gated by **trusted** `founderScope` (not sessionStorage cache):

```js
// Founder-only section: gated STRICTLY by trusted server-derived founder_scope.
// If trusted re-authorization failed OR founder_scope is false, this section
// is NEVER rendered — even if sessionStorage cache says otherwise.
if (trustedAuthorized && founderScope) { /* render founder-only section */ }
```

**Current scope display** also uses trusted response:
- `!trustedAuthorized` → "Scope unknown — re-authorization required" (new `adminScopeUnknown` key)
- `founderScope` → "Founder scope — Dispatch / Power admin"
- `operatorScope` + `is_hoofd=true` → "Operator scope — Head partner (Moukrim) [name]"
- `operatorScope` non-hoofd → "Operator scope — Contact"
- otherwise → "Read-only"

**Verification**: `sessionStorage` reads in `renderFinance()` block = 0 (only mentions in comments explaining the policy). `authorize_admin_role` uses in block = 1 (the trusted re-authz call). `trustedAuthorized` variable present and used for founder-section gate.

r055 server-derived authorization boundary preserved:
- `authorize_admin_role()` v2 has NO args; identity from `auth.uid()` only
- EXECUTE granted only to `authenticated` + `service_role`; REVOKED from `anon`
- RLS policies enforce row-level delete permissions
- No new bypass added

## Fix #2 — Truthful unavailable state (no synthetic pricing fallback)

`loadPricingProfileOverview()` now sets explicit `available: false` on failure/no-data instead of fabricating fallback values:

```js
async loadPricingProfileOverview() {
    try {
        const { data, error } = await supabase.from('pricing_profiles')
            .select('base_fare,price_per_km,name,is_active')
            .eq('is_active', true).limit(1).maybeSingle();
        if (error) { console.warn('loadPricingProfileOverview warning:', error.message); window.PRICING_PROFILE_OVERVIEW = { available: false }; return; }
        if (!data) { window.PRICING_PROFILE_OVERVIEW = { available: false }; return; }
        window.PRICING_PROFILE_OVERVIEW = { available: true, base_fare: data.base_fare, price_per_km: data.price_per_km, name: data.name };
    } catch (e) {
        console.warn('loadPricingProfileOverview failed:', e?.message || e);
        window.PRICING_PROFILE_OVERVIEW = { available: false };
    }
}
```

`renderFinance()` reads the `available` flag and renders truthful state:

```js
const pricing = (typeof window !== 'undefined' && window.PRICING_PROFILE_OVERVIEW) || { available: false };
const pricingAvailable = !!pricing.available;
const pricingValueText = pricingAvailable
    ? `EUR ${Number(pricing.base_fare).toFixed(2)} · €${Number(pricing.price_per_km).toFixed(2)}/km`
    : this.escapeHtml(t.adminUnavailable);
const pricingLabelText = pricingAvailable
    ? this.escapeHtml(pricing.name || 'default')
    : this.escapeHtml(t.adminPricingUnavailable);
```

**Verification**: synthetic fallback string `'base_fare: 5, price_per_km: 2'` no longer present anywhere in `renderFinance()` block.

Internal €2.00/km canonical pricing doctrine unchanged — only truthful diagnostics changed.

## Fix #2b — Active drivers from operational state (not auth link)

```js
// Per Lux review §3: active = operational state, not auth link presence
const activeDriversCount = (this.drivers || []).filter(d => d.is_active !== false && !d.archived_at).length;
```

Matches existing canonical pattern used elsewhere in the dashboard (e.g. line 711 `driverOptions`, line 843 `activeDrivers`).

Added label hint: `(${this.escapeHtml(t.adminDriversActiveNote)})` — explains the operational state semantics.

## New translation keys

4 new keys × 4 languages = 16 new definitions:
- `adminUnavailable` — "Niet beschikbaar" / "Non disponible" / "Unavailable" / "No disponible"
- `adminPricingUnavailable` — "Pricing profiel niet geladen" / "Profil tarifaire non chargé" / "Pricing profile not loaded" / "Perfil de tarifas no cargado"
- `adminScopeUnknown` — "Scope onbekend — re-autorisatie vereist" / "Scope inconnu — ré-autorisation requise" / "Scope unknown — re-authorization required" / "Scope desconocido — re-autorización requerida"
- `adminDriversActiveNote` — "Operationele status (is_active)" / "Statut opérationnel (is_active)" / "Operational status (is_active)" / "Estado operativo (is_active)"

## Verification

- Syntax: `node --check` PASS on both script blocks (ESM module + main IIFE)
- CRLF line endings: preserved (1898 CRLF, 0 LF only)
- Translation coverage: 16/16 (4 new keys × 4 languages)
- `sessionStorage` reads in `renderFinance()` block: 0 (only mentions in policy comments)
- `authorize_admin_role` uses in `renderFinance()` block: 1 (trusted re-authz)
- `trustedAuthorized && founderScope` gate for founder-only section: present
- Synthetic pricing fallback removed: verified (string `'base_fare: 5, price_per_km: 2'` not present)
- Active drivers operational filter: present (`d.is_active !== false && !d.archived_at`)
- `async renderFinance()` signature: present (required for `await supabase.rpc(...)`)
- Diff stat: `Paneel/onderaannemerA.html | 103 +++++++++++++++++++++++++++++++++------------` (76 insertions, 27 deletions) — small conservative batch per Lux §3 reliability-first

## Scope discipline (per Lux §3 reliability-first)

- ONLY Settings/Admin rendering + `loadPricingProfileOverview` + 4 new translation keys
- Did NOT modify `loadOperatorDashboardSnapshot()` RPC contract
- Did NOT add new tabs
- Did NOT add new second cockpit
- Did NOT modify r055 `authorize_admin_role()` RPC
- Did NOT weaken or change the accepted r055 RPC authorization model
- Did NOT broaden into Phase F or dead-code cleanup (per Lux §4 explicit instruction)