/**
 * FleetConnect Dispatch Mailbox — Flag toggle + Booking-ID link search
 *
 * Phase F Batch 1 corrections (per Lux 8d5d099 BLOCKER #2 + #3):
 *   - Single base route + explicit `action` field in body. No subpath required.
 *   - Block 3: ImapFlow `fetchOne()` is the right primitive; mailbox lock via
 *     `lock.release()` (NOT client.unlock(lock)). Same `withMailboxLock` pattern
 *     as dispatch-mail-inbox.
 *
 * ACTIONS supported:
 *   action='flag'  { folder, uid, flags: ['\\Seen', ...], op: 'add' | 'remove' }
 *   action='booking-link-search' { q }
 *
 * Non-secret: returns 'adapter_unavailable' when MAILBOX_IMAP_PASSWORD unset.
 * Booking-link search uses cached DB first so the UI can wire this without secrets.
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

const MAILBOX_HOST        = Deno.env.get('MAILBOX_PROVIDER_HOST') || 'imap.all-inkl.com';
const MAILBOX_IMAP_PORT   = Number(Deno.env.get('MAILBOX_PROVIDER_IMAP_PORT') || '993');
const MAILBOX_USER        = Deno.env.get('MAILBOX_USER') || 'dispatch@fleetconnect.be';
const MAILBOX_IMAP_PASS   = Deno.env.get('MAILBOX_IMAP_PASSWORD') || '';
const SUPABASE_URL        = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_ANON_KEY   = Deno.env.get('SUPABASE_ANON_KEY') || '';

function sanitizeFolder(name: string | null | undefined): string {
  const cleaned = String(name || 'INBOX').replace(/[^A-Za-z0-9._/-]/g, '');
  return cleaned || 'INBOX';
}

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

async function audit(userClient: ReturnType<typeof createClient>, action: string, metadata: Record<string, unknown> = {}) {
  try {
    await userClient.rpc('log_dispatch_mailbox_action', {
      p_action: action,
      p_metadata: metadata,
    });
  } catch (e) {
    console.warn('[dispatch-mail-flag] audit log failed (non-blocking):', (e as Error).message);
  }
}

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
      close: async () => { try { await client.logout(); } catch (_) { /* noop */ } },
    };
  } catch (e) {
    return { ok: false as const, reason: 'imap_connect_failed:' + (e as Error).message };
  }
}

// BLOCKER #3 FIX: use lock.release() (NOT client.unlock(lock))
// deno-lint-ignore no-explicit-any
async function withMailboxLock<T>(client: any, folder: string, fn: (lock: any) => Promise<T>): Promise<T> {
  const lock = await client.getMailboxLock(folder);
  try {
    return await fn(lock);
  } finally {
    try { await lock.release(); } catch (_) { /* noop */ }
  }
}

async function handleFlag(_userClient: ReturnType<typeof createClient>, payload: {
  folder?: string; uid: number; flags: string[]; op?: 'add' | 'remove';
}) {
  const folder = sanitizeFolder(payload.folder);
  const uid = Number(payload.uid);
  const op = payload.op === 'remove' ? 'remove' : 'add';
  if (!Number.isFinite(uid) || uid <= 0) {
    return { ok: false as const, action: 'flag' as const, reason: 'invalid_uid' };
  }
  const allowed = ['\\Seen', '\\Flagged', '\\Answered', '\\Deleted', '\\Draft'];
  const safeFlags = (Array.isArray(payload.flags) ? payload.flags : [])
    .filter((f): f is string => typeof f === 'string')
    .filter((f) => allowed.includes(f));
  if (!safeFlags.length) {
    return { ok: false as const, action: 'flag' as const, reason: 'no_valid_flags' };
  }

  const conn = await tryOpenImap();
  if (!conn.ok) return unavailable(conn.reason);
  try {
    // deno-lint-ignore no-explicit-any
    const client = conn.client as any;
    return await withMailboxLock(client, folder, async () => {
      if (op === 'add') {
        await client.messageFlagsAdd(String(uid), safeFlags, { uid: true });
      } else {
        await client.messageFlagsRemove(String(uid), safeFlags, { uid: true });
      }
      return { ok: true as const, action: 'flag' as const, op, flags: safeFlags, uid, folder };
    });
  } catch (e) {
    return { ok: false as const, action: 'flag' as const, reason: 'imap_flag_failed:' + (e as Error).message };
  } finally {
    await conn.close();
  }
}

async function handleBookingLinkSearch(userClient: ReturnType<typeof createClient>, payload: { q?: string }) {
  const cleaned = String(payload.q || '').trim().toUpperCase();
  if (!cleaned) {
    return { ok: false as const, action: 'booking-link-search' as const, reason: 'missing_query' };
  }
  try {
    const { data, error } = await userClient
      .from('dispatch_mailbox_messages')
      .select('id, mailbox, folder, uid, subject, from_addr, from_name, received_at, seen, flagged, booking_id_referenced')
      .eq('booking_id_referenced', cleaned)
      .order('received_at', { ascending: false })
      .limit(50);
    if (error) {
      return { ok: false as const, action: 'booking-link-search' as const, reason: 'db_query_failed:' + error.message };
    }
    return {
      ok: true as const,
      action: 'booking-link-search' as const,
      bookingId: cleaned,
      count: data?.length || 0,
      messages: data || [],
    };
  } catch (e) {
    return { ok: false as const, action: 'booking-link-search' as const, reason: 'search_failed:' + (e as Error).message };
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
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed (use POST with action field)' }, 405, cors);
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

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch (_) {
    return jsonResponse({ ok: false, error: 'invalid_json' }, 400, cors);
  }

  const action = String(body.action || '').trim();
  if (!action) {
    return jsonResponse({
      ok: false,
      error: 'missing_action',
      valid_actions: ['flag', 'booking-link-search'],
    }, 400, cors);
  }

  let result: { ok: boolean; [k: string]: unknown };
  switch (action) {
    case 'flag':
      result = await handleFlag(auth.userClient, body as { folder?: string; uid: number; flags: string[]; op?: 'add' | 'remove' });
      break;
    case 'booking-link-search':
      result = await handleBookingLinkSearch(auth.userClient, body as { q?: string });
      break;
    default:
      return jsonResponse({
        ok: false,
        error: 'unknown_action',
        action,
        valid_actions: ['flag', 'booking-link-search'],
      }, 400, cors);
  }

  const auditAction = action === 'flag'
    ? (Array.isArray(body.flags) && body.flags.includes('\\Seen') ? 'flag_seen' :
       Array.isArray(body.flags) && body.flags.includes('\\Flagged') ? 'flag_flagged' : 'flag_other')
    : 'booking_link_open';
  await audit(auth.userClient, auditAction, { metadata: { action, request: body } });

  return jsonResponse(result, 200, cors);
});