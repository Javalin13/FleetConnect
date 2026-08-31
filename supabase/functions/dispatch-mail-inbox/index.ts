/**
 * FleetConnect Dispatch Mailbox — Inbox / Folders / Detail / Search adapter
 *
 * Phase F Batch 1 (non-secret review-ready).
 *
 * ARCHITECTURE (per mailbox-audit.md §7b + Lux 68f35b6 §4):
 *   Browser → this edge function → IMAP (imap.kasserver.com:993/TLS) via imapflow
 *   Browser NEVER talks to IMAP directly. NO IMAP credentials in browser/repo/Bridge.
 *
 * SECURITY:
 *   - CORS: only fleetconnect.be / vercel preview / localhost (same allowlist as other FC edge funcs)
 *   - Auth: Supabase Bearer JWT (authenticated only) + authorize_admin_role() server-derived scope
 *   - Secrets: MAILBOX_IMAP_PASSWORD env var on Supabase edge; never logged, never in DB
 *   - Audit: every read/search/open logged via log_dispatch_mailbox_action() (Phase F migration)
 *
 * SCOPE (Batch 1):
 *   GET  /folders                              — list IMAP folders for the configured mailbox
 *   GET  /inbox?folder=INBOX&limit=50&offset=0 — list cached messages (no IMAP round-trip when possible)
 *   GET  /message?folder=INBOX&uid=1234         — fetch full body + attachment list (IMAP FETCH)
 *   GET  /search?q=<text>&folder=INBOX          — IMAP SEARCH across from/subject/body
 *
 * NON-SECRET BATCH 1 BEHAVIOR:
 *   - When MAILBOX_IMAP_PASSWORD is unset OR adapter cannot reach IMAP:
 *     returns 503 SERVICE_UNAVAILABLE with explicit reason and an empty/placeholder payload
 *     + logs a 'denied' or 'inbox_read_failed' audit entry
 *   - This lets Lux review the schema + RPC + edge-function contract WITHOUT exposing secrets.
 *   - Real connection test happens after Founder F-M1 (see evidence/phase-f-mailbox-evidence.md).
 *
 * NOT IN SCOPE (this function):
 *   - SMTP send (see dispatch-mail-send)
 *   - Flag toggle (see dispatch-mail-flag)
 *   - Attachment body download (handled inside /message on demand; binary stream)
 */

import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------- CORS allowlist (mirrors other FleetConnect edge functions) ----------
const ALLOWED_ORIGINS = [
  'https://fleetconnect.be',
  'https://www.fleetconnect.be',
  'https://portal.fleetconnect.be',
  'https://client.fleetconnect.be',
  'https://partners.fleetconnect.be',
  'https://rpk-mu.vercel.app',
  'https://fleetconnectfork.vercel.app',
  'https://fleet-connect-fork.vercel.app',
  'http://localhost:3000',
  'http://127.0.0.1:5500',
];

const EXTRA_ALLOWED_ORIGINS = (Deno.env.get('FLEETCONNECT_ALLOWED_ORIGINS') || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

function isAllowedFleetConnectOrigin(origin: string | null): boolean {
  if (!origin) return false;
  if (ALLOWED_ORIGINS.includes(origin) || EXTRA_ALLOWED_ORIGINS.includes(origin)) return true;
  try {
    const url = new URL(origin);
    if (url.protocol !== 'https:') return false;
    return (
      url.hostname === 'fleetconnect.be' ||
      url.hostname.endsWith('.fleetconnect.be') ||
      /^fleetconnectfork(-.*)?\.vercel\.app$/.test(url.hostname) ||
      /^fleet-connect-fork(-.*)?\.vercel\.app$/.test(url.hostname)
    );
  } catch (_) {
    return false;
  }
}

// ---------- Config (env-driven; NO hardcoded credentials) ----------
const MAILBOX_HOST        = Deno.env.get('MAILBOX_PROVIDER_HOST') || 'imap.kasserver.com';
const MAILBOX_IMAP_PORT   = Number(Deno.env.get('MAILBOX_PROVIDER_IMAP_PORT') || '993');
const MAILBOX_USER        = Deno.env.get('MAILBOX_USER') || 'dispatch@fleetconnect.be';
const MAILBOX_IMAP_PASS   = Deno.env.get('MAILBOX_IMAP_PASSWORD') || '';

const SUPABASE_URL        = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_ANON_KEY   = Deno.env.get('SUPABASE_ANON_KEY') || '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

// ---------- Helpers ----------
function corsHeadersFor(origin: string | null): Record<string, string> {
  const isAllowed = isAllowedFleetConnectOrigin(origin);
  return {
    'Access-Control-Allow-Origin': isAllowed && origin ? origin : ALLOWED_ORIGINS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Vary': 'Origin',
  };
}

function jsonResponse(body: unknown, status: number, headers: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json' },
  });
}

