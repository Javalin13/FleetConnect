// r050 isolated operational-mail regression test harness (per Lux §3 + §4)
// Goals:
//  1. Repair T8 dedup branch proof — call sendOperationsCopy() DIRECTLY with
//     lastDispatchOptions containing dispatch@fleetconnect.be. Assert ZERO additional
//     operations send PLUS returned reason dispatch_already_in_primary_routing.
//     This bypasses the DRIVER_ASSIGNMENT_REQUEST branch that would otherwise
//     overwrite lastDispatchOptions.bcc to [].
//  2. Extend mail matrix to ALL reachable operational triggers from current source:
//     - BOOKING_CONFIRMATION (already covered)
//     - DRIVER_ASSIGNMENT_REQUEST (already covered)
//     - DRIVER_ASSIGNED (already covered)
//     - DRIVER_REASSIGNED (NEW — via driver-accept.html customerTrigger when reassignment)
//     - DRIVER_DECLINED (already covered — operationsOnly)
//     - BOOKING_CANCELLED (NEW — via ondernemer paneel operator cancel)
//     - BOOKING_REJECTED (NEW — via ondernemer paneel operator reject)
//     - RIDE_COMPLETED_REVIEW_REQUEST (NEW — via ondernemer paneel operator complete)
//  3. Use EXACT equality for dispatch@fleetconnect.be (not substring).
//  4. Re-run timeout/security regressions (separate psql harness).

// Set up browser globals BEFORE any other module is imported
globalThis.window = { FLEETCONNECT_BASE_URL: undefined, location: { hostname: 'localhost' } };
globalThis.performance = globalThis.performance || { now: () => Date.now() };
globalThis.console = globalThis.console;
globalThis.fetch = globalThis.fetch || (() => Promise.reject(new Error('fetch not mocked')));

import { CommunicationService } from './src/modules/communication/index.js';
import { CommunicationConfig } from './src/modules/communication/core/config.js';
import { LanguageEngine } from './src/modules/communication/l10n/engine.js';
import { TemplateRegistry } from './src/modules/communication/templates/registry.js';
import { DataNormalizer } from './src/modules/communication/core/normalizer.js';
import { CommunicationLogger } from './src/modules/communication/core/logger.js';

// === RecordingMockProvider ===
class RecordingMockProvider {
    constructor() { this.sends = []; this.type = 'mock'; }
    async send(to, subject, html, options = {}) {
        this.sends.push({
            timestamp: Date.now(),
            to: to,
            subject: subject,
            html_length: html?.length || 0,
            options: options,
            allRecipients: this._collectRecipients(to, options)
        });
        return { success: true, id: `mock-${Date.now()}`, provider: 'mock' };
    }
    _collectRecipients(to, options) {
        const all = new Set();
        const add = (v) => {
            if (!v) return;
            if (typeof v === 'string') v.split(',').map(s => s.trim().toLowerCase()).filter(Boolean).forEach(e => all.add(e));
            else if (Array.isArray(v)) v.forEach(add);
        };
        add(to); add(options?.cc); add(options?.bcc);
        return Array.from(all);
    }
    reset() { this.sends = []; }
    countSendsContainingDispatchExact() {
        return this.sends.filter(s => s.allRecipients.includes('dispatch@fleetconnect.be')).length;
    }
    allSendsWithDispatchExact() {
        return this.sends.filter(s => s.allRecipients.includes('dispatch@fleetconnect.be'));
    }
}

const provider = new RecordingMockProvider();
const service = new CommunicationService();
service.activeProvider = provider;

// === Mocks ===
function makeSnapshot(overrides = {}) {
    return {
        id: 'TEST-001',
        status: 'pending',
        customer: { email: 'customer@example.com', name: 'Test Customer', phone: '+32123456789' },
        driver: { id: '11111111-1111-1111-1111-111111111111', email: 'driver@example.com', name: 'Test Driver' },
        assigned_driver_id: null,
        pickup: 'Brussels', destination: 'Antwerp', datetime: '2026-08-30 20:00',
        name: 'Test Customer', email: 'customer@example.com', phone: '+32123456789',
        flight_number: null, vehicle: 'sedan', extras: [], amount: 50.0, payment: 'cash',
        partner_id: 1, pickup_place_id: null, dropoff_place_id: null,
        route_distance_km: 50, route_duration_min: 60,
        form_data: {}, metadata: {}, created_at: new Date().toISOString(),
        payment_status: 'unpaid', is_registered: false, assignment_token: 'test-token',
        ...overrides
    };
}
function makeMockSupabase() {
    return { supabaseUrl: 'http://localhost', supabaseKey: 'mock-key' };
}

