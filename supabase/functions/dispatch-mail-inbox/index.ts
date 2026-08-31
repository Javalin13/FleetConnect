/**
 * FleetConnect Dispatch Mailbox — Inbox / Folders / Detail / Search
 *
 * Phase F Batch 1 corrections (per Lux 8d5d099 BLOCKER #2 + #3):
 *
 *   BLOCKER #2 FIX: single base route + explicit `action` field in body.
 *     The browser calls `supabase.functions.invoke('dispatch-mail-inbox', { body: { action: ... } })`
 *     and the function dispatches by `action` value. No subpath required. Base
 *     route never returns `ok: true` for a no-op — base without action returns
 *     `{ ok: false, error: 'missing_action' }`.
 *
 *   BLOCKER #3 FIX: ImapFlow `fetch()` returns an async iterable, not an array.
 *     Use `for await ... of` to collect results. Mailbox lock release uses
 *     `lock.release()`, NOT `client.unlock(lock)`. Same patterns in /message
 *     and /search where applicable.
 *
 *   Non-secret behavior: when MAILBOX_IMAP_PASSWORD is unset, the adapter returns
 *     `{ ok: false, status: 'adapter_unavailable', reason: 'mailbox_credentials_unconfigured' }`
 *     so the UI can render the friendly unavailable panel.
 *
 * ACTIONS supported:
 *   action='folders'                            → list IMAP folders
 *   action='inbox'    { folder, limit, offset } → list cached envelope
 *   action='message'  { folder, uid }           → fetch single message body excerpt
 *   action='search'   { q, folder }             → IMAP SEARCH by from/subject/body
 *
 * SECURITY (unchanged from Batch 1):
 *   - CORS allowlist mirrors other FC edge functions
 *   - Bearer JWT + authorize_dispatch_mailbox() server-derived scope
 *   - All actions audited via log_dispatch_mailbox_action()
 *   - Secrets only in env vars, never logged
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

function corsHeadersFor(origin: string | null): Record<string, string> {
  const isAllowed = isAllowedFleetConnectOrigin(origin);
  return {
    'Access-Control-Allow-Origin': isAllowed && origin ? origin : ALLOWED_ORIGINS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

function jsonResponse(body: unknown, status: number, headers: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json' },
  });
}

function unavailable(reason: string) {
  return {
    ok: false as const,
    status: 'adapter_unavailable',
    reason,
    detail: 'mailbox_adapter_unavailable_contact_founder_for_F_M1',
  };
}

// ---------- Config ----------
const MAILBOX_HOST        = Deno.env.get('MAILBOX_PROVIDER_HOST') || 'imap.kasserver.com';
const MAILBOX_IMAP_PORT   = Number(Deno.env.get('MAILBOX_PROVIDER_IMAP_PORT') || '993');
const MAILBOX_USER        = Deno.env.get('MAILBOX_USER') || 'dispatch@fleetconnect.be';
const MAILBOX_IMAP_PASS   = Deno.env.get('MAILBOX_IMAP_PASSWORD') || '';

const SUPABASE_URL        = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_ANON_KEY   = Deno.env.get('SUPABASE_ANON_KEY') || '';

// ---------- User-scoped client ----------
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

// ---------- Authorize ----------
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

// ---------- Audit ----------
async function audit(userClient: ReturnType<typeof createClient>, action: string, metadata: Record<string, unknown> = {}) {
  try {
    await userClient.rpc('log_dispatch_mailbox_action', {
      p_action: action,
      p_metadata: metadata,
    });
  } catch (e) {
    console.warn('[dispatch-mail-inbox] audit log failed (non-blocking):', (e as Error).message);
  }
}

// ---------- Folder-name sanitization ----------
function sanitizeFolder(name: string | null | undefined): string {
  const cleaned = String(name || 'INBOX').replace(/[^A-Za-z0-9._/-]/g, '');
  return cleaned || 'INBOX';
}

// ---------- ImapFlow adapter abstraction (BLOCKER #3 FIX) ----------
//
// Test seam: this module can be replaced by a mock in `tests/` for non-secret
// unit tests. The contract is:
//   openImap() -> { ok: true, client, withLock(folder, fn) } | { ok: false, reason }
//   fetchMessages(client, lock, range, opts) -> async iterable of message objects
//
// ImapFlow reality:
//   - client.getMailboxLock(folder) returns a Lock object (has release() method)
//   - client.fetch(range, opts) returns an AsyncIterable<Message>
//   - lock.release() releases the lock (NOT client.unlock(lock))

async function tryOpenImap() {
  if (!MAILBOX_IMAP_PASS) {
    return { ok: false as const, reason: 'mailbox_credentials_unconfigured' };
  }
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return { ok: false as const, reason: 'supabase_service_configuration_missing' };
  }
  try {
    const { ImapFlow } = await import('npm:imapflow@1.0.171');
    const client = new ImapFlow({
      host: MAILBOX_HOST,
      port: MAILBOX_IMAP_PORT,
      secure: true,
      auth: { user: MAILBOX_USER, pass: MAILBOX_IMAP_PASS },
      logger: false,
    });
    await client.connect();
    return {
      ok: true as const,
      client,
      close: async () => { try { await client.logout(); } catch (_) { /* noop */ } },
    };
  } catch (e) {
    return { ok: false as const, reason: 'imap_connect_failed:' + (e as Error).message };
  }
}

