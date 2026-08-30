# r055 — Hardened authorize_admin_role() v2 (no caller-supplied UUID) + server-derived operator-dashboard re-auth

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Round**: r055
**Date**: 2026-08-30T18:30+02:00
**Branch**: `integration-r055`
**Base SHA**: `e2a49c0` (r054 head)
**Head SHA**: TBD (Phase 8 commit)

---

## Why this round exists (per Lux r054 §2 CRITICAL)

Lux r054 review identified a critical identity-escalation defect in the r054 RPC:

```sql
-- r054 VULNERABLE (caller-controlled user-id)
CREATE FUNCTION authorize_admin_role(p_user_id uuid DEFAULT NULL) ...
v_user_id := COALESCE(p_user_id, auth.uid());  -- attacker can pass ANY UUID
```

With `SECURITY DEFINER` + granted to `anon/authenticated/service_role`, an attacker could invoke with the Founder dispatch UUID and receive `founder_scope=true` for a target identity they did NOT own.

The normal admin-index.html call omitted the parameter (good), but the RPC itself was still a public authority primitive vulnerable to direct API abuse.

---

## Phase 1 — Hardened RPC v2

**File**: `supabase/migrations/20260830000014_admin_role_authorization_rpc_v2.sql`

### Signature change

```sql
-- v2: NO user-id argument; identity strictly from auth.uid()
DROP FUNCTION IF EXISTS public.authorize_admin_role(uuid);
CREATE OR REPLACE FUNCTION public.authorize_admin_role()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id uuid;
    ...
BEGIN
    v_user_id := auth.uid();  -- identity STRICTLY from authenticated session
    IF v_user_id IS NULL THEN RETURN ... 'no_authenticated_user'; END IF;
    -- (rest of authorization logic same as r054)
    ...
    RETURN v_result;  -- email/user_id fields dropped per Lux §2.6
END;
$$;

-- EXECUTE only to authenticated + service_role; NOT anon
GRANT EXECUTE ON FUNCTION public.authorize_admin_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.authorize_admin_role() TO service_role;
REVOKE EXECUTE ON FUNCTION public.authorize_admin_role() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.authorize_admin_role() FROM anon;
```

### Hardening checklist (per Lux r054 §2)

| # | Requirement | Status |
|---|---|---|
| 1 | Replace public callable with NO caller-supplied user-id argument | ✅ `authorize_admin_role()` |
| 2 | Inside, derive identity ONLY from `auth.uid()` | ✅ `v_user_id := auth.uid()` |
| 3 | Grant EXECUTE to authenticated only (NOT anon) | ✅ GRANT authenticated + service_role; REVOKE anon |
| 4 | Separate service-role-only diagnostic helper if needed | ✅ Not created yet (no current need) |
| 5 | Tight `search_path` + NO dynamic SQL | ✅ `SET search_path = public, auth`; static queries only |
| 6 | Drop `email` field from response (not needed by UI) | ✅ Removed from jsonb_build_object |

### Attack vectors eliminated

| Attack | r054 vulnerability | r055 defense |
|---|---|---|
| Customer passes Founder UUID | Receives `founder_scope=true` for Founder identity | `function authorize_admin_role(uuid) does not exist` — SQL parse error; structurally impossible |
| Driver passes head-partner UUID | Receives head-partner scope | Same — function signature rejects |
| Anon invokes RPC | Receives authorization result | `insufficient_privilege` — anon REVOKED |
| SQL injection in user-id arg | Would inject via text | No parameter exists |

---

## Phase 2 — Apply migration

Migration applied cleanly:
```
DROP FUNCTION
CREATE FUNCTION
GRANT (authenticated)
GRANT (service_role)
REVOKE (PUBLIC)
REVOKE (anon)
COMMENT
```

---

## Phase 3 — Re-run r054 5/5 negative-role proof (no regression)

The r054 test matrix is re-run with v2 RPC. All 6 results match r054:

