import { BaseEmailProvider } from './base.provider.js';
import { CommunicationConfig } from '../core/config.js';

/**
 * ResendProvider
 * Integration with Resend.com API via Supabase Edge Function.
 */
export class ResendProvider extends BaseEmailProvider {
    /**
     * @param {object} config - Must include { endpoint, from }
     */
    constructor(config) {
        super(config);
    }

    /**
     * Send email via secure backend abstraction.
     * This protects the Resend API key by executing the call server-side.
     */
    async send(to, subject, html, options = {}) {
        const payload = {
            from: options.from || this.config.from,
            reply_to: options.replyTo || this.config.replyTo,
            to: Array.isArray(to) ? to : [to],
            subject: subject,
            html: html,
            metadata: {
                bookingId: options.bookingId,
                trigger: options.trigger
            }
        };
        if (options.cc) payload.cc = Array.isArray(options.cc) ? options.cc : [options.cc];
        if (options.bcc) payload.bcc = Array.isArray(options.bcc) ? options.bcc : [options.bcc];

        try {
            // Use Supabase credentials from context if available, otherwise fallback to config
            const baseUrl = options.supabaseUrl || CommunicationConfig.settings.supabaseUrl;
            const supabaseKey = options.supabaseKey || CommunicationConfig.settings.supabaseKey || '';
            const functionBase = CommunicationConfig.settings.edgeFunctionBase || '/functions/v1';
            const endpoint = this.config.endpoint;

            // Handle potential double-slashes during path construction
            const cleanFunctionBase = functionBase.endsWith('/') ? functionBase.slice(0, -1) : functionBase;
            const cleanEndpoint = endpoint.startsWith('/') ? endpoint : `/${endpoint}`;
            const fullUrl = `${baseUrl}${cleanFunctionBase}${cleanEndpoint}`;

            let response = await fetch(fullUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'apikey': supabaseKey,
                    'Authorization': `Bearer ${supabaseKey}`
                },
                body: JSON.stringify(payload)
            });

            let raw = await response.text();
            let data = {};
            try {
                data = raw ? JSON.parse(raw) : {};
            } catch (parseError) {
                data = { error: raw || parseError.message };
            }

            // Self-healing fallback: If sending via .com failed (e.g. because of unverified domain on Resend), retry via verified .be domain!
            if ((!response.ok || data.success === false) && payload.from && payload.from.includes('@fleetconnect.com')) {
                console.warn(`[ResendProvider] Dispatch via .com failed. Retrying with verified .be domain fallback...`);
                payload.from = payload.from.replace('@fleetconnect.com', '@fleetconnect.be');
                if (payload.reply_to) payload.reply_to = payload.reply_to.replace('@fleetconnect.com', '@fleetconnect.be');
                if (payload.cc) payload.cc = payload.cc.map(email => email.replace('@fleetconnect.com', '@fleetconnect.be'));
                if (payload.bcc) payload.bcc = payload.bcc.map(email => email.replace('@fleetconnect.com', '@fleetconnect.be'));

                response = await fetch(fullUrl, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'apikey': supabaseKey,
                        'Authorization': `Bearer ${supabaseKey}`
                    },
                    body: JSON.stringify(payload)
                });
                raw = await response.text();
                try {
                    data = raw ? JSON.parse(raw) : {};
                } catch (parseError) {
                    data = { error: raw || parseError.message };
                }
            }

            if (!response.ok || data.success === false) {
                throw new Error(data.error || data.message || `HTTP ${response.status}: Dispatch failed via backend`);
            }

            return {
                success: true,
                id: data.id || `resend-${Date.now()}`,
                provider: 'resend'
            };
        } catch (error) {
            console.error('[ResendProvider] send-email failed:', {
                message: error.message,
                trigger: options.trigger,
                bookingId: options.bookingId,
                recipients: payload.to
            });
            return {
                success: false,
                error: error.message,
                provider: 'resend'
            };
        }
    }
}
