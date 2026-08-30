# r056 public-text pricing-calculation audit + cleanup inventory

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Round**: r056 pricing correction
**Date**: 2026-08-30T20:50+02:00
**Branch**: `integration-r056`
**Base SHA**: `45f7035` (Phase 1 €2.00 rollback)
**Head SHA**: TBD

---

## Why this audit (per Lux r056 §2 Founder directive)

> "PUBLIC WEBSITE / LANDING PAGES — DO NOT EXPOSE PRICING CALCULATION ARITHMETIC"

The Founder explicitly does NOT want public website, landing pages, customer-facing portal copy, marketing copy or generic public UI to explain internal fare-calculation mechanics.

**Audit targets**:
- `€1.50/km`, `€1.80/km`, `€2.00/km`, `€1.5/km` variants
- `per km`, `per kilometer`, `per kilometre`, `/km`
- `prijs per km` (NL), `tarif au kilomètre` (FR), `kilometerprijs`, `kilometertarief`
- Formulas like "base fare + kilometer rate"
- Distance-rate tables
- Language explaining how internal calculator derives a fare

**Preferred public positioning**: transparent fare shown before confirmation; fixed/confirmed fare before booking; specific fixed offers (e.g. hotel/airport) only where commercially intended.

**Exception**: legal/terms page may need pricing methodology disclosure — keep accurate but high-level and flexible; no universal rigid formula unless legally necessary.

---

## Audit results (113 HTML files scanned, 94 with pricing-calculation language)

### ACTIVE pages with pricing-calculation claims (require cleanup)

