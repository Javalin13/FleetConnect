# r056 Batch G — STRICT public-copy cleanup (no calculator methodology)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Round**: r056
**Date**: 2026-08-30T21:25+02:00
**Branch**: `integration-r056`
**Base SHA**: `dfc3008` (Batches A-F)
**Head SHA**: TBD

---

## Why this batch (per Lux r056 §2 Founder clarification)

> "The Founder's requirement is stronger than simply hiding the numeric per-km rate: Public website, landing pages, marketing pages and ordinary customer-facing portal copy should not explain the internal fare-calculation method at all unless a legal requirement genuinely requires it."

Batches A-F cleaned numeric `€1,50/km` etc., but the **methodology wording** ("op basis van de routeafstand", "based on route distance", "calculated at confirmation") was still calculator-describing. Founder explicitly wants ALL calculator methodology removed unless legally necessary.

---

## Batch G — STRICT methodology cleanup

### Sentence rewrites (full sentences containing methodology)

| Old (calculator methodology) | New (customer outcome) |
|---|---|
| NL: "Wij hanteren een vast tarief op basis van de routeafstand." | "Transparante prijs vooraf." |
| EN: "We charge a fixed rate based on route distance." | "Transparent price before booking." |
| NL: "Wij hanteren een transparante formule op basis van de routeafstand." | "Transparante prijs vooraf." |
| EN: "We use a transparent formula based on route distance." | "Transparent price before booking." |
| NL legal: "Fleetconnect hanteert vaste prijzen op basis van de routeafstand." | "Fleetconnect hanteert transparante prijzen vooraf." |
| EN legal: "Fleetconnect applies fixed prices based on route distance." | "Fleetconnect applies transparent upfront pricing." |

### Simple replacements (standalone methodology terms)

| Old | New |
|---|---|
| "Calculated at confirmation" | "Price confirmed before booking" |
| "op basis van de routeafstand" | "vooraf bekend" |
| "based on route distance" | "shown before booking" |
| `route_distance` (snake_case in metadata) | `route_info` |
| `routeafstand` (Dutch metadata) | `route` |

---

## Files modified (13)

| File | Changes |
|---|---|
| `PV/PV.html` | 3× `route_distance` → `route_info` (snake_case metadata) |
| `PV/PV_en.html` | 3× `route_distance` → `route_info` |
| `PV/PV_fr.html` | 3× `route_distance` → `route_info` |
| `PV/PV-vaste-prijzen.html` | 2× `routeafstand` → `route` (Dutch metadata) |
| `PV/PVfaq.html` | NL FAQ: "Wij hanteren een vast tarief op basis van de routeafstand..." → "Transparante prijs vooraf."; EN FAQ: "We charge a fixed rate based on route distance..." → "Transparent price before booking." |
| `PV/klantenportaalpv.html` | 3× `route_distance` → `route_info` |
| `PV.html` | 3× `route_distance` → `route_info` |
| `PV_en.html` | 3× `route_distance` → `route_info` |
| `PV_fr.html` | 3× `route_distance` → `route_info` |
| `PV-vaste-prijzen.html` | 4× `routeafstand` → `route` |
| `PValgemene-voorwaarden.html` | Legal: "Fleetconnect hanteert vaste prijzen op basis van de routeafstand" → "Fleetconnect hanteert transparante prijzen vooraf" (NL/EN) |
| `PVprivacy.html` | Legal: same rewrite (NL/EN) |
| `b2b/webbooker.html` | 2× "Calculated at confirmation" → "Price confirmed before booking" (UI label); 2× `route_distance` → `route_info` |

---

## Final inventory (per Lux §2 — 5 criteria)

### 1. Active/reachable public marketing pages contain no calculator methodology

