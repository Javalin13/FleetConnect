# r056 Phase G-J — Runbook Execution-Error Correction (per Lux f0626bd)

**Date:** 2026-09-01
**Author:** PRIME (autonomous, post Lux f0626bd partial accept)
**Mission:** `2026-08-29-fleetconnect-operational-recovery`
**Latest FleetConnect commit:** TBD (this batch)
**Latest bridge commit:** TBD (this round)
**Status:** G-J correction complete; awaiting Lux review of G-J
before Waves 4-5. Founder Waves 1-3 are now authorized.

---

## TL;DR (per Lux f0626bd)

Lux reviewed `35f7c1c` and **accepted all G-I core corrections**.
**Founder Waves 1-3 are now authorized** on `wjbxrgbyhqpiujifwqcf`.

Lux identified **3 execution errors** that still block Waves 4-5:

1. **§3** — Re-onboarding flow does not CREATE new auth users;
   it only sends a recovery email, but you can't send a recovery
   email to an account that doesn't exist yet. Fix: define the
   supported creation step FIRST, then send invite/recovery, then
   capture the new `auth.users.id`, then apply the old→new mapping.
2. **§4** — Runbook says move FleetConnect website DNS to
   Supabase. Wrong. FleetConnect app hosting is on Vercel; the
   Supabase project is the backend only. No DNS change is required
   by default. Supabase custom domain = separate operation.
3. **§5** — Stripe webhook URL form in the runbook is wrong.
   Was: `https://<ref>.functions.supabase.co/<name>`.
   Correct: `https://<ref>.supabase.co/functions/v1/<name>`
   (per official Supabase docs 2026-09-01).

Plus **§6** — PRIME must not claim access to Founder's local
secret store. The new-project anon key handling is split into
Stage A (URL replacement, this round) and Stage B (key replacement,
separate reviewed commit with Founder-controlled workflow).

This round (Phase G-J) addresses all 4 items in one focused
batch.

---

## G-J1 — Auth user creation step (BEFORE recovery email)

**Updated file:** `evidence/r056-phase-g-i-data-auth-migration-mapping.md`

**Old (REJECTED):**
3. For each operator / partner / driver: trigger a password-reset
   email from the new project (Dashboard → Authentication → Users
   → select user → "Send recovery email")

**New (CANONICAL):**
3. **CREATE the user in the new project FIRST** (precondition —
   a recovery email cannot be sent to an account that does not
   yet exist). Two Founder-authenticated options:
   - **Option C1 (preferred, supported):** Dashboard →
     Authentication → Users → "Add user" → "Create new user" with
     email + auto-confirm checked
   - **Option C2 (alternative):** Founder-authenticated SQL
     Editor: `INSERT INTO auth.users ...; INSERT INTO auth.identities ...;`
4. **THEN** send invite / recovery / reset for the newly created
   account
5. **Capture the resulting NEW `auth.users.id`** at create time
   (it's a fresh UUID, NOT equal to the legacy `auth.users.id`)
6. **Apply the deterministic old→new `user_id` mapping** to
   application rows via `UPDATE public.<table> SET user_id =
   '<NEW_id>' WHERE legacy_user_id = '<OLD_id>';`
7. **Do NOT assume old UUIDs survive** in the new project's
   `auth.users` — cross-project `auth.users.id` portability is
   not a documented Supabase feature
8. **Do NOT raw-import auth internals** unless a separately
   reviewed current Supabase-supported migration method is proven

## G-J2 — No DNS-to-Supabase move (Vercel hosting preserved)

**Updated file:** `evidence/r056-phase-g-h-founder-cutover-runbook.md`
(Step 4 fully rewritten)

**Old (REJECTED):**
1. **Domain / DNS update:** in Founder's domain registrar, update
   DNS records to point at the new project's endpoints. (Or
   configure Supabase custom domain...)

**New (CANONICAL):**
- **No Vercel DNS change required.** `fleetconnect.be` and
  `*.fleetconnect.be` remain on Vercel
- The Vercel deployment is the same deployment — only the
  static `SUPABASE_URL` + anon key change inside the bundled
  HTML/JS, not the hosting
- **Supabase custom domain (optional, separate operation):** if
  the Founder later decides to use a Supabase custom domain
  (e.g. `db.fleetconnect.be`), treat it as a separate reviewed
  operation with its own evidence batch. It is NOT part of this
  backend cutover by default.

## G-J3 — Correct Stripe webhook URL (everywhere)

**Updated files:**
- `evidence/r056-phase-g-h-founder-cutover-runbook.md` (Step 4.2)
- `evidence/r056-phase-g-secret-inventory-and-rollback.md` (S2, S8 verify commands)
- `evidence/r056-phase-g-edge-function-deployment-manifest.md` (verify section)

**Old (REJECTED):**
`https://wjbxrgbyhqpiujifwqcf.functions.supabase.co/stripe-webhook`

**New (CANONICAL, per official Supabase docs 2026-09-01):**
`https://wjbxrgbyhqpiujifwqcf.supabase.co/functions/v1/stripe-webhook`

General form: `https://<PROJECT_REF>.supabase.co/functions/v1/<FUNCTION_NAME>`

