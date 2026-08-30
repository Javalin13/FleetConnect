# r056 Phase D r3 corrections — status-driven buckets + encoding + explicit i18n

Per Lux r056 Phase D r2 review (`48d7365`) + `039745e`: Phase D is still not closed. Two remaining defects addressed in this commit.

## Fix #1 — Active Orders still clock-expires (Lux §2)

### Code change (`filterAndSortData()` line 612-628)

**BEFORE** (Phase D r2, commit `7e3a089`):
```js
this.ordersList = this.allBookings.filter(b => (b.status === 'assigned' || b.status === 'accepted') && !this.isExpired(b.datetime, b.time));
this.historyOrders = this.allBookings.filter(b => b.status === 'completed' || b.status === 'cancelled' || b.status === 'declined' || (b.status === 'assigned' && this.isExpired(b.datetime, b.time)) || (b.status === 'accepted' && this.isExpired(b.datetime, b.time)));
```

**AFTER** (Phase D r3, this commit):
```js
// Active Orders = assigned OR accepted, regardless of clock expiration.
// Late/in-progress visual flag (e.g. overdue pickup) belongs in UI, not in this filter.
this.ordersList = this.allBookings.filter(b => b.status === 'assigned' || b.status === 'accepted');
// History = TERMINAL lifecycle states ONLY. No clock-time derivation.
this.historyOrders = this.allBookings.filter(b => b.status === 'completed' || b.status === 'cancelled' || b.status === 'declined');
```

### Canonical rule (per Lux §2)

> **Time is a presentation/escalation signal; status transition is the lifecycle source of truth.**

### Status bucket assignment (final, after r3)

| Status | Bucket (unexpired) | Bucket (expired) | Notes |
|---|---|---|---|
| `pending` | New Orders | New Orders | Unresolved dispatch attention |
| `pending_payment` | New Orders | New Orders | Unresolved dispatch attention |
| `assignment_sent` | New Orders | New Orders | Driver has not responded — dispatch must chase |
| `reassignment_needed` | New Orders | New Orders | Dispatch must reassign — stays visible |
| `assigned` | Active Orders | **Active Orders** | **NEW: no clock-time move to History** |
| `accepted` | Active Orders | **Active Orders** | **NEW: no clock-time move to History** |
| `completed` | — | History | Terminal |
| `cancelled` | — | History | Terminal |
| `declined` | — | History | Terminal |

**No ride moves New → Active → History merely because wall-clock time passes.**

### Invariants verified

1. ✅ Unresolved dispatch-attention statuses remain New Orders regardless of clock
2. ✅ assigned/accepted remain Active Orders regardless of clock until truthful terminal transition
3. ✅ History is lifecycle-terminal, not time-derived

## Fix #2 — `FINANCIËN` encoding regression (Lux §3.2)

### Original bug (Phase D r2)

`navFinance: "FINANCI˛N"` — bytes were `FINANCI\xcb\x9bN` (mojibake from my Python byte substitution).

### Correction (this commit)

`navFinance: "FINANCIËN"` — bytes are now correct UTF-8 `FINANCI\xc3\x8bN`.

### Verifications

```
grep "FINANCI" Paneel/onderaannemerA.html
298:                <div class="nav-section-title" id="navFinance">FINANCIËN</div>
457:                navManagement: "BEHEER", ... navFinance: "FINANCIËN", ...
```

Both occurrences show `FINANCIËN` correctly. Raw UTF-8 bytes confirmed: `b'FINANCI\xc3\x8bN'`.

## Fix #3 — `navMailbox` explicit in all 4 languages (Lux §3.1)

### Original state

- NL had `navMailbox: "E-mail"` ✅
- FR/EN/ES **did NOT define** `navMailbox` — relied on `_setText` fallback `'E-mail'`

### Correction (this commit)

All 4 languages now explicitly define `navMailbox: "E-mail"`:

```js
nl: { ... navMailbox: "E-mail" ... }
fr: { ... navMailbox: "E-mail" ... }
en: { ... navMailbox: "E-mail" ... }
es: { ... navMailbox: "E-mail" ... }
```

This makes the 4×7 canonical i18n matrix **literal** (no fallback dependency).

## Verifications performed

### Syntax check
```
node --check /tmp/onderaannemer_module.mjs
# rc=0, no errors
```

### 4×7 i18n canonical matrix (literal extraction, no fallback)

| Tab | NL | FR | EN | ES |
|---|---|---|---|---|
| navNewOrders | New Orders | Nouvelles Commandes | New Orders | Nuevos Pedidos |
| navOrders | Active Orders | Commandes Actives | Active Orders | Pedidos Activos |
| navHistory | History | Historique | History | Historial |
| navDrivers | Drivers | Chauffeurs | Drivers | Conductores |
| navCustomers | Clients/Partners | Clients/Partenaires | Clients/Partners | Clientes/Socios |
| navFinancial | Settings / Admin | Paramètres / Admin | Settings / Admin | Configuración / Admin |
| navMailbox | E-mail | E-mail | E-mail | E-mail |

All 28 keys present. **No fallback dependency.**

### Encoding check
- 2/2 `FINANCIËN` occurrences have correct UTF-8 bytes `FINANCI\xc3\x8bN`
- No mojibake patterns (`\xcb\x9b`) remain

### Status-bucket check
- 9 booking statuses × 3 buckets verified
- **No clock-time derivation in any filter**
- History = terminal lifecycle states ONLY
- Active Orders = assigned OR accepted (no time filter)
- New Orders = unresolved dispatch-attention states (no time filter)

## Phase D close criteria (per Lux §4)

| # | Criterion | Status |
|---|---|---|
| 1 | Unresolved dispatch-attention statuses remain New Orders regardless of clock | ✅ |
| 2 | assigned/accepted remain Active Orders regardless of clock until truthful terminal transition | ✅ |
| 3 | History is lifecycle-terminal, not time-derived | ✅ |
| 4 | Seven canonical navigation concepts remain explicit and correct in NL/FR/EN/ES | ✅ |
| 5 | No visible encoding corruption | ✅ |
| 6 | Syntax + status-bucket + i18n regression pass | ✅ |

**All 6 close criteria met.**

## Files modified

- `Paneel/onderaannemerA.html` (`filterAndSortData` lifecycle buckets + 4 translation blocks for `navMailbox`)
- `evidence/r056-phase-d-r3-corrections-verification.md` (this file)

## Commit

- SHA: (this commit)
- Branch: `integration-r056` at base `7e3a089` (Phase D r2 head)
- Push: pending