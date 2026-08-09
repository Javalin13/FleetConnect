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
        supportPhone: '+3200000000',
        supportWhatsapp: '3200000000',
        operationsEmail: 'dispatch@fleetconnect.be',
        technicalEscalationEmail: 'tech@fleetconnect.be'
    },
    routing: {
        assignmentEmails: {
            default: {
                from: 'dispatch@fleetconnect.com',
                to: ['you.transport@gmail.com', 'ayoubgaddar05@gmail.com'],
                cc: ['fleetconnect.os@gmail.com', 'ryzenoutsourcing@gmail.com'],
                bcc: ['dispatch@fleetconnect.com']
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
        supabaseKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJyZXFqanJtdnl0bnduc2lkbXFpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0MjAxMzcsImV4cCI6MjA5Mzk5NjEzN30.q4M3A6Dix3F_9Im2pw8DUIeE4C-INtUlvImRDM58MTA',
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
