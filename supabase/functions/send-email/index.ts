import { serve } from "https://deno.land/std@0.190.0/http/server.ts"
import { Resend } from "npm:resend@2.0.0"

/**
 * FleetConnect Email Dispatch Edge Function
 * Securely handles Resend API calls without exposing keys to the client.
 */

const resend = new Resend(Deno.env.get('RESEND_API_KEY'))

const ALLOWED_ORIGINS = [
  'https://fleetconnect.be',
  'https://www.fleetconnect.be',
  'https://rpk-mu.vercel.app',
  'https://fleetconnectfork.vercel.app',
  'https://fleet-connect-fork.vercel.app',
  'https://portal.fleetconnect.be',
  'https://client.fleetconnect.be',
  'https://partners.fleetconnect.be',
  'http://localhost:3000',
  'http://127.0.0.1:5500'
]

const EXTRA_ALLOWED_ORIGINS = (Deno.env.get('FLEETCONNECT_ALLOWED_ORIGINS') || '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean)

function isAllowedFleetConnectOrigin(origin: string | null) {
  if (!origin) return false
  if (ALLOWED_ORIGINS.includes(origin) || EXTRA_ALLOWED_ORIGINS.includes(origin)) return true

  try {
    const url = new URL(origin)
    if (url.protocol !== 'https:') return false
    return (
      url.hostname === 'fleetconnect.be' ||
      url.hostname.endsWith('.fleetconnect.be') ||
      /^fleetconnectfork(-.*)?\.vercel\.app$/.test(url.hostname) ||
      /^fleet-connect-fork(-.*)?\.vercel\.app$/.test(url.hostname)
    )
  } catch (_) {
    return false
  }
}

function sanitizeResendTag(value: unknown) {
  const cleaned = String(value ?? '')
    .replace(/[^A-Za-z0-9_-]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .substring(0, 40)

  return cleaned || 'unknown'
}

serve(async (req) => {
  const origin = req.headers.get('origin')
  const isAllowedOrigin = isAllowedFleetConnectOrigin(origin)

  const corsHeaders = {
    'Access-Control-Allow-Origin': isAllowedOrigin ? origin : ALLOWED_ORIGINS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
  }

  // 1. Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    if (origin && !isAllowedOrigin) {
      console.error(`[Email Dispatch] Blocked unauthorized origin: ${origin}`)
      return new Response(JSON.stringify({ success: false, error: 'Unauthorized origin' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 403,
      })
    }

    const payload = await req.json()
    const { to, subject, html, from, reply_to, cc, bcc, metadata } = payload

    // 2. Strict Payload Validation
    if (!to || (Array.isArray(to) && to.length === 0)) {
      throw new Error('Missing recipient (to)')
    }
    if (!subject) throw new Error('Missing subject')
    if (!html) throw new Error('Missing html content')

    // Simple email format check for strings
    const recipients = Array.isArray(to) ? to : [to];
    for (const email of recipients) {
      if (!email.includes('@')) {
        throw new Error(`Invalid email format: ${email}`)
      }
    }
    const ccRecipients = cc ? (Array.isArray(cc) ? cc : [cc]) : []
    const bccRecipients = bcc ? (Array.isArray(bcc) ? bcc : [bcc]) : []
    for (const email of [...ccRecipients, ...bccRecipients]) {
      if (!email.includes('@')) {
        throw new Error(`Invalid email format: ${email}`)
      }
    }

    console.log(`[Email Dispatch] Trigger: ${metadata?.trigger || 'Unknown'} | To: ${recipients.join(', ')}`);

    // 3. Dispatch via Resend
    // Allow verified FleetConnect-domain senders, otherwise use the canonical configured sender.
    const senderEnv = Deno.env.get('FLEETCONNECT_EMAIL_FROM')
    const requestedSender = typeof from === 'string' ? from : ''
    const requestedSenderAllowed = /@fleetconnect\.be>?$/i.test(requestedSender.trim())
    const sender = requestedSenderAllowed ? requestedSender : (senderEnv || 'FleetConnect <bookings@fleetconnect.be>')
    const senderFallbackUsed = !requestedSenderAllowed && !senderEnv
    console.log(`[Email Dispatch] FLEETCONNECT_EMAIL_FROM exists: ${senderEnv ? 'yes' : 'no'}`)
    console.log(`[Email Dispatch] Requested sender allowed: ${requestedSenderAllowed ? 'yes' : 'no'}`)
    console.log(`[Email Dispatch] Sender fallback used: ${senderFallbackUsed ? 'yes' : 'no'}`)
    console.log(`[Email Dispatch] Sender address used: ${sender}`)

    const { data, error } = await resend.emails.send({
      from: sender,
      to: to,
      ...(ccRecipients.length ? { cc: ccRecipients } : {}),
      ...(bccRecipients.length ? { bcc: bccRecipients } : {}),
      subject: subject,
      html: html,
      reply_to: reply_to || 'support@fleetconnect.be',
      // Pass metadata as tags for Resend dashboard tracking
      tags: metadata ? Object.entries(metadata).map(([name, value]) => ({
        name: sanitizeResendTag(name),
        value: sanitizeResendTag(value)
      })) : []
    })

    if (error) {
      console.error('[Resend SDK Error]', error)
      const errorMessage = error.message || 'Resend rejected the email request'
      return new Response(JSON.stringify({
        success: false,
        error: errorMessage,
        provider: 'resend',
        code: error.name || 'resend_error',
        statusCode: error.statusCode || 400
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: error.statusCode || 400,
      })
    }

    // 4. Success Response
    return new Response(JSON.stringify({ success: true, id: data.id }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (error) {
    console.error('[Edge Function Exception]', error.message)
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
