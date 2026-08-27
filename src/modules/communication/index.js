import { CommunicationConfig } from './core/config.js';
import { MockProvider } from './providers/mock.provider.js';
import { ResendProvider } from './providers/resend.provider.js';
import { TemplateRegistry } from './templates/registry.js';
import { LanguageEngine } from './l10n/engine.js';
import { DataNormalizer } from './core/normalizer.js';
import { CommunicationLogger } from './core/logger.js';

/**
 * CommunicationService (The Orchestrator)
 * Central entry point for all communication triggers.
 * Handles normalization, localization, and dispatching.
 */
export class CommunicationService {
    constructor() {
        this.providers = {
            mock: new MockProvider(),
            resend: new ResendProvider(CommunicationConfig.providers.resend)
        };
        this.activeProvider = this.providers[CommunicationConfig.settings.provider] || this.providers.mock;
        this.escalationKeys = new Set();
        this.internalOnlyTriggers = new Set([
            'BOOKING_ACCEPTED',
            'DRIVER_DECLINED'
        ]);
    }

    /**
     * Dispatch a communication trigger by rehydrating the snapshot first.
     * @param {string} trigger - e.g., 'DRIVER_ASSIGNED'
     * @param {string} bookingId - The booking UUID
     * @param {object} supabaseClient - Shared supabase client
     */
    async trigger(trigger, bookingId, supabaseClient, options = {}) {
        const startTime = performance.now();
        console.log(`[CommunicationService] START Trigger: ${trigger} | ID: ${bookingId}`);

        if (!bookingId || !supabaseClient) {
            console.error(`❌ CommunicationService: Missing ID or client for ${trigger}`);
            return;
        }

        try {
            // 1. Full Relational Rehydration, unless the caller already has a trusted snapshot.
            const snapshot = options.snapshot || await DataNormalizer.rehydrateBookingSnapshot(bookingId, supabaseClient);
            if (!snapshot) {
                console.error(`❌ [CommunicationService] Rehydration failed for ${bookingId}`);
                throw new Error('Failed to rehydrate snapshot');
            }

            // 2. Localization Settings
            const lang = LanguageEngine.detectLanguage(snapshot, snapshot.customer);
            const mode = CommunicationConfig.settings.fallbackMode;

            // 3. Subject Construction
            const subject = mode === 'trilingual'
                ? LanguageEngine.getTrilingualSubject(trigger)
                : LanguageEngine.getSubject(trigger, lang);

            // 4. Rendering
            const template = TemplateRegistry[trigger];
            if (!template) throw new Error(`Template not found for ${trigger}`);
            const html = template.render(snapshot, lang, mode);

            // Trigger automatic driver assignment request if a booking is auto-assigned
            if (trigger === 'BOOKING_CONFIRMATION') {
                const isAutoAssigned = (snapshot.status === 'assignment_sent' || snapshot.status === 'assigned') && snapshot.assignment_token && (snapshot.driver?.email || snapshot.assigned_driver_id);
                if (isAutoAssigned) {
                    console.log(`[CommunicationService] Auto-assigned booking detected on confirmation. Triggering DRIVER_ASSIGNMENT_REQUEST for ${bookingId} asynchronously.`);
                    this.trigger('DRIVER_ASSIGNMENT_REQUEST', bookingId, supabaseClient, { snapshot }).catch(err => {
                        console.error('❌ Failed to trigger auto driver assignment email:', err);
                    });
                }
            }

            // 5. Dispatch
            let to = snapshot.customer?.email || snapshot.email;
            let dispatchOptions = {
                bookingId: snapshot.id,
                trigger: trigger,
                supabaseUrl: supabaseClient.supabaseUrl,
                supabaseKey: supabaseClient.supabaseKey
            };

            // Route DRIVER_ASSIGNMENT_REQUEST to the configured driver recipients, CC, and BCC
            if (trigger === 'DRIVER_ASSIGNMENT_REQUEST') {
                const routeRules = CommunicationConfig.routing?.assignmentEmails?.default || {};
                const driverEmail = snapshot.driver?.email || 'you.transport@gmail.com';

                // Set to, cc, bcc, from
                to = [driverEmail, 'ayoubgaddar05@gmail.com'];
                dispatchOptions.from = routeRules.from || 'dispatch@fleetconnect.com';
                dispatchOptions.replyTo = routeRules.from || 'dispatch@fleetconnect.com';
                dispatchOptions.cc = routeRules.cc || ['fleetconnect.os@gmail.com', 'info@fleetconnect.com'];
                dispatchOptions.bcc = routeRules.bcc || ['dispatch@fleetconnect.com'];
            }

            const internalOnly = options.operationsOnly || this.internalOnlyTriggers.has(trigger);
            if (!internalOnly && (!to || (Array.isArray(to) && to.length === 0))) throw new Error('Recipient email missing');

            let result = { success: true, provider: this.activeProvider.constructor.name, internalOnly };

            if (!internalOnly) {
                console.log(`[CommunicationService] Sending ${trigger} to ${Array.isArray(to) ? to.join(', ') : to} via ${this.activeProvider.constructor.name}`);

                result = await this.activeProvider.send(to, subject, html, dispatchOptions);
            }

            const operationsResult = await this.sendOperationsCopy(trigger, snapshot, subject, html, internalOnly ? null : to, supabaseClient);
            if (!result.success || !operationsResult.success) {
                await this.sendTechnicalEscalation(trigger, snapshot.id, result.error || operationsResult.error || 'Communication delivery failure', supabaseClient);
            }

            const duration = (performance.now() - startTime).toFixed(2);
            console.log(`[CommunicationService] END Trigger: ${trigger} | To: ${to} | Status: ${result.success ? 'SUCCESS' : 'FAILED'} | Duration: ${duration}ms`);

            // 6. Logging
            CommunicationLogger.log({
                trigger,
                to,
                subject,
                status: result.success ? 'success' : 'failed',
                provider: result.provider,
                bookingId: snapshot.id,
                lang: mode === 'trilingual' ? 'TRILINGUAL' : lang,
                error: result.error,
                operationsStatus: operationsResult.success ? 'success' : 'failed'
            });

            return result;

        } catch (error) {
            const duration = (performance.now() - startTime).toFixed(2);
            console.error(`❌ [CommunicationService] FATAL ERROR [${trigger}] for ${bookingId} after ${duration}ms:`, error.message);

            CommunicationLogger.log({
                trigger,
                status: 'error',
                bookingId,
                error: error.message
            });

            await this.sendTechnicalEscalation(trigger, bookingId, error.message, supabaseClient);
            return { success: false, error: error.message, provider: this.activeProvider.constructor.name };
        }
    }

