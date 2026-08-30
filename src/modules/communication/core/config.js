/**
 * FleetConnect Communication Configuration
 * Centralized theme, branding, and service settings.
 */
export const CommunicationConfig = {
    brand: {
        name: 'FleetConnect',
        email: 'support@fleetconnect.be',
        website: window.FLEETCONNECT_BASE_URL || 'https://fleetconnect.be',
        reviewUrl: '',
        logoUrl: '', // To be filled later
        // r046: Moukrim dispatch phone per Lux §0 / Founder clarification 6010b3e / 6c2c1f6
        supportPhone: '+32470485609',
        supportWhatsapp: '32470485609',
        operationsEmail: 'dispatch@fleetconnect.be',
        technicalEscalationEmail: 'tech@fleetconnect.be'
    },
    routing: {
        // Per Founder clarification 6c2c1f6 §0 / Lux §5: PRESERVE the intentional, explicitly configured operational dispatch
        // recipient set (including Ayoub and the other deliberately configured operational addresses). DO NOT replace these
        // with invented alternatives. Remove only fallback guesses / proven drift elsewhere.
        assignmentEmails: {
            default: {
                // r047 (per Lux §6): resolve platform .com sender drift to factual .be
                // brand.operationsEmail = dispatch@fleetconnect.be is the canonical platform identity
                // Resend provider uses FleetConnect <bookings@fleetconnect.be> as canonical from
                // Preserves intentional TO/CC recipients (Ayoub etc.) per Founder §0
                from: 'dispatch@fleetconnect.be',
                to: ['you.transport@gmail.com', 'ayoubgaddar05@gmail.com'],  // INTENTIONAL — Ayoub is deliberate operational recipient
                cc: ['fleetconnect.os@gmail.com', 'info@fleetconnect.com'],  // INTENTIONAL — explicit operational copy
                bcc: []  // r048 (per Lux §0): dispatch removed from BCC — centralized sendOperationsCopy() is the canonical archive path; exactly-once invariant enforced
            }
        }
    },
    theme: {
        primaryColor: '#2dd4bf', // Teal/Turquoise
        secondaryColor: '#0f172a', // Luxury Dark
        textColor: '#334155',
        backgroundColor: '#f8fafc',
        fontFamily: "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif"
    },
    settings: {
        defaultLanguage: 'en',
        supportedLanguages: ['en', 'fr', 'nl', 'es', 'ar'],
        fallbackMode: 'trilingual', // 'trilingual' or 'default'
        trilingualOrder: ['en', 'fr', 'nl', 'es', 'ar'],
        provider: window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1' ? 'mock' : 'resend',
        supabaseUrl: 'https://rreqjjrmvytnwnsidmqi.supabase.co',
        supabaseKey: 'eyJhbG...8MTA',
        edgeFunctionBase: '/functions/v1',
        ASSIGNMENT_TIMEOUT_MINUTES: 30
    },
    providers: {
        resend: {
            // Secure backend endpoint (Supabase Edge Function)
            // This prevents exposing the Resend API Key in the browser.
            endpoint: '/send-email',
            from: 'FleetConnect <bookings@fleetconnect.be>',
            replyTo: 'support@fleetconnect.be'
        }
    }
};