// Collect AsyncIterable into array (BLOCKER #3 FIX)
async function collectIterable<T>(iter: AsyncIterable<T>): Promise<T[]> {
  const out: T[] = [];
  for await (const item of iter) {
    out.push(item);
  }
  return out;
}

// Run callback with mailbox lock; release on exit (BLOCKER #3 FIX)
// deno-lint-ignore no-explicit-any
async function withMailboxLock<T>(client: any, folder: string, fn: (lock: any) => Promise<T>): Promise<T> {
  const lock = await client.getMailboxLock(folder);
  try {
    return await fn(lock);
  } finally {
    try { await lock.release(); } catch (_) { /* noop */ }
  }
}

// ---------- Action handlers ----------

async function handleFolders(_userClient: ReturnType<typeof createClient>) {
  const conn = await tryOpenImap();
  if (!conn.ok) return unavailable(conn.reason);
  try {
    // deno-lint-ignore no-explicit-any
    const client = conn.client as any;
    const folders = await client.list();
    return {
      ok: true as const,
      action: 'folders' as const,
      folders: folders.map((f: { path: string; name: string; flags: Set<string>; total: number; unseen: number }) => ({
        path: f.path,
        name: f.name,
        flags: Array.from(f.flags || []),
        total: f.total,
        unseen: f.unseen,
      })),
    };
  } catch (e) {
    return unavailable('imap_list_failed:' + (e as Error).message);
  } finally {
    await conn.close();
  }
}

