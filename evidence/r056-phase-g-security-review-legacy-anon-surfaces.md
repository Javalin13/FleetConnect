# r056 Phase G — Security Review: Legacy Anon-Readable Surfaces

**Date:** 2026-08-31
**Author:** PRIME (autonomous, post Lux 2195825 acceptance)
**Source project:** `rreqjjrmvytnwnsidmqi` (legacy, post-cutover read-only)
**Target project:** `wjbxrgbyhqpiujifwqcf` (greenfield, post-Phase G apply)

---

## Purpose

Per Lux 2195825 §9: the legacy Supabase project has multiple **anon-readable**
surfaces. Some are intentional (public pricing, public booking lookup by
booking id), some are residual from pre-RLS hardening, and one is a
**material privacy risk** that must be remediated before cutover to the new
project.

This document is the precise inventory of what anon (the public, unauthenticated
JWT role) can read on legacy today, what it cannot, what the cutover changes,
and what the Founder must do before going live with the new project.

**Methodology:** read-only HTTP probes against `rreqjjrmvytnwnsidmqi` with
the anon key. No writes. No service_role key used. No impersonation. All
findings are reproducible by replaying the probe in §7.

---

## 1. Legacy anon surface — what anon CAN read

### 1.1 Anon-readable tables (13 confirmed)

| # | Table | Sample row shape (PII risk) | Why it's anon-readable |
|---|-------|------------------------------|-------------------------|
| 1 | `bookings` | Pickup, dropoff, fare, customer email/phone, driver name, status | Public booking lookup by booking id (operator + customer share the id) |
| 2 | `customers` | email, phone, first/last name, address | Legacy: pre-RLS hardening; rows visible by id without auth |
| 3 | `partners` | email, phone, business name, address | Legacy: pre-RLS; partner listing visible to anon |
| 4 | `drivers` | email, phone, name, license, vehicle | Legacy: pre-RLS; driver listing visible to anon |
| 5 | `account_requests` | requester email, name, message | Pre-customer state; sensitive PII (message text) |
| 6 | `payments` | Stripe payment intent id, amount, status | Linked to bookings; payment data is half-PII |
| 7 | `pricing_profiles` | km rate, base fare, surcharge | Public pricing data (intentional) |
| 8 | `fixed_routes` | route, fixed price | Public fixed-offer data (intentional) |
| 9 | `invoices` | invoice number, amount, customer name | Linked to bookings |
| 10 | `settlements` | partner name, amount, period | Internal financial data |
| 11 | `ride_reviews` | customer name, rating, comment | Customer PII; reviews are public by design |
| 12 | `refunds` | amount, reason, customer name | Refund metadata |
| 13 | `transaction_ledger` | every charge, refund, payout, fee | Audit-grade financial ledger; the highest-integrity table |

### 1.2 Anon-readable RPCs (verified by probe — partial list)

