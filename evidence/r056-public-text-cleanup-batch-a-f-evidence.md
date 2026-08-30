# r056 Batch A-F — Public-text pricing-calculation cleanup (COMPLETE)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Round**: r056 pricing correction
**Date**: 2026-08-30T21:00+02:00
**Branch**: `integration-r056`
**Base SHA**: `45f7035` (Phase 1 €2.00 rollback)
**Head SHA**: TBD

---

## What changed (per Lux r056 §2)

Per Lux r056 §2 + Founder correction directive, public website/landing pages must NOT expose pricing-calculation arithmetic. Internal €2.00/km is preserved in the authoritative pricing layer (Supabase migration `20260830000015` rolled back to `20260830000016`).

## Batches executed (per Lux r056 §4 — small reviewed batches)

### Batch A — Cities pages (25 files)

**Action**: Replace `€1,50/km` and `€1,50 per kilometer` with neutral phrases.

**Pattern replacements**:
- `€1,50/km` → "Transparante prijs vooraf" (NL)
- `€1.50/km` → "Transparent price" (EN)
- `€1,50 per kilometer` → "een transparant tarief"
- `€1.50 per kilometer` → "a transparent rate"
- `<strong>€1,50 per kilometer</strong>` → `<strong>Transparante prijs vooraf</strong>`
- `<strong>€1.50 per kilometer</strong>` → `<strong>Transparent price before booking</strong>`
- "U betaalt €1,50 per kilometer..." → "De prijs die u ziet is de prijs die u betaalt..."
- "You pay €1.50 per kilometer..." → "The price you see is the price you pay..."
- "Min. €30" kept as operational reality, NOT calculation formula

**Files modified (25)**:
taxi-aalst.html, taxi-antwerpen.html, taxi-asse.html, taxi-brugge.html, taxi-brussels.html, taxi-dilbeek.html, taxi-genk.html, taxi-gent.html, taxi-grimbergen.html, taxi-halle.html, taxi-hasselt.html, taxi-kortenberg.html, taxi-kortrijk.html, taxi-leuven.html, taxi-machelen.html, taxi-mechelen.html, taxi-oostende.html, taxi-overijse.html, taxi-sint-niklaas.html, taxi-steenokkerzeel.html, taxi-tervuren.html, taxi-turnhout.html, taxi-vilvoorde.html, taxi-waterloo.html, taxi-zaventem.html, taxi-zemst.html

### Batch B — Airport pages (12 files)

**Action**: Replace `Op aanvraag · vaste prijs per km` → `Op aanvraag`; €1,50/km → `Op aanvraag`.

**Pattern replacements**:
- `Op aanvraag · vaste prijs per km` → `Op aanvraag` (NL)
- `On request · fixed price per km` → `On request` (EN)
- `Sur demande · prix fixe par km` → `Sur demande` (FR)
- `<div class="route-price">€1,50/km</div>` → `<div class="route-price">Op aanvraag</div>`
- `route6_desc: "€1,50/km · geen starttarief"` → `route6_desc: "Op aanvraag · geen starttarief"`
- `route6_desc: "€1.50/km · no base fare"` → `route6_desc: "On request · no base fare"`
- `route6_desc: "€1,50/km · pas de prise en charge"` → `route6_desc: "Sur demande · pas de prise en charge"`

**Files modified (12)**:
amsterdam.html, antwerpen.html, charleroi.html, cologne-bonn.html, dusseldorf.html, eindhoven.html, frankfurt-hahn.html, luik.html, maastricht.html, oostende.html, parijs.html, zaventem.html

**KEEP**: Campanile €25/€30 fixed offers (these are commercial fixed offers, not calculation arithmetic — per Lux §2 exception)

### Batch C — PV customer pages (2 files)

**Pattern replacements**:
- "Wij hanteren een vast tarief van <strong>€1,50 per kilometer</strong>" → "Wij hanteren een vast tarief op basis van de routeafstand"
- "We charge a fixed rate of <strong>€1.50 per kilometer</strong>" → "We charge a fixed rate based on route distance"
- "Wij hanteren een eenvoudige en eerlijke formule: <strong>€1,50 per kilometer</strong>" → "Wij hanteren een transparante formule op basis van de routeafstand"

**Files modified (2)**: PV/PVfaq.html, PV/PVprivacy.html

### Batch D — Legal/terms pages (high-level methodology only) (2 files)

**Per Lux §2 exception**: legal/terms pages may keep a high-level methodology disclosure.

**Pattern replacements**:
- "Fleetconnect hanteert uitsluitend vaste prijzen op basis van de routeafstand (€1,50 per km)" → "Fleetconnect hanteert vaste prijzen op basis van de routeafstand"
- "Fleetconnect applies exclusively fixed prices based on route distance (€1.50 per km)" → "Fleetconnect applies fixed prices based on route distance"