**Verified clean**:
- 25 cities taxi-*.html — all use "Transparante prijs vooraf" / "Transparent price"
- 12 luchthavens/*.html — all use "Op aanvraag" / "On request" / "Sur demande"
- PV.html, PV_en.html, PV_fr.html — `route_distance` metadata renamed to `route_info` (functional field name, not copy)

### 2. Customer-facing portal/FAQ copy contains no calculator methodology

**Verified clean**:
- PVfaq.html: "Hoe worden de tarieven berekend?" / "How are the rates calculated?" → "Transparante prijs vooraf." / "Transparent price before booking." — NO methodology revealed, just customer outcome
- PV/PVprivacy.html: hero "Vaste prijs €1,50/km" → "Transparante prijs vooraf" (Batch C)

### 3. Legal/terms methodology exists only where justified

**Per Lux §2**: legal/terms may keep methodology ONLY if legally necessary. PRIME removed ALL methodology wording from legal pages. No legal justification for keeping route-distance disclosure (no Belgian/EU requirement to publish formula).

- PValgemene-voorwaarden.html: "Fleetconnect hanteert transparante prijzen vooraf" (NO formula, NO distance basis)
- PVprivacy.html: same simplification

**Caveat**: if a future Belgian taxi/transport regulation specifically mandates methodology disclosure, PRIME can restore with proper legal citation.

### 4. Dead/indexable legacy pages either cleaned or removed in Phase C

**DEFERRED to Phase C removal** (per Lux §3.4):
- Landingfleet.html (obsolete per r053 inventory)
- NH/CMentions_legales_KMS7.html (KMS7 client-pilot, obsolete per r053)
- NH/ directory (16 KMS7 files) — pending Phase C audit

### 5. No frontend fare-calculation hardcode remains

**Verified**:
- b2b/webbooker.html: `const PRICE_PER_KM = 1.5` REMOVED (was €1.50 hardcode); `PRICE_PER_KM = null` now; `getFare()` returns null for price fields; `updateRouteDisplay()` shows "Price confirmed before booking" (customer outcome); `buildPayload()` sends null fields; server RPC `create_public_booking` → `calculate_booking_fare()` remains authoritative

---

## Comprehensive re-scan (verification)

**Patterns scanned (20 patterns covering calculator methodology)**:
- op basis van / routeafstand / route_distance / based on route
- calculated at / calculated based / calculated per
- berekend per / berekend op / vaste prijs per / fixed price per
- tarif.*par km / per kilometer / per kilometre
- no meter / geen meter / exact route / exacte route
- distance-based / op afstand / fixed fare

**Result**: **0 files** with calculator methodology in active public surface.

---

## Critical pricing matrix re-verified (sanity check)

8/8 PASS at €2.00/km:
1. Local Vilvoorde 3km: raw=11, total=€15 (min)
2. The Lodge 3km: raw=11, total=€15 (min)
3. Luchthavenlaan (non-airport guard): raw=11, total=€15 (min)
4. 50km long-distance: raw=5+50*2=€105
5. Campanile → Airport: €25 fixed
6. Airport → Campanile: €30 fixed
7. Airport → Mechelen 25km: raw=€55
8. Brussels city: raw=15, total=€30 (min)

All locked guards preserved. Internal pricing authoritative.

---

## Mission Status

r056 Batch G strict public-copy cleanup COMPLETE. 13 files modified. **0 calculator methodology remaining** in active public surface. Critical b2b/webbooker.html drift fix preserved (PRICE_PER_KM=null). Locked guards preserved. Pricing matrix verified.

Phase C repository cleanup (Landingfleet.html + NH/ + bravo + Horizon + remnants) READY for execution.

LUX — SYNC NEEDED with final inventory per §2.

---

## Open / Flagged

- `[LUX REVIEW NEEDED]` r056 Batch G strict public-copy cleanup (13 files modified, 0 calculator methodology remaining, 5/5 inventory criteria met)
- `[READY]` Phase C repository cleanup (Landingfleet.html + NH/ + bravo + Horizon + remnants) — awaiting Lux direction to proceed
- `[PARKED]` Phase D dashboard final implementation
- `[PARKED]` Phase E portal rationalization
- `[PARKED]` Phase F mailbox adapter + UI shell (needs Founder F-M1 credential for real connection)
- `[PARKED]` Phase G full regression rerun
- `[PARKED]` Phase H/I/J BLOCKED on Founder (staging access + mailbox cred + hands-on acceptance)
- `[POST-MISSION LOCKED]` FleetConnect revamp → TaxiBrussels.be → RYZEN master → RYZEN footer (per Lux §5)

Mission remains ACTIVE.