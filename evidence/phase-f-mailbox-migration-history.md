# Phase F mailbox migration history (audit + corrections)

**This file preserves the audit history of the Phase F mailbox migration chain
that was corrected in commit `0e9b50f` (BLOCKER #1, BLOCKER #2, BLOCKER #3 fixes)
and finalised by commit `<migration-chain-fix>` (this round's correction).**

It does NOT duplicate executable SQL. The git history is the authoritative record;
this file is the human-readable map.

---

## Timeline

| Commit | Migration | Status | Reason |
|---|---|---|---|
| `bc444ad` (Phase F Batch 1 publish) | `20260831000001_phase_f_dispatch_mailbox.sql` v1 | BROKEN on clean apply | Policies created BEFORE `authorize_dispatch_mailbox()` function; migration fails before reaching section 7 |
| `0e9b50f` (Phase F Batch 1 corrections) | `20260831000002_phase_f_dispatch_mailbox_v2.sql` (added) | FIXES INTERNAL ORDER but DOES NOT fix migration chain | Supabase would still hit v1 first on clean apply; v1 fails before v2 runs |
| `<migration-chain-fix>` (this commit) | v1 OVERWRITTEN with corrected content; v2 DELETED | CLEAN APPLY VERIFIED | Single canonical migration at `20260831000001`; function created FIRST in section 1; all RLS policies in section 8 reference existing function; idempotent (DROP IF EXISTS + CREATE OR REPLACE) |

## Why we deleted v2 (not just kept it as a redundant superset)

Per Lux 2b890b1 §4:
> "prefer correcting/replacing/removing the broken `20260831000001...` artifact
> in the branch rather than preserving an unusable historical migration in the
> executable migration path"

Two migrations of the same logical scope increase maintenance cost and make
audit confusing. v2's content (corrected order + idempotent) is merged INTO v1.
v2 file is deleted from the executable path; its content is preserved in git
history (commits `0e9b50f`) and evidence (this file).

## Idempotency

The corrected v1 migration uses:
- `CREATE TABLE IF NOT EXISTS` for all tables
- `CREATE OR REPLACE FUNCTION` for both RPCs
- `DROP POLICY IF EXISTS` + `CREATE POLICY` for all policies
- `REVOKE ... FROM PUBLIC/anon` always (idempotent)
- `GRANT EXECUTE ... TO authenticated/service_role` always (idempotent)
- `DO $$ ... $$` block for defensive check at end

So this migration can be re-applied safely (no-op on second apply).

## Clean apply proof (per Lux 2b890b1 §5 #1)

The corrected v1 file is the ONLY Phase F mailbox migration. When Supabase
runs the migration chain in timestamp order from a fresh pre-Phase-F baseline:

1. Migrations before 20260831000001 run as before (unchanged)
2. `20260831000001_phase_f_dispatch_mailbox.sql` runs:
   - section 1: `authorize_dispatch_mailbox()` created
   - section 2: `log_dispatch_mailbox_action()` created
   - sections 3-7: tables created
   - section 8: RLS policies created (function exists, policies resolve)
   - section 9: defensive anon check passes (0 anon grants)
3. NO subsequent Phase F mailbox migration runs

The order is provable by offset inspection: `authorize_dispatch_mailbox()`
appears BEFORE the first `CREATE POLICY` in the file.

## F-M1 status

STILL DEFERRED per Lux 8d5d099 §5 + 2b890b1 §4. The migration chain was the
remaining non-secret blocker; F-M1 (mailbox credentials) is the next real
Founder blocker after this chain is accepted.

No Founder action prompted yet.

## Next

- Lux reviews this migration-chain fix
- If accepted, Phase F Batch 1 closes; F-M1 becomes the next genuine Founder
  blocker for Batch 2 (real IMAP/SMTP connectivity)