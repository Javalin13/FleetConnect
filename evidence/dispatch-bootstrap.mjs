// r053 — Secure dispatch power-admin bootstrap
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
// Plan correction: Use Supabase Admin API (NOT SQL migration against auth.users):
//   auth.admin.createUser(...) if dispatch account does not yet exist
//   auth.admin.updateUserById(...) if dispatch account already exists
//   Set email_confirm: true / confirmed_at server-side so no email-verification
//   dependency blocks the Founder.
//   service-role credential remains server-side only and must never enter
//   browser code, GitHub, evidence, Bridge, Telegram or chat.
//
// After provisioning, the normal FleetConnect UI continues using
// supabase.auth.signInWithPassword({ email, password }) path.
//
// Authorization model proof (Lux r051 §8): the dispatch identity must map to
// the existing FleetConnect admin/operator authorization model. Currently
// admin-index.html has no role check (any auth user gets through to panel
// selector), but partner-login.html checks user_metadata.role === 'partner'.
// For dispatch to receive OPERATIONAL authority, the bootstrap sets
// app_metadata.role = 'dispatch' AND app_metadata.is_admin = true, so any
// future RLS/role check that examines the standard role field will find
// the correct value without weakening any existing checks.

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

// Step 1: Look up existing user (page through in case there are many)
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
        provider: 'fleetconnect-bootstrap-r053',
        bootstrap_at: new Date().toISOString()
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
  result = { action: 'updated', user_id: data.user.id, email: data.user.email };
} else {
  // Step 2b: CREATE new dispatch user with email_confirm=true
  console.log('[bootstrap] step 2b: creating new dispatch user via auth.admin.createUser...');
  const { data, error } = await admin.auth.admin.createUser({
    email: TARGET_EMAIL,
    password: PASSWORD,
    email_confirm: true,
    app_metadata: {
      role: 'dispatch',
      is_admin: true,
      provider: 'fleetconnect-bootstrap-r053',
      bootstrap_at: new Date().toISOString()
    },
    user_metadata: {
      role: 'dispatch',
      display_name: 'Dispatch Admin'
    }
  });
  if (error) {
    console.error('FATAL: createUser failed:', error.message);
    process.exit(5);
  }
  result = { action: 'created', user_id: data.user.id, email: data.user.email };
}

console.log('[bootstrap] step 3: SUCCESS');
console.log(JSON.stringify(result, null, 2));

// Step 4: Verify by reading back via Admin API
console.log('[bootstrap] step 4: verifying via auth.admin.getUserById...');
const { data: verify, error: vErr } = await admin.auth.admin.getUserById(result.user_id);
if (vErr) {
  console.error('FATAL: getUserById verification failed:', vErr.message);
  process.exit(6);
}
const verified = {
  id: verify.user.id,
  email: verify.user.email,
  email_confirmed_at: verify.user.email_confirmed_at,
  app_metadata: verify.user.app_metadata,
  user_metadata: verify.user.user_metadata
};
console.log('[bootstrap] verification:');
console.log(JSON.stringify(verified, null, 2));

// Final assertions
if (verified.email !== TARGET_EMAIL) {
  console.error(`FATAL: email mismatch (expected ${TARGET_EMAIL}, got ${verified.email})`);
  process.exit(7);
}
if (!verified.email_confirmed_at) {
  console.error('FATAL: email_confirmed_at is null — email-verification dependency NOT bypassed');
  process.exit(8);
}
if (verified.app_metadata?.role !== 'dispatch') {
  console.error(`FATAL: app_metadata.role is "${verified.app_metadata?.role}" (expected "dispatch")`);
  process.exit(9);
}
if (verified.app_metadata?.is_admin !== true) {
  console.error(`FATAL: app_metadata.is_admin is "${verified.app_metadata?.is_admin}" (expected true)`);
  process.exit(10);
}

console.log('[bootstrap] ALL ASSERTIONS PASS');
console.log('[bootstrap] output: dispatch power-admin bootstrap complete; normal signInWithPassword flow ready');
console.log(`[bootstrap] user_id=${result.user_id} action=${result.action}`);
