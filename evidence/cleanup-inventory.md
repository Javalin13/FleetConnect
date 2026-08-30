# FleetConnect Repository Cleanup Inventory (r053, per Founder directive)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Date**: 2026-08-30T17:00+02:00
**Authority**: Founder directive (out-of-band) + Lux r051 §8

---

## Goal

FleetConnect repository must be **clean, efficient, well-organized**. KMS7/testpilot/old client-specific pages inventoried FIRST, then safely removed AFTER dependency-check. Cleanup is a separate reviewed batch and must not destabilize the operational recovery candidate.

## Approach

PRIME audited every HTML/JS file in the repo for:
1. Files in `NH/` directory (KMS7 sub-brand)
2. Files referencing KMS7 / testpilot / old client sub-brands
3. Files with **no inbound cross-references** (isolated sub-apps)
4. Files that are obsolete landing pages

The findings below cover each candidate with:
- Path
- Inbound cross-references (grep -rln on the rest of the repo)
- Outbound dependencies (imports, references to other files)
- Risk if removed
- Recommendation

---

## A. NH/ directory (16 files, KMS7 sub-brand)

`NH/` contains a complete, isolated, self-contained sub-app for a different client (KMS7). No cross-references from the main FleetConnect app. Found via `grep -rln "KMS7\|LoginKMS7\|ClientKMS7"` excluding the NH/ directory:

- `tests/translation-audit.js` — references "KMS7" as a translation audit keyword
- `bravo.html` — references KMS7 (bravo is also a separate sub-app, see Section B)

| File | Inbound refs | Outbound deps | Risk if removed |
|---|---|---|---|
| `NH/KMS7.html` | 0 (outside NH/) | self-contained | LOW — isolated sub-app |
| `NH/KMS7_en.html` | 0 | self-contained | LOW |
| `NH/KMS7_nl.html` | 0 | self-contained | LOW |
| `NH/KMS7services.html` | 0 | self-contained | LOW |
| `NH/ClientKMS7.html` | 0 | self-contained | LOW |
| `NH/ClientKMS7_en.html` | 0 | self-contained | LOW |
| `NH/ClientKMS7_nl.html` | 0 | self-contained | LOW |
| `NH/LoginKMS7.html` | 0 | self-contained | LOW |
| `NH/VerificatieKMS7.html` | 0 | self-contained | LOW |
| `NH/CMentions_legales_KMS7.html` | 0 | self-contained | LOW |
| `NH/Mentions_legales_KMS7.html` | 0 | self-contained | LOW |
| `NH/picgridKMS7.png`, `NH/picgridKMS72.png`, `NH/pixKMS7.png`, `NH/heroKMS7.png`, `NH/picinsidecar.jpg` | 0 | self-contained | LOW |

**Recommendation**: NH/ directory can be archived in a single batch (move to `_archive/NH_KMS7_client/`). Zero risk to operational FleetConnect candidate.

---

## B. Bravo sub-app (4 files)

Bravo is a separate client sub-app for a different brand. Found files: `bravo.html`, `bravoklantenportaal.html`, `loginbravo.html`. No inbound cross-references from the main FleetConnect app, but the file `bravo.html` references `KMS7` (translation audit).

| File | Inbound refs | Outbound deps | Risk if removed |
|---|---|---|---|
| `bravo.html` | 0 (outside bravo files) | self-contained | LOW — isolated |
| `bravoklantenportaal.html` | 0 | self-contained | LOW |
| `loginbravo.html` | 0 | self-contained | LOW |

**Recommendation**: Bravo files can be archived (move to `_archive/bravo_client/`). Zero risk to operational FleetConnect candidate.

---

## C. Obsolete Landing Pages

| File | Inbound refs | Status | Risk if removed |
|---|---|---|---|
| `fleetconnect.html` | `klantenportaal.html:395/435/445` (logout redirects) | **ACTIVE** — main taxi landing page | DO NOT REMOVE |
| `Landingfleet.html` | self-references only | Old landing variant, superseded by `fleetconnect.html` | MEDIUM — verify search engine + marketing before removing |
| `Horizon.html` | 0 | Horizon C2 sub-brand (luxury events) — separate from FleetConnect | LOW — but verify not in production separately |

