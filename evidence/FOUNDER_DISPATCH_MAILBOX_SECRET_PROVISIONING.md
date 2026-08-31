# F-M1 — Founder Dispatch Mailbox Secret Provisioning (Phase F blocker)

**This document is the SINGLE approved mechanism for the Founder to provide the
mailbox credentials required for Phase F real-IMAP/SMTP integration.**

Per Lux 68f35b6 §4:
> "credentials/secrets only in secure server environment/config, never
> browser/repo/Bridge/evidence/chat/Telegram"

Per mailbox-audit.md §7f:
> "Founder provides `MAILBOX_IMAP_PASSWORD` + `MAILBOX_SMTP_PASSWORD` for
> `dispatch@fleetconnect.be` via approved secure secret mechanism"

---

## What the Founder provides (3 secrets, optionally 3 more)

### Required

| Env var | What it is | How to obtain |
|---|---|---|
| `MAILBOX_IMAP_PASSWORD` | IMAP password for `dispatch@fleetconnect.be` | All-Inkl/Kasserver webmail → Settings → Email accounts → dispatch@fleetconnect.be → password (or reset) |
| `MAILBOX_SMTP_PASSWORD` | SMTP submission password (may equal IMAP password) | Same as above (All-Inkl/Kasserver uses the same mailbox password for both IMAP and SMTP submission by default) |

### Optional (defaults already set)

| Env var | Default | When to override |
|---|---|---|
| `MAILBOX_USER` | `dispatch@fleetconnect.be` | If using a different mailbox identity |
| `MAILBOX_PROVIDER_HOST` | `imap.kasserver.com` for IMAP / `smtp.kasserver.com` for SMTP | If migrating off All-Inkl/Kasserver |
| `MAILBOX_PROVIDER_IMAP_PORT` | `993` | If All-Inkl changes port (unlikely) |
| `MAILBOX_PROVIDER_SMTP_PORT` | `465` | If All-Inkl changes port (unlikely; alternate is `587/STARTTLS`) |

---

## How the Founder provides these

### Path A — Supabase Edge Functions (recommended)

If the mailbox adapter is deployed as Supabase Edge Functions:

1. Open Supabase Dashboard → Edge Functions
2. For each function: `dispatch-mail-inbox`, `dispatch-mail-send`, `dispatch-mail-flag`:
   - Settings → Secrets → Add secret
   - Name: `MAILBOX_IMAP_PASSWORD`
   - Value: (the actual password — Founder types it directly into Supabase UI)
3. Repeat for `MAILBOX_SMTP_PASSWORD`

Supabase stores secrets encrypted at rest; only the edge function runtime can
read them. Founder's secret value is **never visible** to PRIME or anyone else
after this step.

### Path B — VPS env file (alternative)

If running the adapter on a VPS (non-Supabase):

1. Founder runs (on the VPS):
   ```bash
   sudo touch /etc/fleetconnect/mailbox.env
   sudo chmod 600 /etc/fleetconnect/mailbox.env
   sudo nano /etc/fleetconnect/mailbox.env
   ```
2. Founder pastes:
   ```
   MAILBOX_IMAP_PASSWORD=<actual-password>
   MAILBOX_SMTP_PASSWORD=<actual-password>
   MAILBOX_USER=dispatch@fleetconnect.be
   ```
3. Founder saves; file is now `chmod 600` (Founder-only readable)

PRIME does NOT need to read this file. The adapter process reads it at startup.

---

## What PRIME does NOT do

- PRIME does NOT request the secret value via Telegram, Bridge, chat, or prompt
- PRIME does NOT generate, reset, or guess the password
- PRIME does NOT log the secret value anywhere
- PRIME does NOT commit the secret value to any repo
- PRIME does NOT pass the secret value through any PRIME-controlled environment

If PRIME asks Founder for the secret value via any of these channels, Founder
should refuse and re-route to this document.

---

## What the Founder does NOT do

- Founder does NOT paste the secret in any chat, Telegram, PRIME prompt, or evidence file
- Founder does NOT include the secret in commit messages, PR descriptions, or repo files
- Founder does NOT share the secret with anyone outside the immediate technical setup (e.g., not in a Google Doc, not in an email, not in a Slack channel)

---

## Verification (after Founder provides secrets)

PRIME will verify connectivity **without seeing the secret value**:

1. Curl edge function `/folders` → expect HTTP 200 with folder list (NOT 503)
2. Curl `/inbox?folder=INBOX` → expect HTTP 200 with message envelope list
3. Curl `/message?folder=INBOX&uid=<some-uid>` → expect HTTP 200 with body excerpt
4. POST `/flag` with `\\Seen` add → expect HTTP 200 + DB audit row updated
5. POST `/compose` with `to=founder-test@fleetconnect.be` → expect HTTP 200 + Sent folder entry

All these tests run with **zero secret value in PRIME's command output**.

If any test fails, PRIME surfaces the **error** to the Founder, not the secret.
If All-Inkl rejects auth, Founder is asked to verify the password via the
All-Inkl webmail UI (NOT to share it with PRIME).

---

## Security boundary

```
Founder ──secret──> Supabase Vault / VPS chmod 600 env file ──runtime──> Adapter process ──TLS──> All-Inkl IMAP/SMTP
                                                                            │
                                                                            ├──> cached metadata ──> dispatch_mailbox_messages (Supabase DB)
                                                                            ├──> audit entries ──────> dispatch_mailbox_audit (Supabase DB)
                                                                            └──> scope-gated JSON ──> browser via Bearer JWT
```

PRIME has visibility into:
- The Supabase DB rows (metadata, audit)
- The browser JSON responses (envelope, body excerpt, attachment list)
- The edge function logs (timestamps, error reasons — NEVER secret value)

PRIME does NOT have visibility into:
- The env-var values themselves
- The All-Inkl IMAP/SMTP authentication exchange
- The Founder's local Webmail UI

---

## After verification

Once all 5 verification steps PASS:
1. PRIME writes `evidence/phase-f-mailbox-evidence.md` Batch 2 (no secret value)
2. PRIME commits to integration-r056
3. PRIME publishes via Bridge for Lux final review
4. Lux reviews Batch 2 acceptance
5. Founder runs hands-on test on real email
6. Phase F closes; Phase G full regression follows

Until all 5 verification steps PASS, Phase F remains "Batch 1 ready, awaiting F-M1".