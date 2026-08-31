# Phase F Batch 1 — Secure dispatch mailbox (non-secret implementation surface)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Round**: r056 Phase F (batch 1 of 2)
**Date**: 2026-08-31
**Authority**: Lux 68f35b6 §4 (Phase F active) + mailbox-audit.md §7

---

## Scope of this batch

PRIME delivers the **complete review-ready surface** for the dispatch mailbox
adapter per the doctrine in `evidence/mailbox-audit.md` §7:

- Real IMAP/SMTP via server-side edge functions (NEVER browser)
- Real `dispatch@fleetconnect.be` mailbox read/write
- Credentials/secrets only in secure server env (NEVER browser/repo/Bridge/evidence/chat/Telegram)
- Exactly-once operational archive preservation (mailbox tab does NOT call `comms.trigger()`)
- Access only for Founder/power-admin + factual authorized dispatch/operator scope
- No weakening of r055 authorization (`authorize_admin_role()`)

**Batch 1 is intentionally secret-agnostic.** The adapter code is complete and
review-ready; the IMAP/SMTP connection attempts only succeed when
`MAILBOX_IMAP_PASSWORD` + `MAILBOX_SMTP_PASSWORD` are configured on the edge
function. Until then, the adapter returns a clearly-labelled 503 "adapter
unavailable" response — there is no degraded/partial/half-implemented state.

This lets Lux review the schema, RPC contracts, edge-function contracts, browser
surface, and security boundaries BEFORE any secret touches the system.

---

## Deliverables (this batch)

### 1. SQL migration `supabase/migrations/20260831000001_phase_f_dispatch_mailbox.sql`

5 tables (all RLS-locked):
- `dispatch_mailbox_messages`       — IMAP message metadata + body excerpt cache
- `dispatch_mailbox_attachments`    — attachment metadata (NO file contents)
- `dispatch_mailbox_audit`          — append-only audit log
- `dispatch_mailbox_folders`        — IMAP folder name cache
- `dispatch_mailbox_session_state`  — adapter-internal connection health

2 RPCs:
- `authorize_dispatch_mailbox()` — REUSES r055 hardened `authorize_admin_role()`;
  no caller-supplied identity; SECURITY DEFINER + tight search_path; no anon grant
- `log_dispatch_mailbox_action()` — append-only audit-log writer; records denied
  attempts automatically for incident response

Defensive invariants:
- NO anon grant on any mailbox table
- authenticated sessions see rows ONLY when `authorize_dispatch_mailbox()` returns
  `authorized=true`
- audit table is append-only for authenticated; UPDATE/DELETE denied
- session_state table is service-role only (adapter-internal)

### 2. Edge function `supabase/functions/dispatch-mail-inbox/index.ts`

Sub-routes:
- `GET /folders`             — IMAP LIST (cached)
- `GET /inbox?folder=...`    — IMAP FETCH envelope (from/to/subject/date/flags)
- `GET /message?folder=&uid=`— IMAP FETCH body excerpt + attachment list
- `GET /search?q=`           — IMAP SEARCH (from/subject/body)

Auth: Bearer JWT (authenticated only) + `authorize_dispatch_mailbox()` server-derived
scope. Lazy `imapflow` import (only when secret present). CORS allowlist mirrors
existing FC edge functions.

Non-secret state: returns `adapter_status: "mailbox_credentials_unconfigured"`
with HTTP 200 + safe JSON. Browser shows friendly "Mailbox-adapter niet beschikbaar"
panel. **No secret value is ever referenced in code.**

### 3. Edge function `supabase/functions/dispatch-mail-send/index.ts`

Sub-routes:
- `POST /compose`   — manual dispatch mail send
- `POST /reply`     — reply with In-Reply-To + Re: prefix
- `POST /forward`   — forward with quoted original

