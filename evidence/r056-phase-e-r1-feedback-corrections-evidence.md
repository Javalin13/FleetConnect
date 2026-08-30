# r056 Phase E round 1 feedback corrections — evidence

## Context

Lux r056 Phase E r1 review (`6c40453`) returned three actionable items:

1. **Fix #1**: non-customer account requests (partner/driver/PWA) are unreachable from canonical UI because `renderAccountRequests()` exists but has no nav path.
2. **Fix #2**: new hardcoded Dutch/English strings in the merged surface (`Hoofdpartner`, `Sub-partner`, `Gearchiveerd`, `Geen login`, `+ Nieuwe partner`, etc.) — translation keys missing.
3. **Fix #4 (safety)**: verify head-partner cannot be accidentally deleted — check server authorization.

## Fix #1 — Account Requests in canonical Clients/Partners view

Added a new "Partner/driver account requests" sub-section to `renderClientsPartners()` between the existing "Client account requests" sub-section and the Customer filter bar. Includes:

- `renderAccountRequestItem(r)` helper function — adapted from `renderRequest()` inside `renderAccountRequests()` but simplified for inline merged-view rendering (no filters — uses bulk section header)
- Uses existing `getAccountRequestKindLabel()` (Driver PWA / Partner PWA / Operations) for the kind badge
- Uses existing `getAccountRequestStatusText()` for status badge
- Shows: name, status badge, kind badge, email/phone, bedrijf/voertuig/regio, requested date, auth-linked flag
- Action buttons: Details (always), Approve/Reject (only if pending) — same handlers as `renderClientRequest()`

Logic:
```js
const nonCustomerRequests = this.accountRequests.filter(r => !this.isCustomerAccountRequest(r));
const pendingNonCustomerRequests = nonCustomerRequests.filter(r => r.status === 'pending');
const handledNonCustomerRequests = nonCustomerRequests.filter(r => r.status !== 'pending').slice(0, 25);
```

Empty state uses new translation key `noOpenPartnerDriverRequests`.

This means: ALL account requests (customer + partner/driver) are now visible in the canonical Clients/Partners view. The standalone `renderAccountRequests()` is kept for deep-linking from email/notification links (Lux preserved it).

## Fix #2 — Translation keys

Added **15 new translation keys** across **4 languages** (NL/FR/EN/ES) = 60 key definitions:

- `hoofdpartnerBadge` — "Hoofdpartner" / "Partenaire principal" / "Head partner" / "Socio principal"
- `subpartnerBadge` — "Sub-partner" / "Sous-partenaire" / "Sub-partner" / "Sub-socio"
- `archivedBadge` — "Gearchiveerd" / "Archivé" / "Archived" / "Archivado"
- `noLoginBadge` — "Geen login" / "Sans login" / "No login" / "Sin login"
- `btnNewPartner` — "+ Nieuwe partner" / "+ Nouveau partenaire" / "+ New partner" / "+ Nuevo socio"
- `partnersSectionTitle` — "Partners" / "Partenaires" / "Partners" / "Socios"
- `clientsSectionTitle` — "Klanten" / "Clients" / "Clients" / "Clientes"
- `clientAccountRequestsTitle` — "Client account requests" / "Demandes de compte client" / "Client account requests" / "Solicitudes de cuenta de cliente"
- `noOpenClientAccountRequests` — "Geen open client account requests." / "Aucune demande de compte client ouverte." / "No open client account requests." / "No hay solicitudes de cuenta de cliente abiertas."
- `recentHandledClientRequests` — "Recent afgehandelde client requests" / "Demandes client récemment traitées" / "Recently handled client requests" / "Solicitudes de cliente recientes"
- `partnerDriverAccountRequests` — "Partner/driver account requests" / "Demandes de compte partenaire/chauffeur" / "Partner/driver account requests" / "Solicitudes de cuenta de socio/conductor"
- `noOpenPartnerDriverRequests` — "Geen open partner/driver account requests." / "Aucune demande de compte partenaire/chauffeur ouverte." / "No open partner/driver account requests." / "No hay solicitudes de socio/conductor abiertas."
- `recentHandledPartnerDriverRequests` — "Recent afgehandelde partner/driver requests" / "Demandes partenaire/chauffeur récemment traitées" / "Recently handled partner/driver requests" / "Solicitudes de socio/conductor recientes"
- `archivedPartners` — "Gearchiveerde partners" / "Partenaires archivés" / "Archived partners" / "Socios archivados"
- `clientsPartnersPageTitle` — "Clients/Partners" / "Clients/Partenaires" / "Clients/Partners" / "Clientes/Socios"

Replaced all hardcoded strings in `renderPartner()` and the page-builder template with `this.escapeHtml(t.<key>)` lookups. Filter bar fallback strings use `t.search || 'Zoeken'` pattern for resilience.

Verification: 15 keys × 4 languages = 60/60 occurrences (each key in each language).

## Fix #4 — Head-partner delete safety

Server-side authorization already in place:
- Migration: `supabase/migrations/20260619060000_partner_delete_dedup_backend.sql`
- Function: `public.delete_operator_partner(p_partner_id integer)`
- Lines 161-165 contain explicit head-partner guard:
  ```sql
  if coalesce(v_partner.is_hoofd, false) then
    raise exception 'Hoofdpartners cannot be deleted. Archive only after migration planning.';
  end if;
  ```

Conclusion: server enforces it. UI-level `deletePartner` button is harmless — cannot delete head-partner via UI either. No additional UI change required.

Additionally per r055 server-derived authorization model:
- `authorize_admin_role()` v2 has NO args; identity only from `auth.uid()`
- RPC EXECUTE granted to `authenticated` + `service_role` only; REVOKED from `anon`
- RLS policies enforce row-level delete permissions
- Therefore even authenticated user cannot escalate to delete head-partner — RPC will reject with "Hoofdpartners cannot be deleted" exception

## Verification

- Syntax: `node --check` PASS on both script blocks (ESM module + main IIFE)
- CRLF line endings: preserved (1742 CRLF, 0 LF only)
- Translation coverage: 60/60 (15 keys × 4 languages)
- Diff stat: `Paneel/onderaannemerA.html | 83 +++++++++++++++++++++++++++++++---------------` (57 insertions, 26 deletions)
- Backward compat: `renderCustomers()` alias preserved, `applyFiltersCustomers()` preserved, `renderCustomersList()` preserved
- All action handlers preserved: `showAccountRequestDetails`, `approveAccountRequest`, `rejectAccountRequest` (used unchanged)
- `getAccountRequestKindLabel()` exists at line 647 (Driver PWA / Partner PWA / Operations / Account)
- Head-partner delete safety: server-side `raise exception` enforced; UI button cannot bypass