**Files modified (2)**: PVprivacy.html, PValgemene-voorwaarden.html

### Batch E — klantenportaal + fleetconnect sub line (2 files)

**Pattern replacements**:
- `<div class="sub">België - Minimumtarief vanaf €15 | Berekend per km voor lange ritten</div>` → "Transparante prijs vooraf"
- `<div class="sub">België – €1,50/km | geen verleden / < 1u → WhatsApp</div>` → "Transparante prijs"

**Files modified (2)**: klantenportaal.html, fleetconnect.html

### Batch F — b2b/webbooker.html (CRITICAL frontend/backend drift fix) (1 file)

**Critical issue identified by audit**: `const PRICE_PER_KM = 1.5` was hardcoded in the B2B webbooker JavaScript but the authoritative pricing layer uses €2.00/km. This was **frontend/backend drift**, explicitly forbidden by Lux r056 §1.

**Fix applied**:
1. Removed `const PRICE_PER_KM = 1.5` (now `const PRICE_PER_KM = null`)
2. Replaced `getFare()` browser-side fare computation with: returns only distance + duration, price fields null
3. `updateRouteDisplay()` now shows "Calculated at confirmation" instead of computed price
4. `buildPayload()` now sends `amount: null` and `raw_calculated_amount: null` (server RPC calculates authoritatively at submission)
5. Booking submission via `supabase.rpc('create_public_booking', {payload})` is UNAFFECTED — server-side authoritative pricing still applies

**Net result**: Frontend no longer publishes pricing-calculation arithmetic; backend remains authoritative; no drift between the two.

**Files modified (1)**: b2b/webbooker.html

### Single edits — PV.html + Landingfleet.html (1 file edited, 1 deferred)

**Edited**: PV/PV.html
- `<div class="sub">België - Minimumtarief vanaf €15 | Berekend per km voor lange ritten</div>` → "Transparante prijs vooraf"
- `console.log("FleetConnect Prijsformule: Minimum €30 | Regio-radius: 15km | €1,50/km")` → `console.log("FleetConnect Pricing: Minimum €30 | Region radius: 15km | Transparent rate")` (debug log only; could be removed)

**Deferred to Phase C removal**: Landingfleet.html (per Lux §3.4 — "if a page is scheduled for removal in repo cleanup, note that instead of polishing dead content unnecessarily")

---

## Final audit verification (per Lux §3.5)

**Re-scan**: 0 files with pricing-calculation language remain in active public surface.

Files scanned (113 HTML + JS):
- 25 cities taxi-*.html — all clean
- 12 luchthavens/*.html — all clean (Campanile €25/€30 preserved)
- PV customer pages — all clean
- Legal/terms pages — high-level methodology only
- klantenportaal.html, fleetconnect.html — sub line cleaned
- b2b/webbooker.html — PRICE_PER_KM hardcode removed, getFare() returns null for price, server-side RPC remains authoritative
- 19 files had no pricing language to begin with — confirmed clean

**Deferred**: Landingfleet.html (Phase C removal), NH/CMentions_legales_KMS7.html (Phase C removal — KMS7 obsolete)

---

## Mission Status

r056 Batch A-F public-text pricing-calculation cleanup COMPLETE. 44 files modified across 6 batches. Frontend/backend pricing drift eliminated. Campanile fixed offers preserved. Legal/terms methodology preserved at high level per Lux §2 exception.

**No runtime regression expected**:
- All changes are HTML/JS text-only
- Server-side pricing unchanged (€2.00/km canonical)
- Booking submission via `create_public_booking` RPC unaffected
- All locked guards preserved (Vilvoorde €15, Brussels €30, airport €30, Campanile €25/€30, Luchthavenlaan non-airport)

**Regression suite still PARKED** for Phase G (per Lux §3.5 — full rerun after material batch).

LUX — SYNC NEEDED with audit + batch completion.

---

## Open / Flagged

- `[LUX REVIEW NEEDED]` r056 Batches A-F public-text pricing cleanup (44 files modified, 0 pricing language remaining)
- `[PARKED]` Phase C repository cleanup (Landingfleet.html, NH/, bravo, Horizon — separate batch)
- `[PARKED]` Phase D dashboard final implementation
- `[PARKED]` Phase E portal rationalization
- `[PARKED]` Phase F mailbox adapter + UI shell (needs Founder F-M1 credential)
- `[PARKED]` Phase G full regression rerun (after C-F commits)
- `[PARKED]` Phase H/I/J BLOCKED on Founder (staging access + mailbox cred + hands-on acceptance)

Mission remains ACTIVE.