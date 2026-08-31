/**
 * FleetConnect Dispatch Mailbox — Compose / Reply / Reply-all / Forward
 *
 * Phase F Batch 1 corrections (per Lux 8d5d099 BLOCKER #2):
 *   - Single base route + explicit `action` field in body. No subpath required.
 *   - Base route without action returns { ok: false, error: 'missing_action' }.
 *   - Each action handler returns its real result (no ok:true hint that UI could
 *     mistake for a successful send).
 *
 * ACTIONS supported:
 *   action='compose' { to, cc?, bcc?, subject, body, inReplyTo? }
 *   action='reply'   { uid, originalSubject, originalMessageId?, originalFrom, body }
 *   action='forward' { uid, originalSubject, originalBody?, to, comment? }
 *
 * Mailbox-audit.md §7c EXACTLY-ONCE ARCHIVE PRESERVATION:
 *   - Manual dispatch mail is treated as DISPATCH communication, NOT comms.trigger()
 *   - Subject prefixed with [Manual dispatch] (clearly attributable)
 *   - Sent folder entry appears in IMAP Sent (via SMTP), NOT in Supabase audit-only
 *   - If body references booking ID, the UI gets a booking-link quick-nav
 *   - NO duplication of archive: this edge function does NOT call comms.trigger()
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

const MAILBOX_SMTP_HOST  = Deno.env.get('MAILBOX_PROVIDER_HOST') || 'w021ae07.kasserver.com';
const MAILBOX_SMTP_PORT  = Number(Deno.env.get('MAILBOX_PROVIDER_SMTP_PORT') || '465');
const MAILBOX_USER       = Deno.env.get('MAILBOX_USER') || 'dispatch@fleetconnect.be';
const MAILBOX_SMTP_PASS  = Deno.env.get('MAILBOX_SMTP_PASSWORD') || '';

const SUPABASE_URL       = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_ANON_KEY  = Deno.env.get('SUPABASE_ANON_KEY') || '';

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

async function authorizeDispatchMailbox(userClient: ReturnType<typeof createClient>) {
  const { data, error } = await userClient.rpc('authorize_dispatch_mailbox');
  if (error) return { authorized: false, authz: null, reason: 'rpc_error:' + error.message };
  const authz = data as { authorized: boolean; founder_scope: boolean; operator_scope: boolean; reason?: string };
  return { authorized: !!authz?.authorized, authz, reason: authz?.reason || 'unknown' };
}

async function audit(userClient: ReturnType<typeof createClient>, action: string, metadata: Record<string, unknown> = {}) {
  try {
    await userClient.rpc('log_dispatch_mailbox_action', {
      p_action: action,
      p_metadata: metadata,
    });
  } catch (e) {
    console.warn('[dispatch-mail-send] audit log failed (non-blocking):', (e as Error).message);
  }
}

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

function extractBookingId(text: string | null | undefined): string | null {
  if (!text) return null;
  const m = text.match(/\b(?:FC[-_]?\d{4}[-_]?[A-Z0-9]{4,}|\bB[-_]?\d{4,6})\b/i);
  return m ? m[0].toUpperCase().replace(/[-_]/g, '-') : null;
}

function sanitizeBody(body: string): string {
  return String(body || '').replace(/<[^>]*>/g, '').slice(0, 16000);
}

async function handleCompose(_userClient: ReturnType<typeof createClient>, payload: {
  to: string; cc?: string[]; bcc?: string[]; subject: string; body: string; inReplyTo?: string;
}) {
  const to = String(payload.to || '').trim();
  const subject = String(payload.subject || '').trim();
  const body = sanitizeBody(payload.body);
  if (!to) return { ok: false as const, action: 'compose' as const, reason: 'missing_to' };
  if (!subject) return { ok: false as const, action: 'compose' as const, reason: 'missing_subject' };

  const smtp = await tryOpenSmtp();
  if (!smtp.ok) return unavailable(smtp.reason);

  const taggedSubject = subject.toLowerCase().startsWith('[manual dispatch]') ? subject : `[Manual dispatch] ${subject}`;
  const bookingId = extractBookingId(subject) || extractBookingId(body);

  try {
    const info = await smtp.transporter.sendMail({
      from: MAILBOX_USER,
      to,
      cc: payload.cc || undefined,
      bcc: payload.bcc || undefined,
      subject: taggedSubject,
      text: body,
      inReplyTo: payload.inReplyTo || undefined,
      references: payload.inReplyTo || undefined,
      headers: {
        'X-FleetConnect-Manual-Dispatch': '1',
        ...(bookingId ? { 'X-FleetConnect-Booking-Id': bookingId } : {}),
      },
    });
    return {
      ok: true as const,
      action: 'compose' as const,
      sent: true,
      messageId: info.messageId,
      subject: taggedSubject,
      bookingId,
    };
  } catch (e) {
    return { ok: false as const, action: 'compose' as const, reason: 'smtp_send_failed:' + (e as Error).message };
  } finally {
    try { smtp.transporter.close(); } catch (_) { /* noop */ }
  }
}

