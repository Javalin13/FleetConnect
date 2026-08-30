# r056 vercel guard fix — removed dead `_archive` rules (per Lux r056 §2 preferred)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Round**: r056
**Date**: 2026-08-30T22:35+02:00
**Branch**: `integration-r056`
**Base SHA**: `0725926` (Phase C-final deletion)
**Head SHA**: TBD

---

## What changed (per Lux r056 §2 preferred option)

Lux r056 Phase C-final review ACCEPTED the deletion but identified a small deployment-config defect:
- Previous `vercel.json` rewrite `"/_archive/:path*" → "/404.html"` was broken because `404.html` does NOT exist in the tree
- A rewrite to a missing file is NOT a clean explicit denial strategy

**Per Lux §2 preferred option**: since `_archive/` no longer exists in final tree, **REMOVE the unnecessary `_archive` header/rewrite rules entirely**. Direct `/_archive/...` paths will resolve as ordinary not-found by Vercel default.

---

## vercel.json fix applied

**Removed**:
- `"headers"` block with `x-robots-tag: noindex,nofollow` for `/_archive/(.*)`
- `"rewrites"` entry mapping `/_archive/:path*` to `/404.html`

**Result**:
- vercel.json: `headers: none`, `0 _archive references in rewrites`
- 42 rewrites remain (all for active routes: portal.fleetconnect.be, /booking, /b2b, /dashboard, /klantenportaal, etc.)
- `/_archive/...` paths will resolve as ordinary Vercel 404 (not-found by default) — clean factual behavior, no stale rules

---

## Final vercel.json (post-fix)

```json
{
  "rewrites": [
    {
      "source": "/",
      "has": [{ "type": "host", "value": "portal.fleetconnect.be" }],
      "destination": "/PV/index.html"
    },
    { "source": "/", "has": [{ "type": "host", "value": "client.fleetconnect.be" }], "destination": "/PV/index.html" },
    { "source": "/", "has": [{ "type": "host", "value": "partners.fleetconnect.be" }], "destination": "/partner-app/index.html" },
    { "source": "/", "has": [{ "type": "host", "value": "partner.fleetconnect.be" }], "destination": "/partner-app/index.html" },
    { "source": "/", "destination": "/PV/PV.html" },
    { "source": "/nl", "destination": "/PV/PV.html" },
    ... [38 more active routes]
    { "source": "/taxi-waterloo", "destination": "/cities/taxi-waterloo.html" }
  ]
}
```

No `_archive` references. No `404.html` dependency. Clean factual behavior.

---

## Verification (per Lux §2)

- ✅ `404.html` does NOT exist (per `os.path.exists` check)
- ✅ vercel.json `headers` block removed
- ✅ vercel.json `0` _archive references in rewrites
- ✅ `_archive/` directory does NOT exist in tree (`find` confirmed)
- ✅ Final deployment tree contains no `_archive/` paths; direct `/_archive/...` requests resolve as ordinary Vercel 404 not-found

---

## Mission Status

Phase C-final cleanup TRULY COMPLETE (deletion + vercel config now clean). PRIME work NEXT (per Lux §3): execute Phase D dashboard final implementation.

LUX — SYNC NEEDED with vercel fix + Phase D ready.

---

## Open / Flagged

- `[WAITING FOR LUX]` r056 vercel guard fix (unnecessary `_archive` rules removed, clean factual 404 behavior)
- `[READY]` Phase D dashboard final implementation (canonical New Orders → Active Orders → History → Drivers → Clients/Partners → E-mail → Settings/Admin)
- `[PARKED]` Phase E portal rationalization
- `[PARKED]` Phase F mailbox adapter + UI shell (needs Founder F-M1 credential for real connection)
- `[PARKED]` Phase G full regression rerun
- `[PARKED]` Phase H/I/J BLOCKED on Founder (F1 staging access + F-M1 mailbox credential + hands-on acceptance)
- `[POST-MISSION LOCKED]` FleetConnect revamp → TaxiBrussels.be → RYZEN master → RYZEN footer

Mission remains ACTIVE.