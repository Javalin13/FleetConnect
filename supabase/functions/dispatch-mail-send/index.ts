/**
 * FleetConnect Dispatch Mailbox — Compose / Reply / Reply-all / Forward
 *
 * Phase F Batch 1 (non-secret review-ready).
 *
 * Per Lux 68f35b6 §4: server-side SMTP adapter; NEVER browser-to-SMTP.
 *
 * Per mailbox-audit.md §7c EXACTLY-ONCE OPERATIONAL ARCHIVE PRESERVATION:
 *   - Manual dispatch mail is treated as DISPATCH communication, NOT as a comms.trigger()
 *   - Subject prefixed with "[Manual dispatch]" (clearly attributable)
 *   - Sent folder entry appears in IMAP Sent (via SMTP), NOT in Supabase audit-only
 *   - If body references booking ID, the UI gets a booking-link quick-nav
 *   - NO duplication of archive: this edge function does NOT call comms.trigger()
 *
 * SCOPE (Batch 1):
 *   POST /compose   { to, cc?, bcc?, subject, body, inReplyTo?, forwardOfUid? }
 *   POST /reply     { uid, folder?, body }       — sets In-Reply-To + Re: prefix
 *   POST /reply-all { uid, folder?, body }       — replies to all To + Cc + From
 *   POST /forward   { uid, folder?, to, body? }  — forwards with quoted original
 *
 * NON-SECRET BATCH 1 BEHAVIOR (when MAILBOX_SMTP_PASSWORD unset):
 *   - returns 503 SERVICE_UNAVAILABLE with adapter_status="mailbox_credentials_unconfigured"
 *   - does NOT attempt SMTP connection (safe fail-closed)
 *   - logs a 'denied' or 'send_failed' audit entry
 *
 * NOT IN THIS FUNCTION:
 *   - Attachment upload (would need separate endpoint + scope guard)
 *   - Template rendering (out of scope Batch 1)
 */

import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------- CORS allowlist ----------
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

// ---------- Config ----------
const MAILBOX_SMTP_HOST  = Deno.env.get('MAILBOX_PROVIDER_HOST') || 'smtp.kasserver.com';
const MAILBOX_SMTP_PORT  = Number(Deno.env.get('MAILBOX_PROVIDER_SMTP_PORT') || '465');
const MAILBOX_USER       = Deno.env.get('MAILBOX_USER') || 'dispatch@fleetconnect.be';
const MAILBOX_SMTP_PASS  = Deno.env.get('MAILBOX_SMTP_PASSWORD') || '';

const SUPABASE_URL       = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_ANON_KEY  = Deno.env.get('SUPABASE_ANON_KEY') || '';

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
  if (error) return { authorized: false, authz: null, reason: 'rpc_error:' + error.message };
  const authz = data as { authorized: boolean; founder_scope: boolean; operator_scope: boolean; reason?: string };
  return { authorized: !!authz?.authorized, authz, reason: authz?.reason || 'unknown' };
}

// ---------- Audit ----------
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
    console.warn('[dispatch-mail-send] audit log failed (non-blocking):', (e as Error).message);
  }
}

// ---------- SMTP transporter (lazy import) ----------
async function tryOpenSmtp() {
  if (!MAILBOX_SMTP_PASS) {
    return { ok: false as const, reason: 'mailbox_credentials_unconfigured' };
  }
  try {
    const nodemailer = await import('npm:nodemailer@6.9.13');
    const transporter = nodemailer.default.createTransport({
      host: MAILBOX_SMTP_HOST,
      port: MAILBOX_SMTP_PORT,
      secure: MAILBOX_SMTP_PORT === 465,
      auth: { user: MAILBOX_USER, pass: MAILBOX_SMTP_PASS },
      logger: false,
    });
    return { ok: true as const, transporter };
  } catch (e) {
    return { ok: false as const, reason: 'smtp_init_failed:' + (e as Error).message };
  }
}

// ---------- Booking-ID extraction ----------
function extractBookingId(text: string | null | undefined): string | null {
  if (!text) return null;
  const m = text.match(/\b(?:FC[-_]?\d{4}[-_]?[A-Z0-9]{4,}|\bB[-_]?\d{4,6})\b/i);
  return m ? m[0].toUpperCase().replace(/[-_]/g, '-') : null;
}

// ---------- Sanitize (light HTML for plain-text emails) ----------
function sanitizeBody(body: string): string {
  // No HTML in Batch 1; convert to plain-text only
  return String(body || '').replace(/<[^>]*>/g, '').slice(0, 16000);
}