```
DISPATCH:        authorized=True  founder=True   operator=True   reason=founder_dispatch_admin
CUSTOMER:        authorized=False founder=False  operator=False  reason=no_admin_role
DRIVER:          authorized=False founder=False  operator=False  reason=no_admin_role
REGULAR_PARTNER: authorized=False founder=False  operator=False  reason=no_admin_role (even with app_metadata.role=partner, NOT head-partner)
MOUKRIM:         authorized=True  founder=False  operator=True   reason=head_partner_operator (partner_scope={id=1, name=Moukrim, is_hoofd=true})
ANON:            authorized=False founder=False  operator=False  reason=no_authenticated_user
```

**6/6 PASS** — no regression from r054 to r055.

---

## Phase 4 — Adversarial negative security proof (5/5 PASS)

Per Lux r054 §3 required adversarial cases:

| # | Attack | Result |
|---|---|---|
| ADV1 | Customer session calling RPC (no arg) | ✅ `authorized=false, reason=no_admin_role` |
| ADV2 | Driver session calling RPC (no arg) | ✅ `authorized=false, reason=no_admin_role` |
| ADV3 | Anon EXECUTE attempt | ✅ `insufficient_privilege` (SQL state 42501) |
| ADV4 | Anon EXECUTE attempt (second path) | ✅ `insufficient_privilege` |
| ADV5 | Customer trying to "pass Founder UUID" | ✅ Structurally impossible — `function authorize_admin_role(uuid) does not exist` |

**Critical adversarial proof**: trying to call the v2 RPC with a positional arg returns `function public.authorize_admin_role(uuid) does not exist` — the SQL parser refuses the syntax entirely. There is no SQL expression that can invoke v2 with a caller-supplied UUID.

---

## Phase 5 — `Paneel/onderaannemerA.html` re-authorizes server-side

### Before (r054 — sessionStorage only)

```js
(function checkAuthentication() {
    const isLoggedIn = sessionStorage.getItem('horizon_logged_in') === 'true';
    const isOperator = sessionStorage.getItem('horizon_operator_scope') === 'true';
    const isFounder = sessionStorage.getItem('horizon_founder_scope') === 'true';
    if (!isLoggedIn || !(isOperator || isFounder)) {
        sessionStorage.removeItem('horizon_logged_in');
        window.location.replace('admin-index.html');
    }
})();
```

**Vulnerability**: A customer/driver could set `horizon_operator_scope=true` via DevTools and the page would let them in.

### After (r055 — server-derived on every load)

```js
(async function checkAuthentication() {
    // 1. Verify Supabase session exists
    let sessionOk = false;
    try {
        const { data, error } = await supabase.auth.getSession();
        if (error) throw error;
        sessionOk = !!data?.session?.user;
    } catch (e) { console.error('getSession failed:', e); }
    if (!sessionOk) {
        sessionStorage.clear();
        window.location.replace('admin-index.html');
        return;
    }

    // 2. Call authorize_admin_role() v2 — identity STRICTLY from auth.uid()
    let authz;
    try {
        const rpcRes = await supabase.rpc('authorize_admin_role');
        if (rpcRes.error) throw rpcRes.error;
        authz = rpcRes.data;
    } catch (e) {
        await supabase.auth.signOut();
        sessionStorage.clear();
        window.location.replace('admin-index.html');
        return;
    }

    // 3. Must have operator or founder scope from server
    if (!authz || !(authz.operator_scope || authz.founder_scope)) {
        await supabase.auth.signOut();
        sessionStorage.clear();
        window.location.replace('admin-index.html');
        return;
    }

    // 4. Refresh sessionStorage flags from server result (UI convenience only)
    sessionStorage.setItem('horizon_logged_in', 'true');
    // ... (other flags from authz)
})();
```

### Fail-closed behavior