async function handleInbox(_userClient: ReturnType<typeof createClient>, payload: { folder?: string; limit?: number; offset?: number }) {
  const folder = sanitizeFolder(payload.folder);
  const limit  = Math.min(Math.max(Number(payload.limit ?? 50), 1), 200);
  const offset = Math.max(Number(payload.offset ?? 0), 0);

  const conn = await tryOpenImap();
  if (!conn.ok) return unavailable(conn.reason);
  try {
    // deno-lint-ignore no-explicit-any
    const client = conn.client as any;
    return await withMailboxLock(client, folder, async () => {
      // BLOCKER #3 FIX: fetch() is an async iterable; collect with for-await
      const range = `${offset + 1}:${offset + limit}`;
      const iterable = client.fetch(range, {
        uid: true,
        envelope: true,
        flags: true,
        bodyStructure: false,
      });
      const messages = await collectIterable(iterable);
      return {
        ok: true as const,
        action: 'inbox' as const,
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
    });
  } catch (e) {
    return unavailable('imap_inbox_failed:' + (e as Error).message);
  } finally {
    await conn.close();
  }
}

async function handleMessage(_userClient: ReturnType<typeof createClient>, payload: { folder?: string; uid: number }) {
  const folder = sanitizeFolder(payload.folder);
  const uid = Number(payload.uid);
  if (!Number.isFinite(uid) || uid <= 0) {
    return { ok: false as const, action: 'message' as const, reason: 'invalid_uid' };
  }

  const conn = await tryOpenImap();
  if (!conn.ok) return unavailable(conn.reason);
  try {
    // deno-lint-ignore no-explicit-any
    const client = conn.client as any;
    return await withMailboxLock(client, folder, async () => {
      // fetchOne for single message; returns single Message | null
      const msg = await client.fetchOne(String(uid), {
        uid: true,
        envelope: true,
        flags: true,
        bodyStructure: true,
        source: { body: true },
      });
      if (!msg) {
        return { ok: false as const, action: 'message' as const, reason: 'message_not_found' };
      }
      const bodyExcerpt = String(msg.source?.body || '').slice(0, 8000);
      const bookingId = extractBookingId(msg.envelope.subject) || extractBookingId(bodyExcerpt);
      return {
        ok: true as const,
        action: 'message' as const,
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
    });
  } catch (e) {
    return unavailable('imap_fetch_failed:' + (e as Error).message);
  } finally {
    await conn.close();
  }
}

async function handleSearch(_userClient: ReturnType<typeof createClient>, payload: { q?: string; folder?: string }) {
  const q = String(payload.q || '').slice(0, 200).trim();
  const folder = sanitizeFolder(payload.folder);
  if (!q) {
    return { ok: false as const, action: 'search' as const, reason: 'missing_query' };
  }

  const conn = await tryOpenImap();
  if (!conn.ok) return unavailable(conn.reason);
  try {
    // deno-lint-ignore no-explicit-any
    const client = conn.client as any;
    return await withMailboxLock(client, folder, async () => {
      const uids = await client.search({ or: [
        { from: q },
        { subject: q },
        { body: q },
      ] });
      return {
        ok: true as const,
        action: 'search' as const,
        folder,
        query: q,
        uids: Array.isArray(uids) ? uids : [],
      };
    });
  } catch (e) {
    return unavailable('imap_search_failed:' + (e as Error).message);
  } finally {
    await conn.close();
  }
}

// ---------- Booking-ID extraction ----------
function extractBookingId(text: string | null | undefined): string | null {
  if (!text) return null;
  const m = text.match(/\b(?:FC[-_]?\d{4}[-_]?[A-Z0-9]{4,}|\bB[-_]?\d{4,6})\b/i);
  return m ? m[0].toUpperCase().replace(/[-_]/g, '-') : null;
}

// ---------- Main serve (single base route + action dispatch) ----------
serve(async (req: Request) => {
  const origin = req.headers.get('origin');
  const cors = corsHeadersFor(origin);

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors });
  }

  if (origin && !isAllowedFleetConnectOrigin(origin)) {
    return jsonResponse({ error: 'Unauthorized origin' }, 403, cors);
  }
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed (use POST with action field)' }, 405, cors);
  }

  // Auth + scope
  const auth = await userScopedClient(req);
  if (auth.error || !auth.userClient) {
    return jsonResponse({ error: auth.error || 'unauthorized' }, 401, cors);
  }
  const scope = await authorizeDispatchMailbox(auth.userClient);
  if (!scope.authorized) {
    await audit(auth.userClient, 'denied', { metadata: { reason: scope.reason } });
    return jsonResponse({ error: 'forbidden', reason: scope.reason }, 403, cors);
  }

  // Parse body
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch (_) {
    return jsonResponse({ ok: false, error: 'invalid_json' }, 400, cors);
  }

  const action = String(body.action || '').trim();

  // BLOCKER #2 FIX: no `ok: true` hint on missing action; explicit error instead.
  if (!action) {
    return jsonResponse({
      ok: false,
      error: 'missing_action',
      valid_actions: ['folders', 'inbox', 'message', 'search'],
    }, 400, cors);
  }

  let result: { ok: boolean; [k: string]: unknown };
  switch (action) {
    case 'folders':
      result = await handleFolders(auth.userClient);
      break;
    case 'inbox':
      result = await handleInbox(auth.userClient, body as { folder?: string; limit?: number; offset?: number });
      break;
    case 'message':
      result = await handleMessage(auth.userClient, body as { folder?: string; uid: number });
      break;
    case 'search':
      result = await handleSearch(auth.userClient, body as { q?: string; folder?: string });
      break;
    default:
      return jsonResponse({
        ok: false,
        error: 'unknown_action',
        action,
        valid_actions: ['folders', 'inbox', 'message', 'search'],
      }, 400, cors);
  }

  // Audit per-action
  const auditAction = `inbox_${action}`;
  await audit(auth.userClient, auditAction, { metadata: { action, request: body } });

  return jsonResponse(result, 200, cors);
});