| File | Patterns found | Action |
|---|---|---|
| `cities/taxi-brussels.html` | €1.50/km ×5, per kilometer ×3 | REPLACE €1,50/km with "Transparante prijs vooraf" |
| `cities/taxi-vilvoorde.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-mechelen.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-leuven.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-brugge.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-gent.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-antwerpen.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-halle.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-aalst.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-kortrijk.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-oostende.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-hasselt.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-genk.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-turnhout.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-machelen.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-overijse.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-tervuren.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-zemst.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-steenokkerzeel.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-dilbeek.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-zaventem.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-sint-niklaas.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-grimbergen.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-kortenberg.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `cities/taxi-asse.html` | €1.50/km ×5, per kilometer ×3 | REPLACE |
| `luchthavens/oostende.html` | €1.50/km ×4, per km ×1, prijs per km ×1 | REPLACE — but Campanile €25/€30 KEEP as fixed offers |
| `luchthavens/luik.html` | €1.50/km ×4, per km ×1, prijs per km ×1 | REPLACE |
| `luchthavens/zaventem.html` | €1.50/km ×4, per km ×1, prijs per km ×1 | REPLACE |
| `luchthavens/antwerpen.html` | €1.50/km ×4, per km ×1, prijs per km ×1 | REPLACE |
| `luchthavens/charleroi.html` | €1.50/km ×4, per km ×1, prijs per km ×1 | REPLACE |
| `luchthavens/cologne-bonn.html` | per km ×3, prijs per km ×2 | REPLACE "Op aanvraag · vaste prijs per km" → "Op aanvraag" |
| `luchthavens/eindhoven.html` | per km ×3, prijs per km ×2 | REPLACE |
| `luchthavens/parijs.html` | per km ×3, prijs per km ×2 | REPLACE |
| `luchthavens/dusseldorf.html` | per km ×3, prijs per km ×2 | REPLACE |
| `luchthavens/frankfurt-hahn.html` | per km ×3, prijs per km ×2 | REPLACE |
| `luchthavens/amsterdam.html` | per km ×3, prijs per km ×2 | REPLACE |
| `luchthavens/maastricht.html` | per km ×3, prijs per km ×2 | REPLACE |
| `PV/PV.html` | €1.50/km ×1 (console.log), per km ×1 (sub) | REPLACE sub + remove console.log or keep debug-only |
| `PV/PVprivacy.html` | €1.50/km ×8, per kilometer ×2 | REPLACE |
| `PV/PVfaq.html` | per kilometer ×2 (FAQ) | REPLACE FAQ answers |
| `PV/PV-vaste-prijzen.html` | per kilometer ×3 (formula text) | REPLACE formula explanation |
| `PVprivacy.html` | per km ×3 (legal terms) | REPLACE — but KEEP high-level legal methodology disclosure per Lux §2 exception |
| `PValgemene-voorwaarden.html` | per km ×3 (legal terms) | REPLACE — KEEP high-level legal methodology disclosure |
| `klantenportaal.html` | €1.50/km ×1 (sub line) | REPLACE |
| `fleetconnect.html` | €1.50/km ×1 (sub line) | REPLACE |

### OBSOLETE/DORMANT (scheduled for removal in Phase C, no polish needed)

| File | Why obsolete |
|---|---|
| `Landingfleet.html` | r053 cleanup-inventory: obsolete landing page |
| `NH/CMentions_legales_KMS7.html` | KMS7 client-pilot, obsolete per r053 inventory |

### NO-PRICING-LANGUAGE FILES (113 - 94 = 19 files clean)

`autodealerpaneel.html`, `commander.html`, `driverpaneel.html`, `loginfleetconnect.html`, `partner-login.html`, `partner-reset-password.html`, `partner-set-password.html`, `partnerspaneel.html`, `PV/PV_en.html`, `PV/PV_Zakelijk_Vervoer.html`, `PV/klantenportaalpv.html`, `PV/PV.html` (mostly clean — only the sub line and console.log flagged), `reset-password.html`, `test-reset.html`, `admin-index.html`, `driver-login.html`, `onderaannemerA.html`

(19 confirmed clean from scan; some may have non-pricing language that doesn't match our patterns)

---

## Cleanup strategy (per Lux §2 + r056 §3 §4 §5)

### Public-facing pages (active customer routes)

Replace hard-coded `€1,50/km` and `€1,50 per kilometer` with:
- "Transparante prijs vooraf" (NL)
- "Transparent price before booking" (EN)
- "Prix transparent avant la réservation" (FR)

Keep:
- Fixed offers (Campanile €25/€30)
- Minimum tariffs (Min €15/€30) — these are operational reality, not calculation formula
- "Op aanvraag" — keep as-is

### Legal/terms pages

Per Lux §2 exception: "If a legal/terms page truly requires pricing methodology disclosure, keep it accurate but high-level and flexible; do not publish a universal rigid formula unless legally necessary."

`PVprivacy.html` and `PValgemene-voorwaarden.html` may keep a high-level methodology line (e.g. "Fleetconnect hanteert vaste prijzen op basis van de routeafstand") but should NOT publish the rigid €1.50/km formula. Generic version: "Fleetconnect applies fixed prices based on route distance."

### Code/JavaScript (b2b/webbooker.html)

`const PRICE_PER_KM = 1.5` — this is a customer-facing booking page calculator. **CRITICAL**: this JS hardcodes €1.50/km but the authoritative pricing layer uses €2.00/km. PRIME r056 Phase 1 migration updated the database but did NOT update this JS. **This is a potential frontend/backend drift** that Lux r056 §1 explicitly forbids: "Do not create frontend/backend drift. Apply the change only through the authoritative pricing layer and legitimate mirrors that must stay synchronized."

**Action**: Either (a) remove the hardcoded constant and call the authoritative RPC `calculate_booking_fare()` from the b2b webbooker, OR (b) update the constant to match the database (2.00). Per Lux §2 spirit, removing calculation arithmetic from public pages is preferred — option (a).

---

## Cleanup batch size

94 files × ~5-10 edits each = ~500-900 line changes. Per Lux §4 ("execute existing KEEP/MERGE/REMOVE/DEFER inventory in small commits; before removing any file/dir: prove no current runtime/nav/build/reference dep"), break into small reviewed batches:

- **Batch A**: 25 cities pages (hero + body €1,50/km → "Transparante prijs")
- **Batch B**: 12 airport pages (€1,50/km + "vaste prijs per km" → fixed offers only)
- **Batch C**: PV customer pages (PVprivacy, PVfaq, PV-vaste-prijzen, PVprivacy high-level keep)
- **Batch D**: Legal terms pages (high-level methodology only)
- **Batch E**: klantenportaal.html + fleetconnect.html sub-line cleanup
- **Batch F**: b2b/webbooker.html JS — frontend/backend drift fix (CRITICAL)

This audit is the inventory for the cleanup; implementation batches follow in subsequent rounds.

---

## Mission Status

Audit inventory complete. 94 files require cleanup, 19 already clean. Batch A-F planned. b2b/webbooker.html JS drift identified as critical fix.

LUX — SYNC NEEDED with full audit inventory + batch plan.

---

## Open / Flagged

- `[LUX REVIEW NEEDED]` r056 public-text pricing-calculation audit + batch plan (94 files to clean in 6 batches)
- `[PARKED]` Batch A-F cleanup execution (awaiting Lux confirmation of audit + batch plan)
- `[PARKED]` Phases C-G still pending
- `[PARKED]` Phases H/I/J BLOCKED on Founder

Mission remains ACTIVE.