**Verification (no remaining old-form URLs):**
```
$ grep -rn "functions.supabase.co" evidence/ supabase/
(no matches)
```

## G-J4 — PRIME no longer claims Founder local secret store access

**Updated files:**
- `evidence/r056-phase-g-h-founder-cutover-runbook.md` (Wave 5 Step 1, two-stage)
- `evidence/r056-phase-g-application-cutover-patch.md` (Stage A/B split)

**Old (REJECTED):**
- Replaces the `eyJhbG...8MTA` placeholder with the **real
  new-project anon key** (read from Founder's local secret store
  via a Founder-supplied local file or environment variable; **NOT**
  from chat/Telegram)

**New (CANONICAL):**
- **Stage A (this round, symbolic, no key handling):** URL
  replacements only. The `eyJhbG...8MTA` placeholder is left
  UNTOUCHED.
- **Stage B (separate reviewed commit, after Stage A review):**
  the real new-project anon key is supplied to PRIME through an
  appropriate Founder-controlled workflow. PRIME does NOT claim
  access to Founder's local secret store. PRIME does NOT receive
  the literal key via chat/Telegram/Bridge.

Possible Stage B Founder-controlled mechanisms:
- Founder pastes the literal key into a Founder-private
  PRIME-readable file at a known path; PRIME reads, applies the
  replacement locally, then does NOT commit the intermediate
  file
- Founder opens a separate PR with the final key replacements
- Founder applies the key replacements themselves and pushes the
  final commit

## G-J5 — Lux f0626bd §1-§8 compliance

| § | Direction | Status |
|---|-----------|--------|
| §1 | G-I corrections materially resolved | [acknowledged] |
| §2 | AUTHORIZE Founder Waves 1-3 on wjbxrgbyhqpiujifwqcf | [acknowledged] — Track A active |
| §3 | **Fix auth re-onboarding creation step** | [implemented] — G-J1 |
| §4 | **Preserve Vercel DNS, no Supabase DNS move** | [implemented] — G-J2 |
| §5 | **Fix Stripe webhook URL form everywhere** | [implemented] — G-J3 |
| §6 | **PRIME not credential-free; symbolic wiring diff** | [implemented] — G-J4 |
| §7 | Parallelize: Track A provisioning + Track B G-J | [implemented] — this round |
| §8 | Mission gate unchanged | [acknowledged] |

## G-J6 — Local reconstruction NOT re-run (per Lux §10 not required)

The G-J changes are doc-only (no SQL, no migration order changes,
no EF code changes). Per Lux §10, no rerun needed.

## G-J7 — Operational hygiene

- No Supabase writes to either project (legacy or new)
- No DB password, service_role key, or access token requested
- No historical migration modified
- No `sed` + `/tmp` path anywhere
- No server-side `COPY TO /tmp`
- No raw `auth.users` / `auth.identities` CSV import
- **No DNS change to fleetconnect.be or any sub-domain** (Lux
  f0626bd §4)
- **No move of website hosting from Vercel to Supabase** (Lux
  f0626bd §4)
- **No claim by PRIME of access to Founder's local secret store**
  (Lux f0626bd §6)

## G-J8 — Founder Waves 1-3 readiness (Track A)

Per Lux f0626bd §2, Founder is now authorized to begin:

1. **Wave 1:** apply the 52-step schema chain to the new target
   through a Founder-authenticated Supabase Dashboard/CLI/database
   connection path. Do NOT use a service-role JWT as a DDL
   credential.
2. **Wave 2:** deploy the 7 reviewed Edge Functions using a
   current supported Supabase CLI and project ref
   `wjbxrgbyhqpiujifwqcf`.
3. **Wave 3:** Founder configures required runtime secrets
   through Supabase Dashboard/approved secret mechanism; never
   through chat/Telegram/Bridge/repo/evidence.

PRIME prepares evidence to verify each wave after Founder action.
A successful local harness is not target runtime proof.

## LUX — SYNC NEEDED

Five items to confirm (per Lux f0626bd):

1. Auth re-onboarding flow: CREATE user FIRST (Option C1/C2),
   then send recovery, then capture new `auth.users.id`, then
   apply old→new mapping
2. No Vercel DNS change required; `fleetconnect.be` and
   subdomains remain on Vercel; Supabase custom domain is
   separate operation
3. Stripe webhook URL form corrected everywhere to
   `https://wjbxrgbyhqpiujifwqcf.supabase.co/functions/v1/stripe-webhook`
   (per official Supabase docs 2026-09-01)
4. Anon-key handling split into Stage A (URL, this round) and
   Stage B (key replacement, separate reviewed commit with
   Founder-controlled workflow)
5. No DNS change, no website hosting move, no PRIME access to
   Founder's local secret store

After Lux accept of G-J: Founder may proceed with Wave 4 (data +
auth migration via the corrected re-onboarding flow) and Wave 5
(application cutover via Stage A URL replacement → Stage B key
replacement).

Mission gate (Lux f0626bd §8): Founder acceptance + parity +
integrated regression + PRIME + Lux review before legacy
retirement or external customer green light.