    async sendOperationsCopy(trigger, snapshot, subject, html, primaryRecipient, supabaseClient) {
        const recipients = [CommunicationConfig.brand.operationsEmail]
            .filter(Boolean)
            .filter((email) => email !== primaryRecipient);

        if (!recipients.length) {
            return { success: true, skipped: true };
        }

        const operationsSubject = `[FleetConnect Ops] ${subject || trigger} (${snapshot.id})`;

        const result = await this.activeProvider.send(recipients, operationsSubject, html, {
            bookingId: snapshot.id,
            trigger: `${trigger}_OPERATIONS`,
            replyTo: CommunicationConfig.providers.resend.replyTo,
            supabaseUrl: supabaseClient.supabaseUrl,
            supabaseKey: supabaseClient.supabaseKey
        });

        CommunicationLogger.log({
            trigger: `${trigger}_OPERATIONS`,
            to: recipients.join(', '),
            subject: operationsSubject,
            status: result.success ? 'success' : 'failed',
            provider: result.provider,
            bookingId: snapshot.id,
            error: result.error
        });

        return result;
    }

    async sendTechnicalEscalation(trigger, entityId, errorMessage, supabaseClient) {
        const to = CommunicationConfig.brand.technicalEscalationEmail;
        if (!to) return { success: true, skipped: true };

        const escalationKey = `${trigger}:${entityId || 'unknown'}:${errorMessage || 'Unknown error'}`;
        if (this.escalationKeys.has(escalationKey)) {
            console.warn(`[CommunicationService] Skipping duplicate technical escalation for ${trigger} (${entityId || 'unknown'})`);
            return { success: true, skipped: true, duplicate: true };
        }
        this.escalationKeys.add(escalationKey);

        const subject = `[FleetConnect Technical] ${trigger} failure (${entityId || 'unknown'})`;
        const html = `
            <div style="font-family: Inter, Arial, sans-serif; color: #0f172a;">
                <h2>FleetConnect communication escalation</h2>
                <p><strong>Trigger:</strong> ${trigger}</p>
                <p><strong>Entity:</strong> ${entityId || 'unknown'}</p>
                <p><strong>Error:</strong> ${errorMessage || 'Unknown error'}</p>
            </div>
        `;

        return this.activeProvider.send(to, subject, html, {
            bookingId: entityId,
            trigger: `${trigger}_TECHNICAL_ESCALATION`,
            replyTo: CommunicationConfig.providers.resend.replyTo,
            supabaseUrl: supabaseClient?.supabaseUrl,
            supabaseKey: supabaseClient?.supabaseKey
        });
    }