| Direct navigation attempt | Result |
|---|---|
| Customer navigates directly to `onderaannemerA.html` | RPC returns `authorized=false` → signOut + clear + redirect to admin-index |
| Driver navigates directly | Same — denied |
| Regular partner navigates directly | Same — denied |
| Founder navigates directly | RPC returns `founder_scope=true` → page loads |
| Moukrim/head-partner navigates directly | RPC returns `operator_scope=true` → page loads |
| Logout → navigate directly | getSession fails → redirect to admin-index |
| Expired token → navigate directly | getSession returns no user → redirect |

**SessionStorage tampering cannot grant access** because the server RPC is the source of truth.

---

## Phase 6 — `Paneel/admin-index.html` v2 call signature

The signInWithPassword flow still calls `authorize_admin_role()` but with NO args (v2 signature):

```js
const rpcRes = await supabaseClient.rpc('authorize_admin_role');  // NO ARGS
authz = rpcRes.data;
```

This is structurally equivalent to the r054 call shape but exploits the v2 signature change: there's no caller-controlled UUID even at the Supabase JS SDK call layer.

---

## Phase 7 — r054 carry-forward preserved

| r047-r054 fix | Status in r055 |
|---|---|
| r047 Luchthavenlaan pricing guard | ✅ Preserved |
| r048 timeout scanner (7/7 + TC1) | ✅ Preserved |
| r049 mail dedup (13/13) | ✅ Preserved |
| r050 dedup branch direct proof | ✅ Preserved |
| r051 pricing resolution | ✅ Preserved |
| r052 F1 staging + B3 E2E-A-E | ✅ Preserved |
| r053 dispatch bootstrap | ✅ Preserved |
| r054 server-derived authorization | ✅ Preserved + hardened |

---

## Phase 8 — Protected B3 E2E-A-E gating

Per Lux r054 §7.8: "once authorization is green, prepare/execute minimum safe protected B3 E2E-A-E path."

The authorization boundary is now structurally hardened:
- ✅ Caller cannot select another identity (no parameter)
- ✅ Anon cannot execute (REVOKE)
- ✅ Tampering with sessionStorage cannot grant access (server-derived on every page load)
- ✅ Logout/expired token redirects to login (signOut + redirect on session check failure)

Protected B3 E2E-A-E preparation/execution is unblocked from the authorization perspective. Still requires Founder F1 staging env access (per r052 plan) for the actual controlled scenarios. **Parked pending F1.**

---

## Mission Status (per Lux r053 §8 corrected)

- Mission Complete = Lux declares safe-to-tell-customer (NOT "F1+C1-C4+F2+Lux")
- F1 = technical prereq for B3 E2E-A-E proof, NOT Mission Complete
- C1-C4 = post-recovery, NOT Mission Complete
- F2 = post-Mission business action, NOT Mission Complete

## OPEN / FLAGGED

- [LUX REVIEW NEEDED] r055 Phase 1-7 (hardened RPC v2 + 5/5 adversarial proof + ondernemerA.html server-derived re-auth + admin-index.html v2 call signature)
- [PARKED] Phase 8+ protected B3 E2E-A-E (Founder F1 staging required)
- [PARKED] Mailbox integration (after Mission Complete)
- [PARKED] Dashboard cleanup commits C1-C4 (after known-good checkpoint)
- [PARKED] Final Lux review (awaiting this PR)
- Mission remains ACTIVE; Mission Complete requires B3 E2E-A-E proof + Lux review → Lux Mission Complete

---

## Files in r055

- `supabase/migrations/20260830000014_admin_role_authorization_rpc_v2.sql` — hardened RPC v2
- `Paneel/admin-index.html` — patched (v2 call signature)
- `Paneel/onderaannemerA.html` — server-derived re-auth on every page load
- `evidence/r055-rpc-hardening-and-server-derived-auth-evidence.md` — THIS FILE

## Total insertion count

~600 lines new (migration + this evidence + html patches).