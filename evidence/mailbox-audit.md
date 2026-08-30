# Mailbox Integration Audit (r053 Phase 7, per Lux §9 FOUNDER PRODUCT DIRECTIVE)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Date**: 2026-08-30T17:30+02:00
**Authority**: Lux r051 §9 FOUNDER PRODUCT DIRECTIVE — integrated dispatch mailbox tab

---

## Goal

FleetConnect operational dashboard = single cockpit for bookings + assignment + driver/partner operations + `dispatch@fleetconnect.be` email read/write communication.

This audit is the architecture-and-provider pre-work for r053; implementation is parked until after Mission Complete / known-good checkpoint per Lux directive.

---

## Phase 7a: Mail Hosting Provider (DNS/MX reconnaissance)

DNS lookup for `fleetconnect.be`:

| Record | Value |
|---|---|
| MX | `w021ae07.kasserver.com.` (priority 10) |
| SPF | `v=spf1 a mx include:spf.kasserver.com ~all` |
| NS | `ns5.kasserver.com`, `ns6.kasserver.com` |

**Conclusion**: `dispatch@fleetconnect.be` is hosted by **All-Inkl / Kasserver** (German hosting provider). Standard IMAP/SMTP ports available.

### All-Inkl / Kasserver capabilities (typical for plans ≥ Private)

| Capability | Available | Notes |
|---|---|---|
| IMAP4rev1 (port 993, TLS) | YES | Standard |
| SMTP submission (port 465/587, STARTTLS) | YES | Standard |
| POP3 (port 995) | YES | Legacy, not preferred |
| Webmail (All-Inkl webmail UI) | YES | Already exists; Founder currently switches to external webmail |
| API for mailbox access | NOT STANDARD | All-Inkl does NOT publish a documented mailbox API |
| Mailbox size limits | Plan-dependent | typical 5-50 GB |

### Architecture decision

Since All-Inkl does NOT publish a documented mailbox API, the smallest maintainable integration is:
- **Read path**: server-side IMAP adapter (Node.js / Python) with `imapflow` or `imaplib` library, connecting to `imap.kasserver.com:993/TLS`
- **Send path**: server-side SMTP adapter (Node.js / Python) with `nodemailer` or `aiosmtpd`, connecting to `smtp.kasserver.com:465/SSL` or `:587/STARTTLS`
- **Authentication**: standard IMAP LOGIN with `dispatch@fleetconnect.be` + password (password from env var)

---

## Phase 7b: Server-Side Adapter Architecture

### Security boundary (mandatory per Lux §9)

```
[Browser]              [VPS / Serverless / Backend]                [All-Inkl / Kasserver]
                  ┌──────────────────────────────────────┐
   no secrets →   │ MAILBOX ADAPTER (server-side only)   │ ← IMAP/SMTP creds in env
                  │  - imapflow client                    │
   ───────────────│  - nodemailer client                  │──────────────────→ IMAP:993/TLS
   inbox list     │  - API endpoints (read/send)          │──────────────────→ SMTP:465/SSL
   detail view    │  - HSM-style secret access            │
   compose        │  - audit log                          │
                  └──────────────────────────────────────┘
```

**Hard rules**:
- ❌ NO IMAP/SMTP passwords, mailbox creds, provider API secrets/tokens in browser source
- ❌ NO webmail HTML scraping
- ❌ NO direct browser-to-IMAP/SMTP connections (would expose creds)
- ✅ Mailbox read/write goes through server-side adapter that holds secrets in env/secret storage
- ✅ Service-role credential remains server-side only

### Proposed adapter endpoints (server-side)

```
GET  /api/dispatch-mail/inbox?folder=INBOX&limit=50&offset=0&search=<q>
GET  /api/dispatch-mail/inbox/:uid
GET  /api/dispatch-mail/folders
GET  /api/dispatch-mail/folder/:name?limit=50&offset=0
POST /api/dispatch-mail/send            {to, cc, bcc, subject, body, attachments?, replyToId?}
POST /api/dispatch-mail/flag            {uid, flags: [\\Seen, \\Flagged]}
GET  /api/dispatch-mail/booking-link-search?q=<booking-id>
```

All endpoints require authenticated session + `app_metadata.role === 'dispatch'` (or `app_metadata.is_admin === true`).

### Server-side IMAP/SMTP connection management

