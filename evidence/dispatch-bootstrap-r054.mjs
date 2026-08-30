// r054 — Secure dispatch power-admin bootstrap (CORRECTED per Lux r053 §1)
//
// Per Lux r053 §1 CORRECTION:
// - REMOVED hardcoded `partner_id: 'moukrim-dispatch'` string
// - Partner scope is now derived FACTUALLY by authorize_admin_role() RPC
//   which queries public.partners WHERE user_id = auth.uid()
// - dispatch@fleetconnect.be identity remains as power-admin via
//   app_metadata.role='dispatch' + app_metadata.is_admin=true
//
// Per Lux r051 §8 FOUNDER OVERRIDE (Founder approval 2026-08-30):
// - Authorize PRIME to design/implement safest practical dispatch login path
// - HARD CONSTRAINTS:
//   * NO hardcoded password/token/service-role/JWT in HTML/JS/GitHub/bridge/Telegram/evidence
//   * NO frontend-only bypass
//   * NO RLS weakening
//   * NO accidental public signup
//   * NO password guessing
//   * NO blind rate-limit retries
// - ACCEPTABLE: bootstrap dispatch@fleetconnect.be as confirmed admin/operator
//   via Supabase Admin API (createUser OR updateUserById) using password supplied
//   ONLY through env-var (DISPATCH_ADMIN_PASSWORD); the password is NEVER
//   embedded in this script or anywhere else.
// - TARGET IDENTITY: dispatch@fleetconnect.be
//
// Plan correction (per Founder r053): Use Supabase Admin API (NOT SQL migration
// against auth.users). authorize_admin_role() reads auth.users.app_metadata
// and public.partners.is_hoofd relationship; the RPC does the actual
// authorization check at runtime. This script only bootstraps the user record.
//
// After provisioning, the normal FleetConnect UI continues using
// supabase.auth.signInWithPassword({ email, password }) path.
//
// Authorization flow at runtime (r054):
//   1. Browser: signInWithPassword({ email, password })
//   2. Browser: supabase.rpc('authorize_admin_role') -> { authorized, founder_scope, operator_scope, ... }
//   3. Browser: gate panel rendering on authz.authorized
//   4. Protected pages: re-check sessionStorage flags (defense in depth; flags
//      can only be set after a successful authorize_admin_role() call from a
//      valid session).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const TARGET_EMAIL = 'dispatch@fleetconnect.be';
const ADMIN_BASE_URL = process.env.SUPABASE_ADMIN_URL || 'http://127.0.0.1:54321';
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const PASSWORD = process.env.DISPATCH_ADMIN_PASSWORD;

if (!SERVICE_ROLE_KEY) {
  console.error('FATAL: SUPABASE_SERVICE_ROLE_KEY env var required (server-side only, never commit)');
  process.exit(2);
}
if (!PASSWORD) {
  console.error('FATAL: DISPATCH_ADMIN_PASSWORD env var required (Founder-provided, server-side only)');
  process.exit(2);
}
if (PASSWORD.length < 12) {
  console.error('FATAL: DISPATCH_ADMIN_PASSWORD must be at least 12 chars for nonprod; 16+ for prod-like');
  process.exit(2);
}

console.log(`[bootstrap] target=${TARGET_EMAIL} url=${ADMIN_BASE_URL}`);
console.log(`[bootstrap] password length=${PASSWORD.length} chars (value never logged)`);

const admin = createClient(ADMIN_BASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false }
});

// Step 1: Look up existing user
console.log('[bootstrap] step 1: looking up existing dispatch account via Admin API...');
const { data: existing, error: lookupError } = await admin.auth.admin.listUsers();
if (lookupError) {
  console.error('FATAL: admin.listUsers failed:', lookupError.message);
  process.exit(3);
}

const found = existing?.users?.find(u => u.email === TARGET_EMAIL);
console.log(`[bootstrap] existing dispatch user: ${found ? found.id + ' (created ' + found.created_at + ')' : 'NOT FOUND'}`);

let result;
if (found) {
  // Step 2a: UPDATE existing dispatch user — set password + email_confirmed + app_metadata
  // r054: do NOT inject hardcoded partner_id; partner scope is derived at runtime
  // via authorize_admin_role() -> public.partners user_id lookup.
  console.log('[bootstrap] step 2a: updating existing user via auth.admin.updateUserById...');
  const { data, error } = await admin.auth.admin.updateUserById(
    found.id,
    {
      password: PASSWORD,
      email_confirm: true,
      app_metadata: {
        ...(found.app_metadata || {}),
        role: 'dispatch',
        is_admin: true,
        provider: 'fleetconnect-bootstrap-r054',
        bootstrap_at: new Date().toISOString()
        // partner_id: REMOVED — derived at runtime via authorize_admin_role()
      },
      user_metadata: {
        ...(found.user_metadata || {}),
        role: 'dispatch',
        display_name: 'Dispatch Admin'
      }
    }
  );
  if (error) {
    console.error('FATAL: updateUserById failed:', error.message);
    process.exit(4);
  }
  result = data;
} else {
  // Step 2b: CREATE dispatch user with email_confirm: true (server-side)
  console.log('[bootstrap] step 2b: creating new user via auth.admin.createUser...');
  const { data, error } = await admin.auth.admin.createUser({
    email: TARGET_EMAIL,
    password: PASSWORD,
    email_confirm: true,
    app_metadata: {
      role: 'dispatch',
      is_admin: true,
      provider: 'fleetconnect-bootstrap-r054',
      bootstrap_at: new Date().toISOString()
      // partner_id: REMOVED — derived at runtime via authorize_admin_role()
    },
    user_metadata: {
      role: 'dispatch',
      display_name: 'Dispatch Admin',
      email_verified: true
    }
  });
  if (error) {
    console.error('FATAL: createUser failed:', error.message);
    process.exit(5);
  }
  result = data;
}

console.log(`[bootstrap] dispatch user provisioned:`);
console.log(`  id:           ${result.user?.id}`);
console.log(`  email:        ${result.user?.email}`);
console.log(`  confirmed_at: ${result.user?.email_confirmed_at}`);
console.log(`  app_metadata: ${JSON.stringify(result.user?.app_metadata)}`);
console.log(`  user_metadata:${JSON.stringify(result.user?.user_metadata)}`);
console.log('');
console.log('[bootstrap] SUCCESS — dispatch@fleetconnect.be ready');
console.log('[bootstrap] next step: verify authorize_admin_role() returns founder_scope=true');
console.log('[bootstrap] next step: verify negative roles (customer/driver/regular-partner) return authorized=false');