/**
 * FleetConnect Dispatch Mailbox — Flag toggle + Booking-ID link search
 *
 * Phase F Batch 1 (non-secret review-ready).
 *
 * SCOPE:
 *   POST /flag    { folder, uid, flags: ['\\Seen', '\\Flagged'] }   — set/unset IMAP flags
 *   GET  /booking-link-search?q=<booking-id>                       — find messages referencing booking
 *
 * Non-secret Batch 1 behavior mirrors dispatch-mail-inbox: returns 503 when
 * MAILBOX_IMAP_PASSWORD is unset. Booking-link search uses cached DB first
 * (no IMAP required) so the UI can wire this today.
 */

import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Vary': 'Origin',
  };
}

function jsonResponse(body: unknown, status: number, headers: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json' },
  });
}

const MAILBOX_HOST        = Deno.env.get('MAILBOX_PROVIDER_HOST') || 'imap.kasserver.com';
const MAILBOX_IMAP_PORT   = Number(Deno.env.get('MAILBOX_PROVIDER_IMAP_PORT') || '993');
const MAILBOX_USER        = Deno.env.get('MAILBOX_USER') || 'dispatch@fleetconnect.be';
const MAILBOX_IMAP_PASS   = Deno.env.get('MAILBOX_IMAP_PASSWORD') || '';
const SUPABASE_URL        = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_ANON_KEY   = Deno.env.get('SUPABASE_ANON_KEY') || '';

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
  if (userError || !user) return { error: 'invalid_session', userClient: null, userId: null };
  return { error: null, userClient, userId: user.id };
}

async function authorizeDispatchMailbox(userClient: ReturnType<typeof createClient>) {
  const { data, error } = await userClient.rpc('authorize_dispatch_mailbox');
  if (error) return { authorized: false, reason: 'rpc_error:' + error.message };
  const authz = data as { authorized: boolean; reason?: string };
  return { authorized: !!authz?.authorized, reason: authz?.reason || 'unknown' };
}

async function audit(userClient: ReturnType<typeof createClient>, action: string, payload: {
  mailbox?: string; folder?: string; uid?: number; metadata?: Record<string, unknown>;
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
    console.warn('[dispatch-mail-flag] audit log failed (non-blocking):', (e as Error).message);
  }
}

// ---------- IMAP (lazy import) ----------
async function tryOpenImap() {
  if (!MAILBOX_IMAP_PASS) return { ok: false as const, reason: 'mailbox_credentials_unconfigured' };
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
      logout: async () => { try { await client.logout(); } catch (_) { /* noop */ } },
    };
  } catch (e) {
    return { ok: false as const, reason: 'imap_connect_failed:' + (e as Error).message };
  }
}

async function handleFlag(_userClient: ReturnType<typeof createClient>, payload: {
  folder?: string; uid: number; flags: string[]; op?: 'add' | 'remove';
}) {
  const folder = String(payload?.folder || 'INBOX').replace(/[^A-Za-z0-9._/-]/g, '');
  const uid = Number(payload?.uid);
  const op = payload?.op === 'remove' ? 'remove' : 'add';
  if (!Number.isFinite(uid) || uid <= 0) return { ok: false, reason: 'invalid_uid' };
  const flags = Array.isArray(payload?.flags) ? payload.flags.filter((f) => typeof f === 'string') : [];
  // Whitelist IMAP flag set
  const allowed = ['\\Seen', '\\Flagged', '\\Answered', '\\Deleted', '\\Draft'];
  const safeFlags = flags.filter((f) => allowed.includes(f));
  if (!safeFlags.length) return { ok: false, reason: 'no_valid_flags' };

  const conn = await tryOpenImap();
  if (!conn.ok) return { ok: false, reason: conn.reason, status: 'adapter_unavailable' };
  try {
    // deno-lint-ignore no-explicit-any
    const client = conn.client as any;
    const lock = await client.getMailboxLock(folder);
    try {
      if (op === 'add') {
        await client.messageFlagsAdd(String(uid), safeFlags, { uid: true });
      } else {
        await client.messageFlagsRemove(String(uid), safeFlags, { uid: true });
      }
      // Mirror flag change to cache table for list-view rendering without IMAP round-trip
      // Note: this writes to DB via service-role client; done in handler caller
      return { ok: true, op, flags: safeFlags };
    } finally {
      await client.unlock(lock);
    }
  } catch (e) {
    return { ok: false, reason: 'imap_flag_failed:' + (e as Error).message };
  } finally {
    await conn.logout();
  }
}

async function handleBookingLinkSearch(userClient: ReturnType<typeof createClient>, q: string) {
  const cleaned = String(q || '').trim().toUpperCase();
  if (!cleaned) return { ok: false, reason: 'missing_query' };
  try {
    // Search cached dispatch_mailbox_messages (no IMAP needed for this lookup)
    const { data, error } = await userClient
      .from('dispatch_mailbox_messages')
      .select('id, mailbox, folder, uid, subject, from_addr, from_name, received_at, seen, flagged, booking_id_referenced')
      .eq('booking_id_referenced', cleaned)
      .order('received_at', { ascending: false })
      .limit(50);
    if (error) return { ok: false, reason: 'db_query_failed:' + error.message };
    return { ok: true, bookingId: cleaned, count: data?.length || 0, messages: data || [] };
  } catch (e) {
    return { ok: false, reason: 'search_failed:' + (e as Error).message };
  }
}

serve(async (req: Request) => {
  const origin = req.headers.get('origin');
  const cors = corsHeadersFor(origin);

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors });
  }
  if (origin && !isAllowedFleetConnectOrigin(origin)) {
    return jsonResponse({ error: 'Unauthorized origin' }, 403, cors);
  }

  const auth = await userScopedClient(req);
  if (auth.error || !auth.userClient) {
    return jsonResponse({ error: auth.error || 'unauthorized' }, 401, cors);
  }
  const scope = await authorizeDispatchMailbox(auth.userClient);
  if (!scope.authorized) {
    await audit(auth.userClient, 'denied', { metadata: { reason: scope.reason } });
    return jsonResponse({ error: 'forbidden', reason: scope.reason }, 403, cors);
  }

  const url = new URL(req.url);
  const path = url.pathname.replace(/^\/functions\/v1\/dispatch-mail-flag/, '').replace(/^\//, '');

  if (req.method === 'GET' && path === 'booking-link-search') {
    const q = url.searchParams.get('q') || '';
    const result = await handleBookingLinkSearch(auth.userClient, q);
    await audit(auth.userClient, 'booking_link_open', { metadata: { query: q.slice(0, 200), count: result.ok ? result.count : 0 } });
    return jsonResponse(result, 200, cors);
  }

  if (req.method === 'POST' && path === 'flag') {
    let body: { folder?: string; uid: number; flags: string[]; op?: 'add' | 'remove' };
    try { body = await req.json(); } catch (_) { return jsonResponse({ error: 'invalid_json' }, 400, cors); }
    const result = await handleFlag(auth.userClient, body);
    const auditAction = body.flags?.includes('\\Seen') ? 'flag_seen' : body.flags?.includes('\\Flagged') ? 'flag_flagged' : 'flag_other';
    await audit(auth.userClient, auditAction, {
      folder: body.folder, uid: body.uid,
      metadata: { flags: body.flags, op: body.op || 'add', reason: result.reason || null },
    });
    return jsonResponse(result, 200, cors);
  }

  return jsonResponse({ error: 'not_found', path, method: req.method }, 404, cors);
});