LanguageEngine.detectLanguage = () => 'en';
LanguageEngine.getSubject = () => 'Test Subject';
LanguageEngine.getTrilingualSubject = () => 'Test Subject';

for (const trigger of Object.keys(TemplateRegistry)) {
    TemplateRegistry[trigger].render = () => `<html>Mock HTML for ${trigger}</html>`;
}

DataNormalizer.rehydrateBookingSnapshot = async (id) => makeSnapshot({ id });
CommunicationLogger.log = (entry) => console.log('[LOG]', JSON.stringify(entry).substring(0, 200));

const EXACT_DISPATCH = 'dispatch@fleetconnect.be';
const results = [];

async function runScenario(name, trigger, snapshotOverrides, options = {}, expectations = {}) {
    provider.reset();
    const snap = makeSnapshot(snapshotOverrides);
    try {
        await service.trigger(trigger, snap.id, makeMockSupabase(), { snapshot: snap, ...options });
    } catch (e) {
        results.push({ name, status: 'FAIL', error: e.message });
        console.log(`✗ ${name}: ${e.message}`);
        return;
    }
    const dispatchSends = provider.allSendsWithDispatchExact();
    const dispatchCount = dispatchSends.length;
    const preservedRecipients = new Set();
    for (const s of provider.sends) {
        for (const r of s.allRecipients) preservedRecipients.add(r);
    }

    const expectedDispatchCount = expectations.dispatchSends ?? 1;
    const expectedRecipients = (expectations.preserved ?? []).map(r => r.toLowerCase());
    const missing = expectedRecipients.filter(r => !preservedRecipients.has(r));

    const passed = dispatchCount === expectedDispatchCount && missing.length === 0;

    results.push({
        name, status: passed ? 'PASS' : 'FAIL',
        total_sends: provider.sends.length, dispatch_sends: dispatchCount,
        expected_dispatch_sends: expectedDispatchCount,
        preserved_count: preservedRecipients.size,
        missing_recipients: missing
    });
    console.log(`${passed ? '✓' : '✗'} ${name}: dispatch=${dispatchCount}/${expectedDispatchCount} preserved=${preservedRecipients.size} missing=${missing.length}`);
}

// === T0: Direct sendOperationsCopy dedup branch proof ===
// Per Lux §3 r050: call sendOperationsCopy() directly with snapshot whose
// lastDispatchOptions contains dispatch@fleetconnect.be. Assert ZERO additional
// operations send + reason dispatch_already_in_primary_routing.
console.log('\n=== T0: Direct sendOperationsCopy dedup branch proof ===');
{
    provider.reset();
    const snap = makeSnapshot({
        id: 'DEDUP-TEST-001',
        status: 'pending',
        // Simulate that the primary routing ALREADY delivered to dispatch
        communication: {
            lastDispatchOptions: {
                to: ['customer@example.com'],
                cc: [],
                bcc: ['dispatch@fleetconnect.be']  // dispatch IS in primary BCC
            }
        }
    });
    const result = await service.sendOperationsCopy(
        'BOOKING_CONFIRMATION',
        snap,
        'Test Subject',
        '<html>Test</html>',
        'customer@example.com',
        makeMockSupabase()
    );
    const dispatchSends = provider.allSendsWithDispatchExact();
    const t0pass = dispatchSends.length === 0 && result.skipped === true && result.reason === 'dispatch_already_in_primary_routing';
    results.push({
        name: 'T0 direct sendOperationsCopy dedup',
        status: t0pass ? 'PASS' : 'FAIL',
        dispatch_sends: dispatchSends.length,
        result_skipped: result.skipped,
        result_reason: result.reason
    });
    console.log(`${t0pass ? '✓' : '✗'} T0 direct sendOperationsCopy dedup: dispatch_sends=${dispatchSends.length} skipped=${result.skipped} reason=${result.reason}`);
}

