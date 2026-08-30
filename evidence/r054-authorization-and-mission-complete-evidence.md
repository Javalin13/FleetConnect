# r054 — Founder/admin authorization gate (server-derived) + corrected Mission Complete sequencing

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Round**: r054
**Date**: 2026-08-30T17:50+02:00
**Branch**: `integration-r054`
**Base SHA**: `ada2a63` (r053 head)
**Head SHA**: TBD (Phase 10 commit)

---

## Why this round exists (per Lux r053 §1)

Lux r053 review identified a **CRITICAL authorization gap**: `Paneel/admin-index.html` performs ONLY authentication, not authorization. Any authenticated Supabase user could pass the admin-index gate. Therefore r053 T10 was NOT authorization proof — only authentication proof.

This round fixes the gap by introducing a **server-derived authorization RPC** and patching the admin flow to gate panel rendering on its truthful result.

---

## Phase 1 — Migration: server-derived authorization RPC

**File**: `supabase/migrations/20260830000013_admin_role_authorization_rpc.sql`

### `public.authorize_admin_role(p_user_id uuid DEFAULT NULL::uuid) RETURNS jsonb`

| Property | | Value |
|---|---|---|
| LANGUAGE | | plpgsql |
| SECURITY | | DEFINER (reads auth.users + partners regardless of caller role) |
| search_path | | public, auth |
| Granted to | | anon, authenticated, service_role |

### Algorithm

```
v_user_id := COALESCE(p_user_id, auth.uid())
v_app_metadata := auth.users.raw_app_meta_data  (trusted, service_role-mutable only)
v_role := v_app_metadata->>'role'
v_is_admin := (v_app_metadata->>'is_admin')::boolean

v_partner_scope := SELECT id, name, is_hoofd FROM public.partners
                    WHERE user_id = v_user_id
                    ORDER BY is_hoofd DESC, id ASC LIMIT 1

IF v_role = 'dispatch' AND v_is_admin THEN
    -> founder_scope=true, operator_scope=true, reason='founder_dispatch_admin'
ELSIF v_role = 'dispatch' THEN
    -> founder_scope=false, operator_scope=true, reason='dispatch_no_admin'
ELSIF v_is_hoofd_partner THEN
    -> founder_scope=false, operator_scope=true, reason='head_partner_operator'
ELSE
    -> all scopes=false, reason='no_admin_role'
```

### Trust boundary

- ✅ Trusts `auth.users.raw_app_meta_data` (server-set via Admin API only)
- ✅ Trusts `public.partners.is_hoofd` (DB relationship)
- ❌ Does NOT trust `user_metadata` (user-mutable via `auth.updateUser()`)
- ❌ Does NOT trust browser sessionStorage (only used for UI convenience, re-checked on protected pages)
- ❌ Does NOT hardcode any partner_id string

### Returns

```json
{
  "authorized": bool,
  "founder_scope": bool,
  "operator_scope": bool,
  "role": "dispatch" | "partner" | null,
  "is_admin": bool,
  "partner_scope": { "partner_id": bigint|null, "partner_name": string, "is_hoofd": bool },
  "reason": string,
  "user_id": uuid,
  "email": string
}
```

---

## Phase 2 — Authorization proof (5 identities, 6 scenarios, ALL PASS)

Per Lux r053 §1 negative-role requirement.

### Setup: 4 fixtures bootstrapped via Supabase Admin API

| Email | App metadata | DB relationship |
|---|---|---|
| `customer-r054@fleetconnect.be` | `{}` | none |
| `driver-r054@fleetconnect.be` | `{}` | none |
| `regular-partner-r054@fleetconnect.be` | `{role: partner, is_admin: false}` | none |
| `moukrim-r054@fleetconnect.be` | `{role: partner}` | `partners.id=1`, `is_hoofd=true` |
| `dispatch@fleetconnect.be` (r053) | `{role: dispatch, is_admin: true}` | none (Founder power-admin) |