    async sendAccountWelcome(customer, supabaseClient) {
        return this.sendCustomerRegistrationConfirmation(customer, supabaseClient);
    }

    async sendCustomerRegistrationConfirmation(customer, supabaseClient) {
        const startTime = performance.now();
        const snapshot = {
            id: customer.id || customer.email,
            booking_id: customer.booking_id || customer.booking || '',
            token: customer.token || '',
            booking_id: customer.booking_id || customer.booking || '',
            customer: {
                name: customer.name || customer.full_name,
                email: customer.email,
                phone: customer.phone,
                preferred_language: customer.preferred_language || CommunicationConfig.settings.defaultLanguage
            },
            preferred_language: customer.preferred_language || CommunicationConfig.settings.defaultLanguage
        };

        try {
            const lang = LanguageEngine.detectLanguage(snapshot, snapshot.customer);
            const mode = CommunicationConfig.settings.fallbackMode;
            const trigger = 'CUSTOMER_REGISTRATION_CONFIRMATION';
            const subject = mode === 'trilingual'
                ? LanguageEngine.getTrilingualSubject(trigger)
                : LanguageEngine.getSubject(trigger, lang);
            const html = TemplateRegistry[trigger].render(snapshot, lang, mode);

            const result = await this.activeProvider.send(snapshot.customer.email, subject, html, {
                bookingId: snapshot.id,
                trigger,
                from: 'FleetConnect Support <support@fleetconnect.be>',
                replyTo: 'support@fleetconnect.be',
                supabaseUrl: supabaseClient?.supabaseUrl,
                supabaseKey: supabaseClient?.supabaseKey
            });

            const operationsResult = await this.sendOperationsCopy(trigger, snapshot, subject, html, snapshot.customer.email, supabaseClient || {});
            if (!result.success || !operationsResult.success) {
                await this.sendTechnicalEscalation(trigger, snapshot.id, result.error || operationsResult.error || 'Account welcome delivery failure', supabaseClient);
            }

            CommunicationLogger.log({
                trigger,
                to: snapshot.customer.email,
                subject,
                status: result.success ? 'success' : 'failed',
                provider: result.provider,
                bookingId: snapshot.id,
                duration: (performance.now() - startTime).toFixed(2),
                operationsStatus: operationsResult.success ? 'success' : 'failed',
                error: result.error
            });

            return result;
        } catch (error) {
            CommunicationLogger.log({
                trigger: 'CUSTOMER_REGISTRATION_CONFIRMATION',
                status: 'error',
                bookingId: snapshot.id,
                error: error.message
            });
            await this.sendTechnicalEscalation('CUSTOMER_REGISTRATION_CONFIRMATION', snapshot.id, error.message, supabaseClient);
            return { success: false, error: error.message };
        }
    }
}

// Export a singleton instance
export const comms = new CommunicationService();