// === T0b: Direct sendOperationsCopy when dispatch NOT in primary routing → exactly 1 send ===
{
    provider.reset();
    const snap = makeSnapshot({
        id: 'DEDUP-TEST-002',
        status: 'pending',
        communication: {
            lastDispatchOptions: {
                to: ['customer@example.com'],
                cc: [],
                bcc: []  // dispatch NOT in primary BCC
            }
        }
    });
    const result = await service.sendOperationsCopy(
        'BOOKING_CONFIRMATION',
        snap,
        'Test Subject',
        '<html>Test</html>',
        'customer@example.com',
        makeMockSupabase()
    );
    const dispatchSends = provider.allSendsWithDispatchExact();
    const t0bpass = dispatchSends.length === 1 && result.success === true;
    results.push({
        name: 'T0b direct sendOperationsCopy (no dedup)',
        status: t0bpass ? 'PASS' : 'FAIL',
        dispatch_sends: dispatchSends.length,
        result_success: result.success
    });
    console.log(`${t0bpass ? '✓' : '✗'} T0b direct sendOperationsCopy (no dedup): dispatch_sends=${dispatchSends.length} success=${result.success}`);
}

// === Reachable operational triggers (extended matrix) ===

console.log('\n=== Reachable operational triggers ===');

// T1: BOOKING_CONFIRMATION — pending, no driver — customer + dispatch
await runScenario('T1 BOOKING_CONFIRMATION', 'BOOKING_CONFIRMATION',
    { status: 'pending', assigned_driver_id: null },
    {},
    { dispatchSends: 1, preserved: ['customer@example.com', EXACT_DISPATCH] }
);

// T2: DRIVER_ASSIGNMENT_REQUEST — auto-fired on auto-assigned booking — driver + Ayoub + CC + dispatch
await runScenario('T2 DRIVER_ASSIGNMENT_REQUEST', 'DRIVER_ASSIGNMENT_REQUEST',
    { status: 'assignment_sent', assigned_driver_id: '11111111-1111-1111-1111-111111111111' },
    {},
    { dispatchSends: 1, preserved: ['driver@example.com', 'ayoubgaddar05@gmail.com', 'fleetconnect.os@gmail.com', 'info@fleetconnect.com', EXACT_DISPATCH] }
);

// T3: DRIVER_ASSIGNED — driver accepts assignment, customer primary
await runScenario('T3 DRIVER_ASSIGNED', 'DRIVER_ASSIGNED',
    { status: 'assigned', assigned_driver_id: '11111111-1111-1111-1111-111111111111' },
    {},
    { dispatchSends: 1, preserved: ['customer@example.com', EXACT_DISPATCH] }
);

// T4: DRIVER_REASSIGNED — when reassignment accept, customer primary (NEW per Lux §4)
await runScenario('T4 DRIVER_REASSIGNED', 'DRIVER_REASSIGNED',
    { status: 'assigned', assigned_driver_id: '11111111-1111-1111-1111-111111111111' },
    {},
    { dispatchSends: 1, preserved: ['customer@example.com', EXACT_DISPATCH] }
);

// T5: DRIVER_DECLINED — internal-only via operationsOnly:true — only dispatch
await runScenario('T5 DRIVER_DECLINED', 'DRIVER_DECLINED',
    { status: 'reassignment_needed', assigned_driver_id: null },
    { operationsOnly: true },
    { dispatchSends: 1, preserved: [EXACT_DISPATCH] }
);

// T6: BOOKING_CANCELLED — operator cancels, customer primary (NEW per Lux §4)
await runScenario('T6 BOOKING_CANCELLED', 'BOOKING_CANCELLED',
    { status: 'cancelled', assigned_driver_id: '11111111-1111-1111-1111-111111111111' },
    {},
    { dispatchSends: 1, preserved: ['customer@example.com', EXACT_DISPATCH] }
);

// T7: BOOKING_REJECTED — operator rejects, customer primary (NEW per Lux §4)
await runScenario('T7 BOOKING_REJECTED', 'BOOKING_REJECTED',
    { status: 'rejected', assigned_driver_id: null },
    {},
    { dispatchSends: 1, preserved: ['customer@example.com', EXACT_DISPATCH] }
);

