# r056 Phase G — Staged Application Cutover Patch

**Date:** 2026-08-31
**Author:** PRIME (autonomous, post Lux 2195825 acceptance)
**Target project:** `wjbxrgbyhqpiujifwqcf` (greenfield)
**Legacy project:** `rreqjjrmvytnwnsidmqi` (read-only after cutover)

---

## Purpose

Per Lux 2195825 §7: the application code (HTML + JS) currently points at
the legacy project. Cutover is the moment we change the URL + anon key in
**11** HTML files. This document is the staged patch — a single
mechanical, reviewable diff that is NOT YET committed. The Founder
applies it at cutover time.

**Why staged (not pre-committed):**
- Pre-committing the URL swap would break the legacy `rreqjjrmvytnwnsidmqi`
  project for any browser that loads a stale page from Vercel/CDN cache.
- The patch is held in this evidence doc, the actual `index.ts` source
  files stay on the legacy URL, and the Founder (or PRIME in a separate
  cutover commit) applies the patch in one atomic commit on cutover day.

---

## 1. Files in scope (11 HTML files with hardcoded legacy URL)

Verified by `grep -n "rreqjjrmvytnwnsidmqi" Paneel/*.html b2b/*.html`:

| # | File | Legacy URL on line | Anon key on line |
|---|------|-------------------|------------------|
| 1 | `Paneel/onderaannemerA.html` | 412 | 413 |
| 2 | `Paneel/admin-index.html` | 296 | (none) |
| 3 | `Paneel/autodealerpaneel.html` | 813 | (none) |
| 4 | `Paneel/driver-login.html` | 111 | (none — relies on createClient default) |
| 5 | `Paneel/partner-login.html` | 224 | (none) |
| 6 | `Paneel/partner-reset-password.html` | 135 | (none) |
| 7 | `Paneel/partner-set-password.html` | 129 | (none) |
| 8 | `Paneel/test-reset.html` | 40 | (none) |
| 9 | `b2b/login.html` | 34 | (anon key inline) |
| 10 | `b2b/portal.html` | 21 | (anon key inline) |
| 11 | `b2b/webbooker.html` | 90 | 91 |

**Repo current state of anon keys (verified by `grep "eyJ"`):**
- `b2b/login.html` — `'eyJhbG...8MTA'` (truncated, NOT a real key — likely placeholder from earlier cleanup)
- `b2b/portal.html` — `'eyJhbG...8MTA'` (truncated, same)
- `b2b/webbooker.html` — `'eyJhbG...8MTA'` (truncated, same)
- `Paneel/onderaannemerA.html` — `'eyJhbG...8MTA'` (truncated, same)

**The real anon key for `wjbxrgbyhqpiujifwqcf` is not yet in the repo.**
The cutover patch handles it in two stages per Lux f0626bd §6:

- **Stage A (URL replacement, this round):** symbolic,
  `eyJhbG...8MTA` placeholder is left UNTOUCHED. PRIME does NOT
  receive the literal anon key from any source.
- **Stage B (anon-key replacement, separate reviewed commit):**
  the real new-project anon key is supplied to PRIME through an
  appropriate Founder-controlled workflow. PRIME does NOT claim
  access to Founder's local secret store; PRIME does NOT receive
  the literal key via chat/Telegram/Bridge.

Possible Stage B Founder-controlled mechanisms:
- Founder pastes the literal key into a Founder-private
  PRIME-readable file at a known path; PRIME reads, applies the
  replacement locally, then does NOT commit the intermediate file
- Founder opens a separate PR with the final key replacements
- Founder applies the key replacements themselves and pushes the
  final commit

**Note on `eyJhbG...8MTA`:** this is a redacted placeholder that
appears in the repo today. It is NOT a valid JWT. Per Lux 2195825 §5.5
+ Lux f0626bd §6, the redaction pattern should be replaced with the
real anon key via Stage B at cutover time.

---

## 2. The cutover patch (one commit, one review)

### 2.1 URL replacement (all 11 files)

For each file in §1, the line:
```
const SUPABASE_URL = 'https://rreqjjrmvytnwnsidmqi.supabase.co';
```
(or equivalent variant: `const SB_URL = ...`, `const supabase = createClient('https://...', ...)`)
becomes:
```
const SUPABASE_URL = 'https://wjbxrgbyhqpiujifwqcf.supabase.co';
```

**Files with the literal `rreqjjrmvytnwnsidmqi` URL that need replacement:**
1. `Paneel/onderaannemerA.html` line 412
2. `Paneel/admin-index.html` line 296
3. `Paneel/autodealerpaneel.html` line 813
4. `Paneel/driver-login.html` line 111
5. `Paneel/partner-login.html` line 224
6. `Paneel/partner-reset-password.html` line 135
7. `Paneel/partner-set-password.html` line 129
8. `Paneel/test-reset.html` line 40
9. `b2b/login.html` line 34
10. `b2b/portal.html` line 21
11. `b2b/webbooker.html` line 90

**Mechanical `sed` command** (run by Founder in worktree at cutover):
```bash
cd /home/prime/fleetconnect-integration-r056
sed -i "s|rreqjjrmvytnwnsidmqi.supabase.co|wjbxrgbyhqpiujifwqcf.supabase.co|g" \
  Paneel/onderaannemerA.html \
  Paneel/admin-index.html \
  Paneel/autodealerpaneel.html \
  Paneel/driver-login.html \
  Paneel/partner-login.html \
  Paneel/partner-reset-password.html \
  Paneel/partner-set-password.html \
  Paneel/test-reset.html \
  b2b/login.html \
  b2b/portal.html \
  b2b/webbooker.html

# Verify zero remaining legacy refs
git diff --name-only -G "rreqjjrmvytnwnsidmqi" Paneel/ b2b/
# Should print: (nothing)
```