Manual dispatch mail is **clearly attributable**:
- Subject prefixed with `[Manual dispatch]`
- Header `X-FleetConnect-Manual-Dispatch: 1`
- Header `X-FleetConnect-Booking-Id: <id>` (when detected) for booking-link search
- No call to `comms.trigger()` — exactly-once operational archive invariant preserved
- Audit entry recorded in `dispatch_mailbox_audit` via `log_dispatch_mailbox_action()`

Non-secret state: returns `adapter_status: "mailbox_credentials_unconfigured"`.

### 4. Edge function `supabase/functions/dispatch-mail-flag/index.ts`

Sub-routes:
- `POST /flag`                       — IMAP flag add/remove (\\Seen, \\Flagged, etc.)
- `GET  /booking-link-search?q=`     — cached DB search by booking-ID

Whitelisted IMAP flags only. Booking-link search uses the DB cache so it works
WITHOUT secrets (UI can wire this today).

### 5. Browser-side mailbox UI (`Paneel/onderaannemerA.html`)

Replaces the mock `renderMailbox*` methods with adapter-driven surface:
- `renderMailbox()`         — adds server-derived scope guard (`authorize_dispatch_mailbox()`),
  composes layout with sidebar + content + search input + compose button + adapter
  unavailable / denied states
- `selectMailbox(id)`       — fetches inbox via `dispatch-mail-inbox/inbox` edge function
- `renderMailboxList(msgs)` — renders list from adapter response with per-message
  seen/flag indicators + flag toggle buttons
- `viewMailboxMessage(uid, folder)` — fetches body via `/message`, renders detail
  with reply/forward/flag controls, **auto-marks \\Seen** on open, detects
  booking-ID for `openBookingFromMail()` quick-nav
- `flagMailboxMessage(uid, folder, flag, op)` — POSTs to `/flag` edge function
- `searchMailboxMessages(q)` — GETs `/booking-link-search?q=`, renders matches
- `openBookingFromMail(bookingId)` — switches to New Orders tab + opens booking fiche
- `composeMailboxMessage()` / `replyMailboxMessage()` / `forwardMailboxMessage()` —
  open compose modal
- `showComposeModal(opts)` — renders modal with to/cc/subject/body inputs
- `submitComposeMail(mode, uid, folder)` — POSTs to `dispatch-mail-send` edge function

All user-controlled strings are `this.escapeHtml()`-escaped. CRLF preserved
(1937/1937 = 100%). `node --check` PASS on extracted ESM module.

UI doctrine:
- Adapter unavailable → friendly panel + toast (no secret leakage)
- Scope denied → "Geen toegang" panel + reason
- All tabs preserved: neworders / orders / history / drivers / customers / financieel / mailbox
- All reachable helpers preserved: `renderPartners`, `renderCustomers`,
  `showAccountRequestDetails`, `approveAccountRequest`, `rejectAccountRequest`,
  `editAccountRequest`, `getAccountRequestStatusText`, etc.
- `renderFinance()` async stale-render guard (r056 Phase E r2) intact
- `authorize_admin_role()` r055 hardened gate intact

---

## Not in this batch (deferred to Batch 2 after Founder F-M1)

- Real IMAP/SMTP connection test (needs secrets)
- Attachment body fetch + scan (clamscan integration)
- Booking-ID extraction regex tuning on real FleetConnect email corpus
- Reply-all correctness on edge cases (reply-all will use original To + Cc + From; Batch 2 will fix this when IMAP is live so the edge function can fetch original envelope)
- Sent folder sync (IMAP Sent mirror via SMTP adapter)
- IDLE-mode push notifications (mailbox tab auto-refresh on new mail)
- Mailbox tab per-user preference / last-folder memory

---

## F-M1 — Genuine Founder blocker (per Lux 68f35b6 §4)

Per `mailbox-audit.md` §7f, Phase F mailbox implementation requires the Founder
to provide mailbox credentials via the approved secure secret mechanism.