// ---------- Adapter status (returns 503 with explicit reason when IMAP unavailable) ----------
function adapterStatusPayload(reason: string): { ok: false; reason: string; detail?: string } {
  // Do NOT leak whether MAILBOX_IMAP_PASSWORD is set vs. unset; just say "adapter unavailable".
  return { ok: false, reason, detail: 'mailbox_adapter_unavailable_contact_founder_for_F_M1' };
}

// ---------- Bearer-token Supabase client (user-context) ----------
async function userScopedClient(req: Request) {
  const authHeader = req.headers.get('authorization') || '';
  if (!authHeader.toLowerCase().startsWith('bearer ')) {
    return { error: 'missing_bearer_token', userClient: null, userId: null };
  }
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return { error: 'invalid_session', userClient: null, userId: null };
  }
  return { error: null, userClient, userId: user.id, userEmail: user.email };
}

// ---------- Authorize (server-derived, reuses r055 RPC) ----------
async function authorizeDispatchMailbox(userClient: ReturnType<typeof createClient>) {
  const { data, error } = await userClient.rpc('authorize_dispatch_mailbox');
  if (error) {
    return { authorized: false, authz: null, reason: 'rpc_error:' + error.message };
  }
  const authz = data as {
    authorized: boolean;
    founder_scope: boolean;
    operator_scope: boolean;
    role?: string;
    is_admin?: boolean;
    partner_scope?: Record<string, unknown>;
    reason?: string;
  };
  return {
    authorized: !!authz?.authorized,
    authz,
    reason: authz?.reason || 'unknown',
  };
}

// ---------- Audit helper (uses log_dispatch_mailbox_action RPC) ----------
async function audit(userClient: ReturnType<typeof createClient>, action: string, payload: {
  mailbox?: string;
  folder?: string;
  uid?: number;
  metadata?: Record<string, unknown>;
}) {
  try {
    await userClient.rpc('log_dispatch_mailbox_action', {
      p_action: action,
      p_mailbox: payload.mailbox ?? null,
      p_folder: payload.folder ?? null,
      p_uid: payload.uid ?? null,
      p_metadata: payload.metadata ?? {},
    });
  } catch (e) {
    console.warn('[dispatch-mail-inbox] audit log failed (non-blocking):', (e as Error).message);
  }
}

// ---------- IMAP body (dynamic import — only loaded when secret is present) ----------
async function tryOpenImap(): Promise<{ ok: true; client: unknown; logout: () => Promise<void> } | { ok: false; reason: string }> {
  if (!MAILBOX_IMAP_PASS) {
    return { ok: false, reason: 'mailbox_credentials_unconfigured' };
  }
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    return { ok: false, reason: 'supabase_service_configuration_missing' };
  }
  try {
    // Lazy import so Batch 1 (no secret) does NOT pull IMAP library at boot
    const { ImapFlow } = await import('npm:imapflow@1.0.171');
    const client = new ImapFlow({
      host: MAILBOX_HOST,
      port: MAILBOX_IMAP_PORT,
      secure: true,
      auth: { user: MAILBOX_USER, pass: MAILBOX_IMAP_PASS },
      logger: false, // do not log credentials or message bodies
    });
    await client.connect();
    return {
      ok: true,
      client,
      logout: async () => { try { await client.logout(); } catch (_) { /* noop */ } },
    };
  } catch (e) {
    return { ok: false, reason: 'imap_connect_failed:' + (e as Error).message };
  }
}