**Recommendation**:
- `fleetconnect.html`: KEEP (active)
- `Landingfleet.html`: review separately with Founder before removal
- `Horizon.html`: separate sub-brand; review separately

---

## D. Active Pages (DO NOT REMOVE)

These are the production-active pages and must NOT be touched by cleanup:

| File | Role |
|---|---|
| `PV/PV.html`, `PV/PV_en.html`, `PV/PV_fr.html` | Customer booking pages (NL/EN/FR) |
| `PV/klantenportaalpv.html`, `PV/klantenportaalpv_en.html`, `PV/klantenportaalpv_fr.html` | Customer portal |
| `loginfleetconnect.html` | Customer login |
| `klantenportaal.html` | Old customer portal (kept for legacy redirects) |
| `Paneel/admin-index.html` | Admin/dispatch panel selector (Horizon) |
| `Paneel/autodealerpaneel.html`, `Paneel/onderaannemerA.html`, `Paneel/commander.html` | 3 sub-panels |
| `Paneel/partner-login.html`, `Paneel/partner-set-password.html`, `Paneel/partner-reset-password.html` | Partner login + flows |
| `Paneel/driver-login.html`, `Paneel/driverpaneel.html` | Driver login + portal |
| `driver-accept.html`, `driver-decline.html` | Driver assignment accept/decline |
| `review.html`, `reset-password.html` | Review + password reset |
| `luchthavens/*.html` | Airport landing pages (10 files) |
| `PV/register.html` | Customer registration |
| `PV/index.html` | Customer index |
| `assessment/*.html` | Operational assessment pages |

---

## E. Operational Files (DO NOT REMOVE)

The following non-HTML files are core to the operational recovery candidate:

- `supabase/migrations/` — all migrations (r047-r053 evidence)
- `supabase/functions/` — Edge Functions
- `src/modules/communication/` — mail service (r048-r050 evidence)
- `src/lib/auth/` — customer auth (TypeScript)
- `src/lib/` — other shared libs
- `tests/` — test files
- `b2b/`, `Paneel/`, `PV/`, `Webapp/` — operational sub-apps

---

## F. Other Files Review

| Path | Status | Notes |
|---|---|---|
| `final_audit.log`, `nav_verify.log`, `nav_test_output.log`, `audit_*.log`, `audit_*.txt`, `audit_*.json` | Reports | KEEP for audit trail (historical evidence) |
| `BOOKING_*_REPORT.md`, `BRANDING_*_REPORT.md`, `CHECKPOINT_*_REPORT.md`, `CERTIFICATION*`, `CYCLE-*` | Historical certification reports | KEEP — required for mission history |
| `cities/` | Cities landing pages | REVIEW — verify not in production before cleanup |
| `assessment/` | Operational assessment | KEEP (operational) |
| `certification/` | Certification evidence | KEEP |

---

## Cleanup Action Plan (separate reviewed batch)

| Phase | Action | Pre-condition |
|---|---|---|
| C1 | Move `NH/` → `_archive/NH_KMS7_client/` (preserve all 16 files) | Founder approves |
| C2 | Move `bravo*.html` + `loginbravo.html` → `_archive/bravo_client/` | Founder approves |
| C3 | Verify `Landingfleet.html` has no inbound production references; then move to `_archive/` | Founder approves |
| C4 | Verify `Horizon.html` not in production separately; then move to `_archive/` | Founder approves |

**Cleanup does NOT happen in r053.** It is a separate reviewed batch per Founder directive ("inventory first, then safely removed after dependency-check").

---

## What r053 DOES NOT Touch

- No removal in r053
- No file deletion in r053
- No directory restructuring in r053
- All cleanup is parked until Founder explicitly approves C1-C4

The cleanup inventory is the deliverable for r053. Implementation is a future batch.