async function handleReply(_userClient: ReturnType<typeof createClient>, payload: {
  uid: number; originalSubject: string; originalMessageId?: string; originalFrom: string; body: string;
}) {
  const originalSubject = String(payload.originalSubject || '').trim();
  const originalFrom = String(payload.originalFrom || '').trim();
  if (!originalFrom) return { ok: false as const, action: 'reply' as const, reason: 'missing_original_from' };
  if (!originalSubject) return { ok: false as const, action: 'reply' as const, reason: 'missing_original_subject' };

  const replySubject = originalSubject.toLowerCase().startsWith('re:') ? originalSubject : `Re: ${originalSubject}`;
  return await handleCompose(_userClient, {
    to: originalFrom,
    subject: replySubject,
    body: payload.body,
    inReplyTo: payload.originalMessageId || undefined,
  }).then((r) => {
    if ('action' in r && r.action === 'compose') {
      return { ...r, action: 'reply' as const };
    }
    return r;
  });
}

async function handleForward(_userClient: ReturnType<typeof createClient>, payload: {
  uid: number; to: string; originalSubject?: string; originalBody?: string; comment?: string;
}) {
  const to = String(payload.to || '').trim();
  if (!to) return { ok: false as const, action: 'forward' as const, reason: 'missing_to' };
  const originalSubject = String(payload.originalSubject || '(geen onderwerp)').trim();
  const originalBody = sanitizeBody(payload.originalBody || '');
  const comment = sanitizeBody(payload.comment || '');

  const fwdSubject = originalSubject.toLowerCase().startsWith('fwd:') ? originalSubject : `Fwd: ${originalSubject}`;
  const quotedBody = [
    comment,
    '',
    '---------- Doorgestuurd bericht ----------',
    `Onderwerp: ${originalSubject}`,
    '',
    originalBody,
  ].join('\n');

  return await handleCompose(_userClient, {
    to,
    subject: fwdSubject,
    body: quotedBody,
  }).then((r) => {
    if ('action' in r && r.action === 'compose') {
      return { ...r, action: 'forward' as const };
    }
    return r;
  });
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
      valid_actions: ['compose', 'reply', 'forward'],
    }, 400, cors);
  }

  let result: { ok: boolean; [k: string]: unknown };
  switch (action) {
    case 'compose':
      result = await handleCompose(auth.userClient, body as { to: string; cc?: string[]; bcc?: string[]; subject: string; body: string; inReplyTo?: string });
      break;
    case 'reply':
      result = await handleReply(auth.userClient, body as { uid: number; originalSubject: string; originalMessageId?: string; originalFrom: string; body: string });
      break;
    case 'forward':
      result = await handleForward(auth.userClient, body as { uid: number; to: string; originalSubject?: string; originalBody?: string; comment?: string });
      break;
    default:
      return jsonResponse({
        ok: false,
        error: 'unknown_action',
        action,
        valid_actions: ['compose', 'reply', 'forward'],
      }, 400, cors);
  }

  const auditAction = `send_${action}`;
  await audit(auth.userClient, auditAction, { metadata: { action, request: body } });

  return jsonResponse(result, 200, cors);
});