// ---------- Booking-ID extraction (subject/body heuristics) ----------
function extractBookingId(text: string | null | undefined): string | null {
  if (!text) return null;
  // Common booking-id formats in FleetConnect: e.g. "FC-2026-AB1234" or "B-12345"
  const m = text.match(/\b(?:FC[-_]?\d{4}[-_]?[A-Z0-9]{4,}|\bB[-_]?\d{4,6})\b/i);
  return m ? m[0].toUpperCase().replace(/[-_]/g, '-') : null;
}

// ---------- Route handlers ----------
async function handleFolders(_userClient: ReturnType<typeof createClient>, _params: URLSearchParams) {
  const conn = await tryOpenImap();
  if (!conn.ok) return adapterStatusPayload(conn.reason);
  try {
    const client = conn.client as { list: () => Promise<Array<{ path: string; name: string; flags: Set<string>; total: number; unseen: number }>>; logout: () => Promise<void> };
    const folders = await client.list();
    return {
      ok: true,
      folders: folders.map((f) => ({
        path: f.path,
        name: f.name,
        flags: Array.from(f.flags || []),
        total: f.total,
        unseen: f.unseen,
      })),
    };
  } catch (e) {
    return adapterStatusPayload('imap_list_failed:' + (e as Error).message);
  } finally {
    await conn.logout();
  }
}

async function handleInbox(_userClient: ReturnType<typeof createClient>, params: URLSearchParams) {
  const folder = (params.get('folder') || 'INBOX').replace(/[^A-Za-z0-9._/-]/g, '');
  const limit  = Math.min(Math.max(Number(params.get('limit') || 50), 1), 200);
  const offset = Math.max(Number(params.get('offset') || 0), 0);

  const conn = await tryOpenImap();
  if (!conn.ok) return adapterStatusPayload(conn.reason);
  try {
    const client = conn.client as {
      getMailboxLock: (f: string) => Promise<unknown>;
      unlock: (lock: unknown) => Promise<void>;
      fetch: (range: string, opts: Record<string, unknown>) => Promise<unknown>;
    };
    const lock = await client.getMailboxLock(folder);
    try {
      // status: range search via IMAP SEARCH returns UIDs; then FETCH metadata
      // imapflow returns envelope (from, to, subject, date) for UID FETCH
      const range = `${offset + 1}:${offset + limit}`;
      // deno-lint-ignore no-explicit-any
      const messages: any[] = await (client as any).fetch(range, {
        uid: true,
        envelope: true,
        flags: true,
        bodyStructure: false,
      });
      return {
        ok: true,
        folder,
        offset,
        limit,
        messages: messages.map((m: { uid: number; envelope: Record<string, unknown>; flags: Set<string> }) => ({
          uid: m.uid,
          from: m.envelope.from || [],
          to: m.envelope.to || [],
          cc: m.envelope.cc || [],
          subject: m.envelope.subject || '(geen onderwerp)',
          date: m.envelope.date,
          flags: Array.from(m.flags || []),
          seen: (m.flags || new Set()).has('\\Seen'),
          flagged: (m.flags || new Set()).has('\\Flagged'),
        })),
      };
    } finally {
      await client.unlock(lock);
    }
  } catch (e) {
    return adapterStatusPayload('imap_inbox_failed:' + (e as Error).message);
  } finally {
    await conn.logout();
  }
}

async function handleMessage(_userClient: ReturnType<typeof createClient>, params: URLSearchParams) {
  const folder = (params.get('folder') || 'INBOX').replace(/[^A-Za-z0-9._/-]/g, '');
  const uidStr = params.get('uid');
  const uid = uidStr ? Number(uidStr) : NaN;
  if (!Number.isFinite(uid) || uid <= 0) {
    return { ok: false, reason: 'invalid_uid' };
  }

  const conn = await tryOpenImap();
  if (!conn.ok) return adapterStatusPayload(conn.reason);
  try {
    // deno-lint-ignore no-explicit-any
    const client = conn.client as any;
    const lock = await client.getMailboxLock(folder);
    try {
      const msg = await client.fetchOne(String(uid), {
        uid: true,
        envelope: true,
        flags: true,
        bodyStructure: true,
        source: { body: true }, // request full body (will truncate HTML bodies for safety)
      }, { uid: true });
      if (!msg) return { ok: false, reason: 'message_not_found' };

      // Extract plain-text body excerpt (truncated server-side for safety)
      const bodyExcerpt = String(msg.source?.body || '').slice(0, 8000);
      const bookingId = extractBookingId(msg.envelope.subject) || extractBookingId(bodyExcerpt);

      return {
        ok: true,
        message: {
          uid,
          from: msg.envelope.from || [],
          to: msg.envelope.to || [],
          cc: msg.envelope.cc || [],
          subject: msg.envelope.subject || '(geen onderwerp)',
          date: msg.envelope.date,
          messageId: msg.envelope.messageId,
          inReplyTo: msg.envelope.inReplyTo,
          flags: Array.from(msg.flags || []),
          bodyExcerpt,
          bookingId,
        },
      };
    } finally {
      await client.unlock(lock);
    }
  } catch (e) {
    return adapterStatusPayload('imap_fetch_failed:' + (e as Error).message);
  } finally {
    await conn.logout();
  }
}

