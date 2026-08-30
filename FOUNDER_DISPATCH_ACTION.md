# FOUNDER DISPATCH ACTION — Single Concrete Provisioning Action (r053)

**Mission**: `2026-08-29-fleetconnect-operational-recovery`
**Date**: 2026-08-30T17:00+02:00
**Authority**: Lux r051 §8 (Founder override) + Founder correction (use Admin API, NOT SQL)

---

## ONE Action Required from Founder

Set the **`DISPATCH_ADMIN_PASSWORD`** environment variable to the actual password value through an approved secure secret mechanism.

### What to set

The bootstrap script (`evidence/dispatch-bootstrap.mjs`) reads the password from this env var name:
```
DISPATCH_ADMIN_PASSWORD=<Founder-chosen-password>
```

### Approved secure mechanisms (Founder's choice)

Pick ONE:
1. **Vault** the Founder controls (1Password, Bitwarden, AWS Secrets Manager, etc.) — export env var when running bootstrap
2. **One-time-share link** with expiration (Bitwarden Send, 1Password sharing)
3. **Founder-signed env file** on the VPS that PRIME loads at runtime (never committed)
4. **Direct Founder dictation** in a private, non-recorded session; PRIME types it into the env file then deletes the chat log

### What PRIME does with the password

PRIME runs the bootstrap script in **isolated/staging** only (NOT production):
```bash
# Server-side only; values never enter HTML/JS/GitHub/bridge/Telegram/evidence
export SUPABASE_SERVICE_ROLE_KEY=<supabase-staging-service-role-key-from-vault>
export DISPATCH_ADMIN_PASSWORD=<password-from-Founder>
node evidence/dispatch-bootstrap.mjs
```

The script calls `supabase.auth.admin.createUser` (or `updateUserById` if exists) with `email_confirm: true` so no email-verification dependency blocks the Founder.

### What PRIME does NOT do

- ❌ Do NOT modify production Supabase
- ❌ Do NOT put the password in HTML/JS/GitHub/bridge/Telegram/evidence/commits
- ❌ Do NOT add a frontend-only bypass such as `if (email===... && password===...)`
- ❌ Do NOT weaken RLS policies
- ❌ Do NOT create another accidental public signup user
- ❌ Do NOT guess or rotate passwords repeatedly

### What the normal FleetConnect UI does after bootstrap

The existing `supabase.auth.signInWithPassword({email: dispatch@fleetconnect.be, password})` flow in `Paneel/admin-index.html` works unchanged. Founder logs in with the bootstrap password via the same browser-based login screen used by every other FleetConnect user.

### Production cutover (gated)

After Lux reviews the r053 evidence + Founder approves production cutover:
1. Founder provisions a hosted staging-equivalent Supabase (per r052 F1)
2. Founder runs the same bootstrap script against staging URL
3. PRIME runs E2E-A through E2E-E (r052 B3 matrix) in staging
4. Lux independently reviews and may declare MISSION COMPLETE only when safe
5. Founder chooses external communication after

This Founder authorization supersedes the prior blanket "no production auth mutation" only to the extent necessary to **prepare and prove a safe nonprod bootstrap path**. Production account creation/deployment remains gated until Lux reviews the implementation and the Founder explicitly approves the final production cutover.

---

**This is the ONE concrete Founder action.** Nothing else is required for r053.