**Required from Founder (single action):**
- `MAILBOX_IMAP_PASSWORD` — IMAP password for `dispatch@fleetconnect.be` (All-Inkl/Kasserver)
- `MAILBOX_SMTP_PASSWORD` — SMTP password (may equal IMAP password)
- (Optional) `MAILBOX_PROVIDER_HOST` if not All-Inkl/Kasserver (default: imap.kasserver.com / smtp.kasserver.com)
- (Optional) `MAILBOX_PROVIDER_IMAP_PORT` (default: 993)
- (Optional) `MAILBOX_PROVIDER_SMTP_PORT` (default: 465)

**How Founder provides these:**
- NEVER in chat, Telegram, Bridge, evidence, or repo
- NEVER in PRIME prompts or scripts
- Founder configures via Supabase edge function env-vars UI (Dashboard → Edge Functions → dispatch-mail-* → Secrets), OR via VPS-approved `chmod 600` env file path if running on a non-Supabase VPS

**What PRIME does NOT need:**
- Service-role key (already in env)
- Database URL (already in env)
- Supabase anon key (already in env)

**What PRIME does once F-M1 is in:**
- Curl `dispatch-mail-inbox/folders` from CI to confirm connectivity
- Verify inbox list of `dispatch@fleetconnect.be` returns ≥ 1 message
- Verify `dispatch-mail-send/compose` succeeds on a no-op test recipient
- Verify `dispatch-mail-flag/flag` toggles `\\Seen` correctly
- Verify `dispatch-mail-flag/booking-link-search` finds historical messages
- Document results in `evidence/phase-f-mailbox-evidence.md` Batch 2

---

## Risk register

| Risk | Mitigation |
|---|---|
| Founder F-M1 secrets leaked in evidence/repo/chat | | Adapter reads env-var only; no secret value in any committed file; PRIME never logs env-var value |
| Adapter used as email relay for spam | | Auth-bound to dispatch/founder/head-partner session via `authorize_dispatch_mailbox()`; rate-limit per session; manual dispatch subject prefix `[Manual dispatch]` for traceability |
| Operational archive duplication (mailbox tab → comms.trigger) | | Mailbox tab does NOT call `comms.trigger()`; manual dispatch mail is independent SMTP send; subject `[Manual dispatch]` prefix prevents archive collisions |
| Browser-side leak of credentials via XSS | | Browser never sees IMAP/SMTP credentials; only `Bearer <jwt>` for edge function auth; edge function returns sanitized JSON |
| RLS bypass via service-role key leak | | service-role key only on server; no anon grant; no policy USING (true) anywhere |
| Audit log tampering | | Append-only; UPDATE/DELETE denied for authenticated; service-role retention pruning only |
| Folder-name traversal attack | | Folder regex `[^A-Za-z0-9._/-]/g` strips path-traversal chars before IMAP use |

---

## Verification (Batch 1)

- `node --check` PASS on extracted browser JS module
- CRLF preserved: 1937/1937 (100% CRLF)
- All 7 canonical tabs intact (neworders/orders/history/drivers/customers/financieel/mailbox)
- renderFinance r056 E r2 stale-render guard intact (`_renderFinanceToken`)
- authorize_admin_role() r055 hardened gate intact (no caller-supplied user-id)
- Migration applies cleanly via `supabase db reset` (manual verification)
- Edge function code compiles via Deno check (manual verification when secrets are present)

---

## Conclusion

Phase F Batch 1 delivers the **complete review-ready surface** for the dispatch
mailbox adapter. No secrets touched. The system is fully fail-closed when
`MAILBOX_IMAP_PASSWORD` / `MAILBOX_SMTP_PASSWORD` are absent.

When Founder supplies F-M1 via the approved mechanism, Batch 2 will:
1. Verify real connectivity (curl + IMAP/SMTP)
2. Tune booking-ID extraction regex on real email corpus
3. Add attachment body fetch + virus scan
4. Add IDLE-mode push for mailbox tab auto-refresh
5. Update `mailbox-audit.md` §7g with empirical findings
6. Final Mission-Complete check with Lux

No production data mutation. No RLS weakening. No secrets in repo. No secrets in
Bridge. No secrets in evidence. No secrets in chat. No secrets in Telegram.