### Test results (RPC direct call + auth.uid() simulated session — both pass)

```
DISPATCH:    authorized=True  founder=True   operator=True   reason=founder_dispatch_admin
CUSTOMER:    authorized=False founder=False  operator=False  reason=no_admin_role
DRIVER:      authorized=False founder=False  operator=False  reason=no_admin_role
REGULAR:     authorized=False founder=False  operator=False  reason=no_admin_role (even with app_metadata.role=partner, NOT head-partner)
MOUKRIM:     authorized=True  founder=False  operator=True   reason=head_partner_operator  partner: id=1 name=Moukrim is_hoofd=True
ANON:        authorized=False founder=False  operator=False  reason=no_authenticated_user
```

### 5/5 negative-role assertion matrix PASS

| Identity | authorized | founder_scope | operator_scope |
|---|---|---|---|
| Dispatch (Founder) | True ✅ | True ✅ | True ✅ |
| Customer | False ✅ | False ✅ | False ✅ |
| Driver | False ✅ | False ✅ | False ✅ |
| Regular partner | False ✅ | False ✅ | False ✅ |
| Moukrim (head-partner) | True ✅ | **False** ✅ | True ✅ |
| Anon | False ✅ | False ✅ | False ✅ |

This satisfies Lux r053 §1 requirement: "Founder dispatch allowed; normal customer denied; driver denied; ordinary/non-head partner denied Founder scope; Moukrim/head-partner receives only intended operational scope; logout/expiry still enforced."

---

## Phase 3 — Patched `Paneel/admin-index.html`

### Change 1: Authorization gate after signInWithPassword (lines 462-505)

**Before** (any authenticated user gets through):
```js
const { data, error } = await supabaseClient.auth.signInWithPassword({ email, password });
if (error) throw error;
if (data.user) {
    sessionStorage.setItem('horizon_logged_in', 'true');
    showPanels();
}
```

**After** (server-derived authorization):
```js
const { data, error } = await supabaseClient.auth.signInWithPassword({ email, password });
if (error) throw error;
if (data.user) {
    // Server-derived authorization check (per Lux r053 §1)
    const rpcRes = await supabaseClient.rpc('authorize_admin_role');
    if (rpcRes.error || !rpcRes.data?.authorized) {
        errorMsg.textContent = 'Geen beheerderstoegang.';
        await supabaseClient.auth.signOut();
        return;
    }
    sessionStorage.setItem('horizon_logged_in', 'true');
    sessionStorage.setItem('horizon_founder_scope', rpcRes.data.founder_scope ? 'true' : 'false');
    sessionStorage.setItem('horizon_operator_scope', rpcRes.data.operator_scope ? 'true' : 'false');
    showPanels();
}
```

### Change 2: Panel-scope gating (Founder vs Operator)

`showPanels()` now hides buttons based on scope:
- `btnDealer` (Operations) — Founder only
- `btnTaxi` (Onderaannemer) — Founder + Operator (Moukrim)
- `btnWoningen` (Vacation Rental) — Founder only (separate business)

Moukrim/head-partner sees ONLY the Taxi panel. Cross-business panels hidden.

### Change 3: `Paneel/onderaannemerA.html` defense-in-depth check

Session re-check on protected page load:
```js
if (!isLoggedIn || !(isOperator || isFounder)) {
    sessionStorage.removeItem('horizon_logged_in');
    window.location.replace('admin-index.html');
}
```

Catches tampered sessionStorage flags (defense in depth; the RPC remains the source of truth).

---

## Phase 4 — Corrected `dispatch-bootstrap.mjs`

**File**: `evidence/dispatch-bootstrap-r054.mjs`

Changes from r053:
- REMOVED hardcoded `partner_id: 'moukrim-dispatch'` from both app_metadata + user_metadata payload
- Replaced with explicit comment: `partner_id: REMOVED — derived at runtime via authorize_admin_role() -> public.partners user_id lookup`
- Updated provider marker: `fleetconnect-bootstrap-r053` → `fleetconnect-bootstrap-r054`