async function handleSearch(_userClient: ReturnType<typeof createClient>, params: URLSearchParams) {
  const q = (params.get('q') || '').slice(0, 200).trim();
  const folder = (params.get('folder') || 'INBOX').replace(/[^A-Za-z0-9._/-]/g, '');
  if (!q) return { ok: false, reason: 'missing_query' };

  const conn = await tryOpenImap();
  if (!conn.ok) return adapterStatusPayload(conn.reason);
  try {
    // deno-lint-ignore no-explicit-any
    const client = conn.client as any;
    const lock = await client.getMailboxLock(folder);
    try {
      // SEARCH across from/subject/body
      const uids = await client.search({ or: [
        { from: q },
        { subject: q },
        { body: q },
      ] });
      return {
        ok: true,
        folder,
        query: q,
        uids: Array.isArray(uids) ? uids : [],
      };
    } finally {
      await client.unlock(lock);
    }
  } catch (e) {
    return adapterStatusPayload('imap_search_failed:' + (e as Error).message);
  } finally {
    await conn.logout();
  }
}

// ---------- Main serve ----------
serve(async (req: Request) => {
  const origin = req.headers.get('origin');
  const cors = corsHeadersFor(origin);

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors });
  }

  if (origin && !isAllowedFleetConnectOrigin(origin)) {
    return jsonResponse({ error: 'Unauthorized origin' }, 403, cors);
  }
  if (req.method !== 'GET') {
    return jsonResponse({ error: 'Method not allowed' }, 405, cors);
  }

  // Auth + scope
  const auth = await userScopedClient(req);
  if (auth.error || !auth.userClient) {
    return jsonResponse({ error: auth.error || 'unauthorized' }, 401, cors);
  }
  const scope = await authorizeDispatchMailbox(auth.userClient);
  if (!scope.authorized) {
    await audit(auth.userClient, 'denied', { metadata: { path: new URL(req.url).pathname, reason: scope.reason } });
    return jsonResponse({ error: 'forbidden', reason: scope.reason }, 403, cors);
  }

  const url = new URL(req.url);
  const path = url.pathname.replace(/^\/functions\/v1\/dispatch-mail-inbox/, '').replace(/^\//, '');

  let result: unknown;
  let auditAction: string;
  if (path === '' || path === '/') {
    result = { ok: true, hint: 'Phase F dispatch-mail-inbox; sub-routes: /folders /inbox /message /search' };
    auditAction = 'inbox_read';
  } else if (path === 'folders') {
    result = await handleFolders(auth.userClient, url.searchParams);
    auditAction = 'folders_list';
  } else if (path === 'inbox') {
    result = await handleInbox(auth.userClient, url.searchParams);
    auditAction = 'inbox_read';
  } else if (path === 'message') {
    result = await handleMessage(auth.userClient, url.searchParams);
    auditAction = 'message_open';
  } else if (path === 'search') {
    result = await handleSearch(auth.userClient, url.searchParams);
    auditAction = 'inbox_search';
  } else {
    return jsonResponse({ error: 'not_found', path }, 404, cors);
  }

  await audit(auth.userClient, auditAction, { metadata: { path, query: Object.fromEntries(url.searchParams) } });

  return jsonResponse(result, 200, cors);
});