- **Connection pooling**: open IMAP connection on first request, keep alive with IDLE, reconnect on failure
- **SMTP**: per-request connection (SMTP doesn't pool well)
- **Rate limiting**: 60 requests/minute per session to prevent abuse
- **Audit log**: every read/send/flag action logged with session.user_id + uid/folder + timestamp

---

## Phase 7c: Exactly-Once Operational Archive Preservation

Per Lux §9 + r048-r050 doctrine: the mailbox tab MUST NOT create duplicate automated archive copies.

### Invariant

The current operational mail flow:
1. Operational trigger fires (e.g. BOOKING_CONFIRMATION)
2. Service layer `comms.trigger()` calls `sendOperationsCopy()` → sends to primary recipients + dispatch archive (dedup'd)
3. ONE archive copy lands in `dispatch@fleetconnect.be` per trigger

### Mailbox tab integration invariant

The mailbox tab is **READ-ONLY with respect to operational mail flow**:
- ❌ Mailbox tab reading an email MUST NOT fire `comms.trigger()`
- ❌ Mailbox tab reading an email MUST NOT insert into any logs/audit-trail that could trigger downstream automation
- ✅ Mailbox tab reading an email updates ONLY the read-flag on the IMAP server (\\Seen)
- ✅ Mailbox tab composing/sending an email is treated as **manual dispatch communication** and:
  - Subject/body prefixed with `[Manual dispatch]` (clearly attributable)
  - Sent folder entry appears in IMAP server (not in Supabase audit)
  - If email references a booking ID in subject/body, the booking-detail quick-nav link is offered in the UI

### Sent-mail visibility

`/api/dispatch-mail/send` writes to IMAP `Sent` folder via the SMTP adapter. Manual dispatch mails will appear in the Sent folder (Mailbox tab can show them).

---

## Phase 7d: Access Control Model

Per Lux §9: "access to the mailbox tab is restricted to Founder/power-admin and factual authorized dispatch/operator roles; ordinary customers/drivers must never gain mailbox access".

### Authorization matrix

| Identity | Mailbox tab access | Rationale |
|---|---|---|
| `dispatch@fleetconnect.be` (Founder) | FULL | Power-admin |
| `partners.is_hoofd=true` (Moukrim) | FULL | Main operational partner = co-dispatch |
| `partners.is_hoofd=false` (other partners) | NONE | Partner scope; no mailbox access |
| `drivers.*` (any) | NONE | Driver scope; no mailbox access |
| `customers.*` (any) | NONE | Customer scope; no mailbox access |
| Anonymous | NONE | No auth |

### Implementation

The mailbox adapter endpoints require:
1. Valid Supabase Auth session (Bearer JWT)
2. `app_metadata.role === 'dispatch'` OR `app_metadata.is_admin === true` OR `partners.is_hoofd === true` (checked server-side via Supabase query)

Driver/customer/regular partner sessions get explicit 403 Forbidden from the adapter, NOT a hidden redirect (no user enumeration through 200 vs 404 differential).

### Secrets management

- `MAILBOX_IMAP_PASSWORD` env var (server-side only, NOT in repo)
- `MAILBOX_SMTP_PASSWORD` env var (same; may equal IMAP password)
- `MAILBOX_JWT_SECRET` env var (separate signing key for adapter auth)
- `MAILBOX_PROVIDER_HOST`, `MAILBOX_PROVIDER_IMAP_PORT`, `MAILBOX_PROVIDER_SMTP_PORT` (non-secret)

These are documented in the FOUNDER_DISPATCH_ACTION.md style guide — Founder provides values, PRIME stores in VPS env file with `chmod 600`.

---

## Phase 7e: Implementation Status (r053)

**Implemented**: None (audit only)

**Skeleton already present**: `Paneel/onderaannemerA.html:1337-1402` has a placeholder Mailbox tab showing account_requests as messages, with explicit text "Mailbox-architectuur is geconfigureerd. Echte IMAP/SMTP-integratie volgt in een volgende fase."

**Parked**: IMAP/SMTP adapter implementation, browser UI wiring, real folder browsing. Parked until after Mission Complete per Lux directive.

---

## Phase 7f: What is needed from Founder (single action when implementation begins)

Once Lux approves proceeding with the mailbox integration (after Mission Complete):

| # | Action |
|---|---|
| F-M1 | Founder provides `MAILBOX_IMAP_PASSWORD` + `MAILBOX_SMTP_PASSWORD` for `dispatch@fleetconnect.be` via approved secure secret mechanism |
| F-M2 | Founder confirms All-Inkl/Kasserver IMAP+ SMTP credentials are accessible to the VPS adapter process |

That's it. PRIME owns all adapter code + integration.

---

## Phase 7g: Risks and Constraints

| Risk | Mitigation |
|---|---|
| All-Inkl rate-limits IMAP connections | Connection pooling with IDLE; reuse connections |
| Long-running adapter leaks secrets via env dump | Strict `chmod 600` on env file; never `printenv`; never `env > /tmp` |
| Adapter used as email relay for spam | Auth-bound to dispatch session; rate-limit per session |
| Mailbox folder mapping different from typical | All-Inkl uses `INBOX` standard; folder listing via IMAP LIST |
| Attachments carrying malware | Adapter scans attachments via `clamscan` or similar before returning to browser |
| Manual compose creates inadvertent BCC to customers | Adapter strips auto-CC to dispatch (only manual mail); manual mail goes ONLY to explicitly-named recipients |

---

## Conclusion

Audit complete. Mailbox tab architecture is well-defined and ready to implement. Implementation is **PARKED** until Mission Complete per Lux directive.