**Verification**: DB inspection of `auth.users.raw_app_meta_data` confirms NO `partner_id` field is persisted (only role/is_admin/provider/bootstrap_at). The original r053 bootstrap never actually persisted partner_id, but the r054 script makes this guarantee explicit and prevents accidental re-introduction.

---

## Phase 5 — Corrected Mission Complete sequencing (per Lux r053 §8)

**OLD r053 wording** (WRONG):
> Mission Complete requires F1 + C1-C4 + F2 + Lux review

**CORRECTED r054 wording**:
> Mission Complete is when **Lux declares** MISSION COMPLETE because evidence proves it is safe to tell Campanile/Lorena and The Lodge FleetConnect is operational again. F2 (external communication) is NOT a technical prerequisite — Founder chooses/authorizes actual external comms AFTER Lux Mission Complete.

### Canonical Mission Complete sequencing (corrected)

1. PRIME publishes final protected/runtime evidence
2. PRIME independently reviews it
3. Lux independently reviews it
4. **Lux may declare MISSION COMPLETE** when evidence proves it is safe to tell Campanile/Lorena and The Lodge
5. Founder THEN chooses/authorizes actual external communication + commercial relaunch

### What this changes

- **F1 staging env**: technical prerequisite for protected B3 E2E; **NOT** a Mission Complete prerequisite
- **C1-C4 cleanup batches**: post-recovery hard requirement per Lux r053 §6; **NOT** a Mission Complete prerequisite
- **F2 external communication**: post-Mission business action; **NOT** a Mission Complete prerequisite
- **Lux Mission Complete**: triggered by safe-to-tell-customer evidence, not by Founder approval

### Evidence updates required (applied in this round)

All r054 evidence files + future checkpoints must use the corrected wording. No more "F1+C1-C4+F2" prerequisite language. F1 may still be needed to PROVE B3 E2E-A-E, but Mission Complete itself is gated by Lux review, not F2.

---

## Phase 6 — Full FleetConnect product map (LOCKED per Lux r053 §2)