### 2.2 Anon key replacement (4 files)

For each of:
- `Paneel/onderaannemerA.html` line 413
- `b2b/login.html` line 34 (inline)
- `b2b/portal.html` line 21 (inline)
- `b2b/webbooker.html` line 91

Replace `'eyJhbG...8MTA'` with the real anon key for `wjbxrgbyhqpiujifwqcf`. The literal value comes from Supabase Dashboard → Project Settings → API → `anon` `public` key.

**Mechanical replacement** (Founder at cutover):
```bash
cd /home/prime/fleetconnect-integration-r056
# Read the real anon key from a file the Founder places at /tmp/wjbx_anon_key
KEY=$(cat /tmp/wjbx_anon_key)
sed -i "s|eyJhbG\\.\\.\\.8MTA|$KEY|g" \
  Paneel/onderaannemerA.html \
  b2b/login.html \
  b2b/portal.html \
  b2b/webbooker.html
```

**Or, recommended:** keep the placeholder and inject via a build-time
Vite/envsubst step. The build does not currently exist (HTML files are
served raw from Vercel), so the inline replacement is the simplest path.

### 2.3 Other references to check

**Stripe public key (publishable, not secret):**
- `grep -rn "pk_live\|pk_test" Paneel/ b2b/` — if present, may need update if the Stripe account changes.
- Per current repo state: not flagged. Stripe publishable keys are safe
  in client code.

**Resend public key:**
- Resend is called via the `send-email` edge function, not from the browser. No client-side Resend key.

**Other Supabase references:**
- `grep -rn "supabase.co" Paneel/ b2b/` — verify zero remaining `rreqjjrmvytnwnsidmqi` after sed.
- `grep -rn "supabase.functions.invoke" Paneel/ b2b/` — verify all EF calls point at the right project (the EF URL is derived from `SUPABASE_URL` so this is automatic).

---

## 3. Pre-cutover verification (Founder runs)

```bash
cd /home/prime/fleetconnect-integration-r056
# 1. Verify zero legacy refs after sed
git diff --name-only -G "rreqjjrmvytnwnsidmqi" Paneel/ b2b/
# Expected: (empty)

# 2. Verify zero placeholder anon keys
git diff --name-only -G "eyJhbG\\.\\.\\.8MTA" Paneel/ b2b/
# Expected: (empty)

# 3. Verify new URL is in every file
for f in Paneel/onderaannemerA.html Paneel/admin-index.html Paneel/autodealerpaneel.html \
         Paneel/driver-login.html Paneel/partner-login.html Paneel/partner-reset-password.html \
         Paneel/partner-set-password.html Paneel/test-reset.html \
         b2b/login.html b2b/portal.html b2b/webbooker.html; do
  count=$(grep -c "wjbxrgbyhqpiujifwqcf.supabase.co" "$f")
  if [ "$count" -lt 1 ]; then
    echo "MISSING new URL in $f"
    exit 1
  fi
done
echo "All 11 files have the new URL."
```

---

## 4. Commit shape

Single commit on `integration-r056`:
```
r056 Phase G cutover: 11 HTML files repointed to wjbxrgbyhqpiujifwqcf

  Paneel/onderaannemerA.html: URL + anon key
  Paneel/admin-index.html: URL
  Paneel/autodealerpaneel.html: URL
  Paneel/driver-login.html: URL
  Paneel/partner-login.html: URL
  Paneel/partner-reset-password.html: URL
  Paneel/partner-set-password.html: URL
  Paneel/test-reset.html: URL
  b2b/login.html: URL + anon key
  b2b/portal.html: URL + anon key
  b2b/webbooker.html: URL + anon key

  Per evidence/r056-phase-g-application-cutover-patch.md
  See also: r056-phase-g-edge-function-deployment-manifest.md
  See also: r056-phase-g-secret-inventory-and-rollback.md
```

**Co-authored-by:** `claude` (PRIME write) + `founder` (URL/key decision).

---

## 5. Rollback (revert in one command)

```bash
cd /home/prime/fleetconnect-integration-r056
git revert <cutover-commit-sha> --no-edit
git push origin integration-r056
# Vercel auto-redeploys the branch; old URL is back in served HTML
```

**Co-conditions for revert:**
- Stripe webhook URL also needs revert in Stripe Dashboard
- DNS / Vercel rewrites (if any) need revert
- Edge function secrets (S5–S13) — leave them set; the revert only undoes the URL/anon key in HTML, the new functions stay available for re-cutover

---

## 6. What this patch does NOT do

- Does NOT modify any edge function source code. (Functions are deployed
  by a separate command; see `r056-phase-g-edge-function-deployment-manifest.md`.)
- Does NOT modify any migration file. (Schema is applied by
  `supabase/apply_manifest.sh`; see `r056-phase-g-migration-manifest.md`.)
- Does NOT set any Supabase secret. (Secrets are set in Dashboard only;
  see `r056-phase-g-secret-inventory-and-rollback.md`.)
- Does NOT commit the literal anon key value to the repo if the
  Founder prefers build-time injection.

---

## 7. LUX — SYNC NEEDED

- Confirm 11-file scope (8 Paneel + 3 b2b)
- Confirm the placeholder `eyJhbG...8MTA` should be replaced (not kept)
- Confirm commit shape (single commit, single review, single revert)
- Confirm pre-cutover verification script (§3)
- Confirm rollback path (§5)