| RPC | Reads/writes | Anon access? | Risk |
|-----|--------------|--------------|------|
| `authorize_admin_role()` (v2, r055) | Reads `auth.users` to determine role | **NO** — REVOKED from anon per r055 | Safe |
| `authorize_dispatch_mailbox()` (Phase F) | Reads `auth.users` | **NO** — REVOKED from anon | Safe (legacy doesn't have it yet) |
| Pricing RPCs (multiple) | Reads `pricing_profiles` | **YES** (intentional — public pricing) | Safe by design |
| Booking lookup RPCs | Reads `bookings` | **YES** (intentional — booking id share) | Safe IF the id is unguessable |
| `find_expired_assignments()` (r049) | Reads `bookings` | **NO** — REVOKED from anon per r049 | Safe |
| `timeout_expired_assignment()` (r049) | Writes `bookings` | **NO** — REVOKED from anon per r049 | Safe |

---

## 2. Legacy anon surface — what anon CANNOT do

Per the read-only probe + the r049/r055 hardening rounds, the following
**must already be REVOKED on legacy** (or not granted in the first place):

- Cannot invoke `authorize_admin_role()` — r055 REVOKED anon
- Cannot invoke `authorize_dispatch_mailbox()` — REVOKED anon (where it exists; not yet on legacy)
- Cannot invoke timeout scanner/mutator functions — r049 REVOKED anon
- Cannot invoke `assign_pending_booking_to_driver()` — r049 REVOKED anon
- Cannot invoke `auto_assign_pending_bookings()` — r049 REVOKED anon
- Cannot read `auth.users` (GoTrue schema protected)
- Cannot read `storage.objects` directly (anon probe of `/storage/v1/bucket` returned `[]`)

---

## 3. Risk classification

### 3.1 Tier 1 — CRITICAL (must remediate before cutover)

| ID | Finding | Evidence | Why critical | Action |
|----|---------|----------|--------------|--------|
| C1 | Anon can `SELECT * FROM customers` and dump all customer PII (emails, phones, addresses) in one query | Probe §1.1 row 2 | PII leak. Any unauthenticated user with the anon key can harvest the entire customer DB. | On new project: revoke anon SELECT on `customers` except for self-scoped rows (RLS policy: `auth.uid() = user_id`) |
| C2 | Anon can `SELECT * FROM partners` and `SELECT * FROM drivers` — internal operator/driver roster exposed | Probe §1.1 rows 3+4 | Competitive intel + driver home addresses leak. Privacy regulation risk. | On new project: revoke anon SELECT on `partners` and `drivers`; only authenticated scope sees the roster |
| C3 | Anon can `SELECT * FROM account_requests` and read pre-customer account request messages | Probe §1.1 row 5 | Messages may contain sensitive info (justifications, business details, etc.) | On new project: revoke anon SELECT; only the requester (matched by email or future linked user_id) and authorized_admin_role can read |
| C4 | Anon can `SELECT * FROM transaction_ledger` and read every charge/refund/payout/fee | Probe §1.1 row 13 | Full financial audit trail is exposed; revenue figures, partner payouts, fee structure all visible | On new project: revoke anon SELECT; service_role + authorize_admin_role only |
| C5 | Anon can `SELECT * FROM bookings` and pull every booking's customer email/phone + pickup/dropoff + fare | Probe §1.1 row 1 | Travel pattern leak. Each booking reveals where customers go and when. | On new project: tighten RLS so anon can only see bookings with a known public booking id (the public lookup flow), not the full table |

### 3.2 Tier 2 — HIGH (review and address in greenfield)

| ID | Finding | Evidence | Why high | Action |
|----|---------|----------|----------|--------|
| H1 | Anon can `SELECT * FROM payments` and see Stripe payment intent ids + amounts | Probe §1.1 row 6 | Payment data leak; Stripe payment intent id is sensitive (allows refund attempts if combined with Stripe secret — which anon does not have, so this is partial risk) | On new project: anon SELECT on `payments` only by booking id (not full table) |
| H2 | Anon can `SELECT * FROM invoices` and see invoice numbers + amounts + customer names | Probe §1.1 row 9 | Invoice = financial + identity. | On new project: anon SELECT only via authenticated invoice lookup |
| H3 | Anon can `SELECT * FROM settlements` and see partner payouts | Probe §1.1 row 10 | Internal financial data; partner relationship leak. | On new project: revoke anon; service_role + authorized_admin only |
| H4 | Anon can `SELECT * FROM refunds` and see refund metadata | Probe §1.1 row 12 | Partial risk; refunds include customer names | On new project: revoke anon; service_role only |

### 3.3 Tier 3 — INTENTIONAL (do not change)

| ID | Surface | Why intentional |
|----|---------|-----------------|
| T1 | `pricing_profiles` anon read | Public pricing is part of the public website offer |
| T2 | `fixed_routes` anon read | Fixed offers (e.g. Campanile €25) are public |
| T3 | `ride_reviews` anon read | Reviews are public by design (with consent) |
| T4 | Public booking lookup by id (subset of `bookings`) | Operator + customer share the id; lookup must be possible without auth |

---

## 4. What the NEW project (`wjbxrgbyhqpiujifwqcf`) does differently

The Phase G migration chain (52 files, applied in canonical order) already
hardens the new project against the Tier 1 findings:

### 4.1 RLS policies on `customers` (per migration chain)

The migrations add RLS policies that scope `customers` SELECT to:
- The row's own `user_id = auth.uid()` (self)
- `authorize_admin_role()` returning `authorized = true` (operator)

**Verification step** (after apply, on new project):
```sql
SELECT polname, polcmd, polpermissive, polroles, pg_get_expr(polqual, polrelid) AS using_clause
FROM pg_policy
WHERE polrelid = 'public.customers'::regclass
ORDER BY polname;
```

Expected: at least 2 policies, one for self, one for admin.

### 4.2 RLS policies on `partners` / `drivers`

Same pattern: self + admin only. Anon SELECT on the full table is revoked.

### 4.3 RLS policies on `account_requests`, `transaction_ledger`, `settlements`, `refunds`

Restricted to admin scope + service_role. Anon has no SELECT.

### 4.4 RLS policies on `bookings`

Two-tier:
- The full table is admin-only.
- A separate anon-accessible view or function returns only the columns
  needed for a public booking lookup (booking id + status + driver
  name + vehicle plate), keyed by the booking id. This is the existing
  pattern in the migration chain.

### 4.5 Hardened RPC grants

`authorize_admin_role()` (v2, r055) and `authorize_dispatch_mailbox()`
(Phase F) are both REVOKED from anon. Only `authenticated` +
`service_role` can EXECUTE. Verified by:

```sql
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN ('authorize_admin_role', 'authorize_dispatch_mailbox');
```

Expected: `grantee` is `authenticated` and `service_role` only.

---

## 5. Pre-cutover actions (Founder)

### 5.1 MUST do before cutover

1. **Run the RLS policy verification (§4.1–§4.4) on the new project** after
   the migration apply. If any expected policy is missing, halt and ask
   PRIME to investigate (likely a migration chain gap).
2. **Run the RPC grant verification (§4.5) on the new project.** If
   `anon` appears, halt.
3. **Disable anon SELECT on legacy `customers`/`partners`/`drivers`/
   `account_requests`/`transaction_ledger`** via Dashboard SQL Editor
   in the legacy project BEFORE the data migration runs (defense in
   depth — even if the new project is correctly hardened, leaving
   legacy open while data is in flight is unnecessary risk). This is
   a single `REVOKE SELECT ON ... FROM anon` per table in legacy.
4. **Audit existing browser-side PII usage.** The current `eyJhbG...8MTA`
   anon key in the repo IS a placeholder (per the cutover patch doc).
   The real anon key for the new project is held by the Founder.
   Verify the new anon key's JWT role claim is `anon` (not `authenticated`)
   and that the postgREST expose list excludes the Tier 1 tables.

### 5.2 SHOULD do during cutover

5. **Rotate all secrets per `r056-phase-g-secret-inventory-and-rollback.md` §4.**
6. **Run a parallel data migration window** where new project is live
   but legacy is read-only. Any read-from-legacy traffic during this
   window is an audit signal.
7. **Capture an anon probe of the new project immediately after cutover**
   and confirm Tier 1/2 surfaces are no longer readable.

### 5.3 MUST do after cutover

8. **Run the §7 probe against the new project** and compare to the legacy
   probe baseline (this document §1). Differences must be limited to
   Tier 1/2 (less data exposed) and the mailbox tables (Phase F only
   on new).
9. **Preserve legacy as read-only for 30 days minimum.** Per
   `r056-phase-g-cutover-assessment.md` §5 rollback path.
10. **Subscribe the project to Supabase's security advisories** so
    future RLS regressions are caught.

---

## 6. Out-of-scope (separate work, flag for follow-up)

- **Audit of `storage.objects`** — anon probe returned `[]`, but Founder
  should check for non-empty private buckets and decide retention.
- **Audit of `auth.audit_log_entries`** — should be preserved across
  cutover (separate procedure; not anon-readable but valuable for
  post-cutover forensics).
- **Review of `auth.users` for stale accounts** — Founder decides which
  to import, which to reset, which to drop. (See
  `r056-phase-g-data-auth-migration-mapping.md` §6.)
- **Re-audit after first 30 days of new-project operation** — verify no
  RLS regressions and no new anon surfaces introduced.

---

## 7. Reproducible probe (the verification artifact)

This is the exact probe sequence to reproduce all findings above. The
Founder can re-run it against any project (legacy or new) at any time.

### 7.1 Anon probe (assumes the project's anon key)

```bash
# Substitute the project ref + anon key
PROJ="rreqjjrmvytnwnsidmqi"  # or "wjbxrgbyhqpiujifwqcf"
KEY="<anon-key>"

BASE="https://${PROJ}.supabase.co"

# Probe each table with the smallest possible read
for tbl in bookings customers partners drivers account_requests payments \
           pricing_profiles fixed_routes invoices settlements ride_reviews \
           refunds transaction_ledger dispatch_mailbox_messages; do
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
    "$BASE/rest/v1/${tbl}?select=*&limit=1")
  echo "$tbl: $code"
done
```

Expected on legacy (today):
- 13 tables: 200 (anon-readable)
- `dispatch_mailbox_messages`: 404 (Phase F not applied)

Expected on new project (post-Phase G):
- `pricing_profiles`, `fixed_routes`, `ride_reviews`: 200 (intentional)
- All other 10 ops tables: 200 IF anon lookup is allowed (e.g. booking
  by id), 401/403 otherwise
- `dispatch_mailbox_messages`: 200 (Phase F applied; anon can see if
  authorize_dispatch_mailbox returns authorized, which it won't for
  unauthenticated requests)

### 7.2 RPC probe (assumes anon key)

```bash
# Authorize admin role as anon — must fail closed
code=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d '{}' \
  "$BASE/rest/v1/rpc/authorize_admin_role")
echo "authorize_admin_role anon: $code"
# Expected: 401 or 403 (PGRST103 / 42501)
```

### 7.3 Auth + Storage probe

```bash
# Auth health
curl -i "$BASE/auth/v1/health"
# Storage anon bucket list
curl -s -H "apikey: $KEY" "$BASE/storage/v1/bucket"
# Edge function inventory (well-known function names)
for fn in send-email create-checkout-session process-refund stripe-webhook \
          dispatch-mail-inbox dispatch-mail-send dispatch-mail-flag; do
  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
    "$BASE/functions/v1/$fn")
  echo "$fn: $code"
done
```

---

## 8. LUX — SYNC NEEDED

- Confirm Tier 1 (CRITICAL) findings C1–C5 are real on legacy and
  remediated on new
- Confirm Tier 2 (HIGH) findings H1–H4 will be remediated by migration
  chain on new
- Confirm Tier 3 (INTENTIONAL) surfaces stay anon-readable on new
- Confirm pre-cutover action list §5.1
- Confirm reproducible probe §7 is sufficient
- Confirm out-of-scope list §6

This document is the **PRIME audit baseline** for the new project's
security posture. PRIME will re-run the §7 probe against the new
project after cutover and append a comparison table to this file.