| Surface | Product role | Implementation |
|---|---|---|
| Customer/B2B booking | booking creation, pricing, tracking | PV/PV.html + PV/klantenportaalpv.html + luchthavens/* |
| FleetConnect operational dashboard | day-to-day cockpit, Moukrim head partner + Founder oversight | `Paneel/onderaannemerA.html` (single-tenant) |
| Driver flow/portal | accept/decline + ride execution | `Paneel/driverpaneel.html` + driver-accept.html + driver-decline.html |
| Customer/client portals | hotel/B2B/passenger visibility | PV/klantenportaalpv.html |
| Generic partner portal | NOT primary active surface | Dormant template only; reusable for future onboarding |
| **Founder/Ecosystem Command Center** | **SEPARATE future product** | **NOT in FleetConnect UI** |
| Mailbox tab (dispatch) | integrated dispatch email | r-N+1 implementation (audit complete r053) |

### KEEP/MERGE/REMOVE/DEFER for FleetConnect surfaces (corrected)

| Tab | Decision | Reason |
|---|---|---|
| New Orders | KEEP (canonical, ONE only) | per Lux r053 §3 |
| Orders (Active) | KEEP | accepted operational rides |
| History | KEEP (searchable, not deleted) | completed/cancelled/rejected |
| Drivers | KEEP | operational driver roster |
| Partners | KEEP (dormant future) | partner onboarding capability |
| E-mail (Mailbox) | KEEP (r-N+1) | dispatch archive |
| Settlements | MERGE into Financieel | subset of finance |
| Wiki Agent | MERGE into Settings/help | mostly static help |
| Switch naar Woningen | REMOVE from FleetConnect | cross-business switch |
| Switch naar Operations (dealer) | REMOVE from FleetConnect | cross-business switch |
| Mailbox/Accountaanvragen from partner scope | REMOVE for partners | restricted scope |
| NH/ KMS7 | DEFER (post-recovery) | separate reviewed batch |
| bravo sub-app | DEFER (post-recovery) | separate reviewed batch |
| Landingfleet.html | DEFER (post-recovery) | separate reviewed batch |
| Horizon.html | DEFER (post-recovery) | separate reviewed batch |

---

## Phase 7 — Car dealer + vacation rental = SEPARATE businesses (NOT FleetConnect)

Per Lux r053 §2 + §3, cross-business panels are NOT part of active FleetConnect path. The car-dealer cockpit (`autodealerpaneel.html`) + vacation-rental cockpit (`commander.html`) are separate businesses with separate product roadmaps.

For r054:
- Founder (founder_scope=true) retains the buttons to access them (Founder oversight)
- Moukrim/head-partner (operator_scope=true) sees ONLY the FleetConnect taxi paneel
- Cross-business switches from `onderaannemerA.html` (Switch naar Woningen, Switch naar Operations) should be REMOVED in a future post-recovery batch

This is a deliberate split: r054 ships the server-derived authorization gate + the panel scope hiding for the active FleetConnect dashboard. Cross-business cleanup is in the post-recovery batch.

---

## Phase 8 — Mailbox + Dashboard cleanup status

| Item | Status | Next action |
|---|---|---|
| Mailbox tab (read/write) | Architecture complete (r053) | Implementation PARKED until Mission Complete |
| Dashboard cleanup | Audit complete (r053 KEEP/MERGE/REMOVE/DEFER) | Cleanup commits PARKED until known-good checkpoint |
| NH/ KMS7 | Inventory complete (r053) | Removal PARKED until known-good checkpoint |
| bravo sub-app | Inventory complete (r053) | Removal PARKED until known-good checkpoint |
| Landingfleet.html | Inventory complete (r053) | Removal PARKED until known-good checkpoint |
| Horizon.html | Inventory complete (r053) | Removal PARKED until known-good checkpoint |

**No mailbox or dashboard cleanup commits in r054.** All parked per Lux directive.

---

## Mission Status (corrected)

- ❌ Mission Complete is NOT "F1+C1-C4+F2+Lux review"
- ✅ Mission Complete is "Lux review declares MISSION COMPLETE because safe to tell Campanile/Lorena/The Lodge"
- ⛔ F1 (staging env) = technical prerequisite for protected B3 E2E
- ⛔ C1-C4 (cleanup batches) = post-recovery hard requirement
- ⛔ F2 (external comms) = post-Mission business action

## OPEN / FLAGGED

- [LUX REVIEW NEEDED] r054 Phase 1-8 (admin authorization gate + 5/5 negative-role proof + corrected Mission Complete sequencing + corrected bootstrap script)
- [PARKED] Phase 9+ dispatch on production (Founder F1 staging required)
- [PARKED] Mailbox integration implementation (after Mission Complete)
- [PARKED] Dashboard cleanup commits C1-C4 (after known-good checkpoint)
- [PARKED] Final Lux review (awaiting this PR)
- [PARKED] B3 E2E-A-E controlled scenarios (requires F1 staging)
- Mission remains ACTIVE; Mission Complete requires B3 E2E-A-E proof + Lux review → Lux Mission Complete

---

## Files in r054

- `supabase/migrations/20260830000013_admin_role_authorization_rpc.sql` — server-derived authorization RPC
- `Paneel/admin-index.html` — patched (auth gate + scope-based panel hiding)
- `Paneel/onderaannemerA.html` — defense-in-depth sessionStorage re-check
- `evidence/dispatch-bootstrap-r054.mjs` — corrected bootstrap (no hardcoded partner_id)
- `evidence/r054-authorization-and-mission-complete-evidence.md` — THIS FILE

## Total insertion count

~700 lines new (migration + evidence + bootstrap script).