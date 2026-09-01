# r056 Phase G-K — Auth-Contract Correction (Option C2 REMOVED per Lux 39ca1a0 §5)

**Date:** 2026-09-01
**Author:** PRIME (autonomous, post Lux 39ca1a0 partial accept)
**Mission:** `2026-08-29-fleetconnect-operational-recovery`
**Latest FleetConnect commit:** TBD (this batch)
**Latest bridge commit:** TBD (this round)
**Status:** G-K correction complete; awaiting Lux review of G-K
before Wave 4. Founder Waves 1-3 remain authorized.

---

## TL;DR (per Lux 39ca1a0)

Lux reviewed `0de5926` and accepted §1-§4 (Vercel hosting, Stripe
URL, no-secret-claim, create-first order). Lux identified **one
auth-contract blocker** (Option C2) that still blocks Wave 4.

**Option C2 REMOVED entirely** from the canonical re-onboarding
path. Direct `INSERT INTO auth.users ...` / `INSERT INTO
auth.identities ...` via SQL Editor is NOT acceptable as canonical
OR fallback. The authenticated Dashboard session does not make it
a supported auth lifecycle operation.

The canonical re-onboarding flow is now:
- Option C1 only: Dashboard → Authentication → Users → "Add
  user" → "Create new user" with email + auto-confirm checked
- Send invite / recovery / reset to the new user
- Capture the new `auth.users.id` at create time
- Apply deterministic old → new `user_id` mapping

Also: the older `evidence/r056-phase-g-data-auth-migration-mapping.md`
doc is now marked **SUPERSEDED** — its §3 (raw auth import) and
§4.2.1 (`\COPY auth.users` / `\COPY auth.identities`) are
explicitly REJECTED. Use the G-I canonical doc instead.

Wording fix (per Lux §6): "new UUID must differ" softened to
"do not assume legacy ID portability; target-created ID is
authoritative".

---

## G-K1 — Option C2 REMOVED

**Updated file:** `evidence/r056-phase-g-i-data-auth-migration-mapping.md`

**Old (REJECTED):**
```
- Option C2 (alternative): Founder-authenticated SQL Editor:
  INSERT INTO auth.users (instance_id, id, aud, role, email,
  encrypted_password, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at) VALUES (...);
  INSERT INTO auth.identities (...) VALUES (...);
```

**New (CANONICAL, Option C1 only):**
```
- Option C1 (canonical, supported): Dashboard → Authentication
  → Users → "Add user" → "Create new user" with email +
  auto-confirm checked. The new auth.users.id is returned by
  the Dashboard and recorded in the mapping document.
- ~~Option C2 (REMOVED per Lux 39ca1a0 §5): direct INSERT INTO
  auth.users / auth.identities via SQL Editor — directly
  manipulates Supabase-managed Auth internals and reintroduces
  the exact class of unsupported raw-auth mutation Lux
  previously rejected. NOT acceptable as canonical or fallback,
  even with Founder authenticated in Dashboard.~~
- (Future option, not yet adopted) If a supported administrative
  auth API is later verified and reviewed, it MAY be added as
  another canonical option in a future round. Until then,
  Dashboard is the only supported path.
```

## G-K2 — Soften "new UUID must differ" wording

**Updated file:** `evidence/r056-phase-g-i-data-auth-migration-mapping.md`

**Old (PRECISE BUT OVERCLAIMING):**
```
- It is NOT equal to the legacy auth.users.id (per documented
  Supabase behavior, auth.users.id is a fresh UUID per project)
```

**New (PER LUX 39ca1a0 §6):**
```
- Do NOT assume legacy auth.users.id portability. The cross-
  project portability of auth.users.id is not a documented
  Supabase feature; the legacy IDs belong to the legacy
  project's auth schema. The target-created ID is authoritative
  unless a separately supported migration method explicitly
  preserves IDs (no such method is currently adopted).
```

## G-K3 — Mark older doc as SUPERSEDED

**Updated file:** `evidence/r056-phase-g-data-auth-migration-mapping.md`
(prior Phase G mapping doc)

**Changes:**
- Title appended: `(SUPERSEDED — G-I canonical)`
- New top-level "⚠️ SUPERSEDED — DO NOT FOLLOW" section that
  points to the G-I canonical doc, G-J correction, and G-K
  correction
- 4 reasons why the doc is superseded (raw `COPY auth.users`,
  `Option A` hash import, UUID portability assumption, wrong
  import order)
- Section §1 + §2 + §3.1 + §4.2.2-4.2.4 marked "still directionally
  correct for non-auth application data"
- Section §3 + §4.2.1 marked REJECTED

## G-K4 — G-J correction summary updated

**Updated file:** `evidence/r056-phase-g-j-correction-summary.md`
(its Step 3 description now points to G-K correction)

**Changes:**
- Option C2 description marked as `***UPDATE 2026-09-01 (Lux
  39ca1a0 §5): Option C2 REMOVED***`
- Reference to G-K correction summary added

## G-K5 — Repo-wide grep (verification)

Ran grep over `evidence/` and `supabase/` for any remaining
direct `INSERT INTO auth.users` / `INSERT INTO auth.identities`
instructions in canonical docs / runbooks:

| File | Status |
|------|--------|
| `evidence/r056-phase-g-i-data-auth-migration-mapping.md` | Option C2 struck through, Option C1 only is canonical |
| `evidence/r056-phase-g-j-correction-summary.md` | Option C2 marked REMOVED with pointer to G-K |
| `evidence/r056-phase-g-data-auth-migration-mapping.md` | Doc marked SUPERSEDED; §3 + §4.2.1 rejected |
| `evidence/r056-phase-g-h-founder-cutover-runbook.md` | Already REJECTED raw CSV path; references G-I canonical auth doc |
| `supabase/migrations/20260616030000_partner_invite_with_auth_user.sql` | Historical migration (already shipped on legacy); SECURITY DEFINER function. NOT in the canonical re-onboarding path; not modified (per Lux 2195825 §4 — no historical migration edits without founder approval) |
| `supabase/migrations/20260617020000_cert_cycle_8_partner_driver_portals.sql` | Same: historical migration; SECURITY DEFINER function. Not in the canonical re-onboarding path; not modified |
| `supabase/manual/20260619_go_live_cleanup_keep_ryzen.sql` | Manual one-shot script, not part of the production chain. Not in canonical re-onboarding path. |
| `supabase/local_harness/00_local_auth_stubs.sql` | Local harness only (test stubs). Not on real Supabase. Not in canonical re-onboarding path. |

**No remaining canonical-path direct `INSERT INTO auth.users`
or `INSERT INTO auth.identities` instructions.**

## G-K6 — Lux 39ca1a0 §1-§9 compliance

| § | Direction | Status |
|---|-----------|--------|
| §1 | Vercel hosting / DNS correction | [acknowledged] — already done in G-J |
| §2 | Stripe webhook endpoint form | [acknowledged] — already done in G-J |
| §3 | PRIME no longer claims Founder local secret store | [acknowledged] — already done in G-J |
| §4 | Auth flow now recognizes user must exist first | [acknowledged] — already done in G-J |
| §5 | **Remove Option C2 entirely** | [implemented] — G-K1: Option C2 struck through, Option C1 only is canonical |
| §6 | **Soften UUID wording** | [implemented] — G-K2: target-created ID is authoritative; legacy portability not assumed |
| §7 | Waves 1-3 remain authorized | [acknowledged] — Track A active |
| §8 | One focused G-K correction | [implemented] — this round |
| §9 | Mission gate unchanged | [acknowledged] |

## G-K7 — Local reconstruction NOT re-run (per Lux §8.6)

All G-K changes are doc-only. Per Lux §8.6: "docs-only correction;
no need for full local 52-step regression unless executable SQL/
config changes."

## G-K8 — Operational hygiene

- No Supabase writes to either project
- No DB password, service_role key, or access token requested
- **No historical migration modified** (the SECURITY DEFINER
  `insert into auth.users` in
  `20260616030000_partner_invite_with_auth_user.sql` and
  `20260617020000_cert_cycle_8_partner_driver_portals.sql` are
  historical migrations; per Lux 2195825 §4 they are NOT
  modified without founder approval)
- No `sed` + `/tmp` path anywhere
- No server-side `COPY TO /tmp`
- No raw `auth.users` / `auth.identities` CSV import in the
  canonical re-onboarding path
- No DNS change to fleetconnect.be
- No Vercel → Supabase hosting move
- No PRIME claim of Founder local secret store access
- **No direct `INSERT INTO auth.users` / `INSERT INTO
  auth.identities` in the canonical re-onboarding path** (Option
  C2 removed; historical SECURITY DEFINER functions preserved as
  documented)

## LUX — SYNC NEEDED

Five items to confirm (per Lux 39ca1a0):

1. **Option C2 (direct `INSERT INTO auth.users` /
   `auth.identities`) is REMOVED entirely** from the canonical
   re-onboarding path. Dashboard (Option C1) is the ONLY
   supported create-user path.
2. **UUID wording softened:** target-created ID is authoritative;
   legacy ID portability is not assumed; the explicit "must
   differ" claim is removed (it overclaimed).
3. **Older doc marked SUPERSEDED**:
   `evidence/r056-phase-g-data-auth-migration-mapping.md` is
   clearly marked as superseded with pointers to the G-I
   canonical doc, G-J correction, and this G-K correction.
4. **Repo-wide grep clean:** no remaining canonical-path
   `INSERT INTO auth.users` / `auth.identities` instructions.
   Historical SECURITY DEFINER functions in legacy migrations
   are preserved (not in canonical re-onboarding path; per
   Lux 2195825 §4 no historical migration edits).
5. **Local reconstruction NOT re-run** (per Lux §8.6,
   docs-only changes).

After Lux accept of G-K: Founder may proceed with Wave 4 (data +
auth migration via Option C1 Dashboard create-user flow + old→new
mapping) and Wave 5 (application cutover via Stage A → Stage B).

Mission gate (Lux 39ca1a0 §9): Founder acceptance + parity +
integrated regression + PRIME + Lux review before legacy
retirement or external customer green light.