// T8: RIDE_COMPLETED_REVIEW_REQUEST — operator marks complete + asks for review (NEW per Lux §4)
await runScenario('T8 RIDE_COMPLETED_REVIEW_REQUEST', 'RIDE_COMPLETED_REVIEW_REQUEST',
    { status: 'completed', assigned_driver_id: '11111111-1111-1111-1111-111111111111' },
    {},
    { dispatchSends: 1, preserved: ['customer@example.com', EXACT_DISPATCH] }
);

// T9: Missing driver email → explicit failure (no Gmail fallback)
{
    provider.reset();
    const snap = makeSnapshot({ status: 'assignment_sent', assigned_driver_id: '22222222-2222-2222-2222-222222222222', driver: null });
    const r = await service.trigger('DRIVER_ASSIGNMENT_REQUEST', snap.id, makeMockSupabase(), { snapshot: snap });
    const gmailSends = provider.sends.filter(s => s.allRecipients.some(addr => addr.includes('@gmail.com')));
    const passed = r && r.success === false && gmailSends.length === 0;
    results.push({ name: 'T9 missing driver email', status: passed ? 'PASS' : 'FAIL', success: r?.success, gmail_sends: gmailSends.length });
    console.log(`${passed ? '✓' : '✗'} T9 missing driver email: success=${r?.success} gmail_sends=${gmailSends.length}`);
}

// T10: Verify dispatch address is EXACT equality (not substring match)
// Inject a fake "dispatch@fleetconnect.becom" address — should NOT count as dispatch
{
    provider.reset();
    // Inject an alternate-domain "dispatch" via custom provider call
    await provider.send(
        ['dispatch@fleetconnect.becom', 'customer@example.com'],
        'fake subject',
        'html',
        { cc: [], bcc: [] }
    );
    // The above is a direct provider call — should record with non-exact dispatch
    // Verify provider's exact-match count
    const exactDispatch = provider.countSendsContainingDispatchExact();
    // Now run a real BOOKING_CONFIRMATION which should add the REAL dispatch@fleetconnect.be
    await service.trigger('BOOKING_CONFIRMATION', 'TEST-X', makeMockSupabase(), { snapshot: makeSnapshot({ id: 'TEST-X' }) });
    const finalExactDispatch = provider.countSendsContainingDispatchExact();
    // We had 0 exact dispatch sends initially (the .becom was excluded), then 1 exact dispatch from BOOKING_CONFIRMATION
    const passed = finalExactDispatch === 1;
    results.push({ name: 'T10 EXACT dispatch equality (not substring)', status: passed ? 'PASS' : 'FAIL',
                  initial_dispatch: exactDispatch, final_dispatch: finalExactDispatch });
    console.log(`${passed ? '✓' : '✗'} T10 EXACT dispatch equality: initial=${exactDispatch} final=${finalExactDispatch}`);
}

// T11: Verify NO .com platform identity drift in subject/options
{
    provider.reset();
    await service.trigger('BOOKING_CONFIRMATION', 'TEST-CC', makeMockSupabase(), { snapshot: makeSnapshot({ id: 'TEST-CC' }) });
    const hasComDrift = provider.sends.some(s =>
        s.options?.from?.toString().includes('@fleetconnect.com') ||
        s.options?.replyTo?.toString().includes('@fleetconnect.com')
    );
    const passed = !hasComDrift;
    results.push({ name: 'T11 no .com platform identity drift', status: passed ? 'PASS' : 'FAIL',
                  has_com_drift: hasComDrift });
    console.log(`${passed ? '✓' : '✗'} T11 no .com drift: hasComDrift=${hasComDrift}`);
}

// === SUMMARY ===
console.log('\n=== SUMMARY ===');
const passed = results.filter(r => r.status === 'PASS').length;
const failed = results.filter(r => r.status === 'FAIL').length;
console.log(`Total: ${results.length}, PASS: ${passed}, FAIL: ${failed}`);
for (const r of results) {
    console.log(`  ${r.status === 'PASS' ? '✓' : '✗'} ${r.name}`);
}

process.exit(failed === 0 ? 0 : 1);