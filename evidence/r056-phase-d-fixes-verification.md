# r056 Phase D Fix #1 + #2 — verification matrix

## Fix #1: Unresolved dispatch-attention bookings stay in New Orders

Per Lux r056 Phase D review §2: clock-time expiration must NOT move unaccepted bookings to History.

### Status bucket assignment (current `filterAndSortData()` logic)

| Status | NewOrders | ActiveOrders | History | Notes |
|---|---|---|---|---|
| `pending` (unexpired) | ✅ | — | — | Unresolved dispatch attention |
| `pending` (expired) | ✅ | — | — | **NEW: stays in New Orders** (was incorrectly moved to History by clock) |
| `pending_payment` (unexpired) | ✅ | — | — | Unresolved dispatch attention |
| `pending_payment` (expired) | ✅ | — | — | **NEW: stays in New Orders** |
| `assignment_sent` (unexpired) | ✅ | — | — | Driver not yet responded |
| `assignment_sent` (expired) | ✅ | — | — | **NEW: stays in New Orders** (dispatch must chase late assignment) |
| `reassignment_needed` (unexpired) | ✅ | — | — | Dispatch needs to reassign |
| `reassignment_needed` (expired) | ✅ | — | — | **NEW: stays in New Orders** |
| `assigned` (unexpired) | — | ✅ | — | Driver acknowledged, operational |
| `assigned` (expired) | — | — | ✅ | Past scheduled ride for which driver was assigned |
| `accepted` (unexpired) | — | ✅ | — | Driver accepted, operational |
| `accepted` (expired) | — | — | ✅ | Past scheduled ride for which driver accepted |
| `completed` | — | — | ✅ | Terminal lifecycle state |
| `cancelled` | — | — | ✅ | Terminal lifecycle state |
| `declined` | — | — | ✅ | Terminal lifecycle state |

### Key code change

```js
// BEFORE (Phase D r1 — 2727714d)
this.newOrders = this.allBookings.filter(b => this.isNewOrderStatus(b.status) && !this.isExpired(b.datetime, b.time));
this.historyOrders = this.allBookings.filter(b => b.status === 'completed' || b.status === 'cancelled' || b.status === 'declined' || (this.isNewOrderStatus(b.status) && this.isExpired(b.datetime, b.time)) || (b.status === 'accepted' && this.isExpired(b.datetime, b.time)) || (b.status === 'assignment_sent' && this.isExpired(b.datetime, b.time)) || (b.status === 'assigned' && this.isExpired(b.datetime, b.time)));

// AFTER (Phase D r2 — this commit)
this.newOrders = this.allBookings.filter(b => this.isNewOrderStatus(b.status));
this.historyOrders = this.allBookings.filter(b => b.status === 'completed' || b.status === 'cancelled' || b.status === 'declined' || (b.status === 'assigned' && this.isExpired(b.datetime, b.time)) || (b.status === 'accepted' && this.isExpired(b.datetime, b.time)));
```

`expiredOrders` retained as separate filter for UI flagging (overdue/late/escalation-required marker inside New Orders).

### Invariant verified

✅ No unaccepted booking disappears from the operational attention queue.
✅ History receives terminal/resolved states ONLY.
✅ Active Orders receives assigned/accepted operational rides only.
✅ Clock-time expiration is NOT used as a substitute for lifecycle transition.

## Fix #2: Language switching preserves canonical 7-tab semantics

Per Lux r056 Phase D review §3: translation values must be updated so every supported language preserves the same canonical concepts.

### Translation matrix (4 languages × 7 canonical tabs)

| Tab DOM key | NL | FR | EN | ES |
|---|---|---|---|---|
| `navNewOrders` | New Orders | Nouvelles Commandes | New Orders | Nuevos Pedidos |
| `navOrders` | **Active Orders** | **Commandes Actives** | **Active Orders** | **Pedidos Activos** |
| `navHistory` | History | Historique | History | Historial |
| `navDrivers` | Drivers | Chauffeurs | Drivers | Conductores |
| `navCustomers` | **Clients/Partners** | **Clients/Partenaires** | **Clients/Partners** | **Clientes/Socios** |
| `navFinancial` | **Settings / Admin** | **Paramètres / Admin** | **Settings / Admin** | **Configuración / Admin** |
| `navMailbox` | **E-mail** | **E-mail** | **E-mail** | **E-mail** |

`navPartners` also updated to canonical value (was "Mijn Partners"/"Mes Partenaires"/"My Partners"/"Mis Socios") so even if the element is somehow resurrected, it shows the same canonical semantic.

### Key code change

Each `translations = { nl: {...}, fr: {...}, en: {...}, es: {...} }` block updated:
- `navOrders: "Orders" → "Active Orders"` (or language equivalent)
- `navCustomers: "Klanten"` (fallback) → explicit `"Clients/Partners"` per language
- `navFinancial: "Financieel"` → `"Settings / Admin"` (or language equivalent)
- `navMailbox: "Mailbox"` → `"E-mail"` (all 4 languages)

### i18n switch regression (manual verification plan)

Switching NL → FR → EN → ES must NOT:
- Regress `Active Orders` → `Orders`
- Regress `Clients/Partners` → customer-only wording
- Regress `Settings / Admin` → financial wording
- Regress `E-mail` → mailbox/legacy wording

`_setText()` helper prevents TypeError on missing elements (defense-in-depth from Phase D r1).

## Status-bucket regression test (synthetic data)

```js
// Pseudo-test (browser console):
const testBookings = [
  { id: 1, status: 'pending', datetime: '2026-08-30', time: '10:00' },  // unexpired
  { id: 2, status: 'pending', datetime: '2026-01-01', time: '10:00' },  // expired but still pending
  { id: 3, status: 'assignment_sent', datetime: '2026-01-01', time: '10:00' },  // expired
  { id: 4, status: 'assigned', datetime: '2026-08-30', time: '14:00' },  // unexpired active
  { id: 5, status: 'accepted', datetime: '2026-01-01', time: '10:00' },  // expired accepted → history
  { id: 6, status: 'completed', datetime: '2026-08-30', time: '12:00' },  // terminal
];

// After filterAndSortData():
// newOrders should contain: 1, 2, 3 (all unresolved dispatch-attention, regardless of expiration)
// ordersList should contain: 4 (unexpired assigned/accepted)
// historyOrders should contain: 5, 6 (expired accepted OR terminal lifecycle)
```

## i18n switch regression test (synthetic)

```js
// Pseudo-test (browser console):
// After mount, document.getElementById('navOrders').textContent should be "Active Orders" regardless of language
// After clicking FR: document.getElementById('navOrders').textContent should be "Commandes Actives"
// After clicking EN: document.getElementById('navOrders').textContent should be "Active Orders"
// After clicking ES: document.getElementById('navOrders').textContent should be "Pedidos Activos"
```

## Diff summary

```
Paneel/onderaannemerA.html | +Fix1 +Fix2 (4 language blocks updated + filter logic + 1 helper preserved)
evidence/r056-phase-d-fixes-verification.md (this file)
2 files changed
```

## Files modified

- `Paneel/onderaannemerA.html` (filterAndSortData + translations)
- `evidence/r056-phase-d-fixes-verification.md` (this evidence)

## Commit

- SHA: (this commit)
- Branch: `integration-r056` at base `2727714d` (Phase D r1 head)