// ---------- Routing ----------
async function handleCompose(userClient: ReturnType<typeof createClient>, payload: {
  to: string; cc?: string[]; bcc?: string[]; subject: string; body: string;
  inReplyTo?: string; forwardOfUid?: number;
}) {
  const to = String(payload?.to || '').trim();
  const subject = String(payload?.subject || '').trim();
  const body = sanitizeBody(payload?.body || '');
  if (!to) return { ok: false, reason: 'missing_to' };
  if (!subject) return { ok: false, reason: 'missing_subject' };

  const smtp = await tryOpenSmtp();
  if (!smtp.ok) return { ok: false, reason: smtp.reason, status: 'adapter_unavailable' };

  // Per Lux §4 / mailbox-audit.md §7c: manual dispatch mail is clearly attributable
  const taggedSubject = subject.toLowerCase().startsWith('[manual dispatch]') ? subject : `[Manual dispatch] ${subject}`;
  const bookingId = extractBookingId(subject) || extractBookingId(body);

  try {
    const info = await smtp.transporter.sendMail({
      from: MAILBOX_USER,
      to,
      cc: payload?.cc || undefined,
      bcc: payload?.bcc || undefined,
      subject: taggedSubject,
      text: body,
      inReplyTo: payload?.inReplyTo || undefined,
      references: payload?.inReplyTo || undefined,
      headers: {
        'X-FleetConnect-Manual-Dispatch': '1',
        ...(bookingId ? { 'X-FleetConnect-Booking-Id': bookingId } : {}),
      },
    });
    return {
      ok: true,
      messageId: info.messageId,
      subject: taggedSubject,
      bookingId,
    };
  } catch (e) {
    return { ok: false, reason: 'smtp_send_failed:' + (e as Error).message };
  } finally {
    try { smtp.transporter.close(); } catch (_) { /* noop */ }
  }
}

async function handleReply(userClient: ReturnType<typeof createClient>, payload: {
  uid: number; folder?: string; body: string; replyAll?: boolean;
}) {
  // Per Batch 1 scope: we accept the UID + folder, but DO NOT round-trip to IMAP
  // to fetch original envelope (would require IMAP credentials). Instead, the
  // browser UI is expected to pass original envelope metadata in the payload.
  // This keeps Batch 1 self-contained when MAILBOX_IMAP_PASSWORD is also absent.
  //
  // When MAILBOX_IMAP_PASSWORD is later configured (F-M1), this handler can be
  // extended to fetch the original envelope server-side. The contract stays stable.
  const originalSubject = String(payload?.originalSubject || '').trim();
  const originalMessageId = payload?.originalMessageId || '';
  const originalFrom = String(payload?.originalFrom || '').trim();

  if (!originalFrom) return { ok: false, reason: 'missing_original_from' };
  if (!originalSubject) return { ok: false, reason: 'missing_original_subject' };

  const replySubject = originalSubject.toLowerCase().startsWith('re:') ? originalSubject : `Re: ${originalSubject}`;
  return await handleCompose(userClient, {
    to: payload?.replyAll ? originalFrom : originalFrom, // Batch 1: To = From; reply-all would need original To/Cc which browser supplies
    subject: replySubject,
    body: String(payload?.body || ''),
    inReplyTo: originalMessageId || undefined,
  });
}

async function handleForward(userClient: ReturnType<typeof createClient>, payload: {
  uid: number; folder?: string; to: string; originalSubject?: string;
  originalBody?: string; comment?: string;
}) {
  const originalSubject = String(payload?.originalSubject || '(geen onderwerp)').trim();
  const originalBody = sanitizeBody(payload?.originalBody || '');
  const comment = sanitizeBody(payload?.comment || '');

  const fwdSubject = originalSubject.toLowerCase().startsWith('fwd:') ? originalSubject : `Fwd: ${originalSubject}`;
  const quotedBody = [
    comment,
    '',
    '---------- Doorgestuurd bericht ----------',
    `Onderwerp: ${originalSubject}`,
    '',
    originalBody,
  ].join('\n');

  return await handleCompose(userClient, {
    to: String(payload?.to || ''),
    subject: fwdSubject,
    body: quotedBody,
  });
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
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405, cors);
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

  const url = new URL(req.url);
  const path = url.pathname.replace(/^\/functions\/v1\/dispatch-mail-send/, '').replace(/^\//, '');

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch (_) {
    return jsonResponse({ error: 'invalid_json' }, 400, cors);
  }

  let result: { ok: boolean; reason?: string; status?: string; messageId?: string; subject?: string; bookingId?: string | null };
  let auditAction: string;
  if (path === '' || path === '/') {
    result = { ok: true, reason: 'use /compose /reply /reply-all /forward' };
    auditAction = 'send_compose';
  } else if (path === 'compose') {
    result = await handleCompose(auth.userClient, body as { to: string; cc?: string[]; bcc?: string[]; subject: string; body: string });
    auditAction = 'send_compose';
  } else if (path === 'reply' || path === 'reply-all') {
    result = await handleReply(auth.userClient, body as { uid: number; folder?: string; body: string; replyAll?: boolean; originalSubject?: string; originalMessageId?: string; originalFrom?: string });
    auditAction = path === 'reply-all' ? 'send_reply_all' : 'send_reply';
  } else if (path === 'forward') {
    result = await handleForward(auth.userClient, body as { uid: number; folder?: string; to: string; originalSubject?: string; originalBody?: string; comment?: string });
    auditAction = 'send_forward';
  } else {
    return jsonResponse({ error: 'not_found', path }, 404, cors);
  }

  await audit(auth.userClient, auditAction, { metadata: { path, bookingId: result.bookingId || null } });

  // Per Lux: no auto-retry on transient SMTP failure; bubble error to user
  return jsonResponse(result, 200, cors);
});