# r056 Phase G Migration Manifest (Canonical Apply Order)

**Date:** 2026-08-31
**Author:** PRIME (r056 Phase G, post Lux 2195825 acceptance)

## Purpose

Per Lux 2195825 §3 + §4: the historical SQL set is NOT a complete greenfield bootstrap, and the unprefixed `phase4_identity_closure.sql` file creates ordering ambiguity (lexicographic vs timestamp ordering). This manifest establishes the **deterministic** canonical apply order for greenfield reconstruction.

## File Count

**File count:** 51 historical / existing SQL files in
`supabase/migrations/`:
- 1 NEW canonical greenfield baseline (added in this round, cc10c8f)
- 48 pre-existing timestamped migrations
- 1 unprefixed `phase4_identity_closure.sql`
- 1 Phase F migration

**Total reconstruction steps = 52** (51 historical + 1 new baseline).
The term "51-file manifest" used in earlier evidence is shorthand
for the 51 historical files; the new baseline is added at position
0 in the apply order, making the full chain 52 steps.

## Canonical Apply Order

The apply order is **NOT** filename lexicographic order (which would put the unprefixed `phase4_identity_closure.sql` at the end by accident). The canonical order is:

1. **Baseline FIRST** (file 0) — bootstraps foundational tables (customers, partners, drivers, bookings, booking_lifecycle_events) + auth stubs + roles + pgcrypto
2. **48 timestamped migrations in filename order** (files 1-48)
3. **Unprefixed `phase4_identity_closure.sql`** (file 49) — applies after r056 RPCs that reference customers/bookings
4. **Phase F migration LAST** (file 50) — needs auth schema but self-contained for its 5 mailbox tables

## Exact File List (51 files, in canonical order)

```
[0]  20260831000000_phase_g_canonical_greenfield_baseline.sql         [NEW]
[1]  20260521000000_phase3_payments.sql
[2]  20260602000000_phase5_live_remediation.sql
[3]  20260602020000_public_booking_id_generation.sql
[4]  20260603010000_operator_partner_driver_creation_rpcs.sql
[5]  20260611000000_account_requests.sql
[6]  20260611010000_phase_a44_lifecycle_hardening.sql
[7]  20260611020000_phase_a441_live_validation_hotfixes.sql
[8]  20260611030000_customer_email_lifecycle_refinement.sql
[9]  20260612000000_phase_a443_customer_auth_routing_workflows.sql
[10] 20260612010000_phase_a444_account_customer_conversion.sql
[11] 20260612020000_phase_a444_dashboard_lifecycle.sql
[12] 20260612030000_phase_a444_review_workflow.sql
[13] 20260612040000_phase_a444_live_blocker_hardening.sql
[14] 20260612050000_phase_a444_final_certification_blockers.sql
[15] 20260612060000_phase_a444_live_retest_blockers.sql
[16] 20260613000000_phase_a444_dashboard_visibility_repair.sql
[17] 20260613010000_phase_a444_customer_self_service.sql
[18] 20260615010000_cycle2_step09_review_visibility.sql
[19] 20260616010000_idempotent_link_and_portal_access.sql
[20] 20260616020000_onderaannemers_policies.sql
[21] 20260616030000_partner_invite_with_auth_user.sql
[22] 20260617010000_cert_cycle_7_data_cleanup.sql
[23] 20260617020000_cert_cycle_8_partner_driver_portals.sql
[24] 20260617030000_segment1_cleanup.sql
[25] 20260617040000_segment2_dedup_and_updates.sql
[26] 20260619010000_partner_driver_pwa_mvp.sql
[27] 20260619020000_partner_pwa_registration_requests.sql
[28] 20260619030000_fix_partner_driver_approval_pgcrypto.sql
[29] 20260619040000_unified_account_duplicate_check.sql
[30] 20260619060000_partner_delete_dedup_backend.sql
[31] 20260619070000_fix_partner_update_delete_rpc.sql
[32] 20260619080000_operator_bulk_assign_bookings.sql
[33] 20260619190000_fix_dashboard_update_rpc_returns.sql
[34] 20260620090000_customer_account_dashboard_management.sql
[35] 20260620193000_partner_driver_pwa_role_separation.sql
[36] 20260621000000_add_customer_username.sql
[37] 20260623000000_configurable_auto_assignment.sql
[38] 20260624000000_centralized_pricing_engine.sql
[39] 20260625000000_revert_to_manual_dispatch.sql
[40] 20260827000000_restore_manual_dispatch_lifecycle.sql
[41] 20260830000009_narrow_luchthavenlaan_pricing_fix.sql
[42] 20260830000010_luchthavenlaan_pricing_regression_guard.sql
[43] 20260830000011_auto_assign_lifecycle.sql
[44] 20260830000012_timeout_scanner.sql
[45] 20260830000013_admin_role_authorization_rpc.sql
[46] 20260830000014_admin_role_authorization_rpc_v2.sql
[47] 20260830000015_long_distance_rate_1_80_per_km.sql
[48] 20260830000016_rollback_1_80km_to_2_00km.sql
[49] phase4_identity_closure.sql                                     [unprefixed]
[50] 20260831000001_phase_f_dispatch_mailbox.sql                     [Phase F]
```

## Why the Baseline Must Be File 0

The historical migration chain references these tables but never CREATES them:
- `customers` — referenced in 18 migrations + frontend
- `partners` — referenced in 21 migrations + `authorize_admin_role()` v2
- `drivers` — referenced in 20 migrations + frontend
- `bookings` — referenced in 30 migrations + frontend + 4 edge functions
- `booking_lifecycle_events` — referenced in migration `20260830000012_timeout_scanner.sql`

Without the baseline, the historical chain FAILS at file 1 or later with `relation "customers" does not exist` (or similar).

## Why `phase4_identity_closure.sql` Goes at File 49

The unprefixed file:
- ALTER TABLE customers + bookings (assumes these exist; baseline #0 provides them)
- Creates RLS policies on customers/bookings (must be after migration chain that defines business logic on these tables)
- Creates trigger sync_booking_user_id (must be after r055 booking RPCs that insert into bookings)

Lexicographic order would put it AFTER file 50 (Phase F) by accident because:
- `20260831...` < `phase4...` (digits come before 'p' in ASCII)
- This means the unprefixed file accidentally runs LAST if sorted by filename

But Phase F (file 50) is self-contained for its 5 mailbox tables and DOES NOT depend on phase4_identity_closure. Either order works. We choose: phase4 BEFORE Phase F so the Phase F mailbox policies are the LAST policies created in the chain.

## Why NOT Rename `phase4_identity_closure.sql`

- It is a historical migration; renaming changes production deployment history
- Per Lux 2195825 §4: "Decide and document its factual dependency position"
- This manifest documents the canonical position WITHOUT renaming the file
- The deterministic apply is enforced by the **apply script** (not by filename lex order)

## Apply Script (deterministic, strict fail-fast)

```bash
#!/bin/bash
# apply_manifest.sh — applies migrations in canonical order with strict fail-fast
set -euo pipefail
DB_URL="${DB_URL:?DB_URL required (e.g. postgresql://user:pass@host:port/dbname)}"
PSQL="psql ${DB_URL} -v ON_ERROR_STOP=1 --no-psqlrc -X"

MANIFEST=(
  "20260831000000_phase_g_canonical_greenfield_baseline.sql"
  "20260521000000_phase3_payments.sql"
  "20260602000000_phase5_live_remediation.sql"
  "20260602020000_public_booking_id_generation.sql"
  "20260603010000_operator_partner_driver_creation_rpcs.sql"
  "20260611000000_account_requests.sql"
  "20260611010000_phase_a44_lifecycle_hardening.sql"
  "20260611020000_phase_a441_live_validation_hotfixes.sql"
  "20260611030000_customer_email_lifecycle_refinement.sql"
  "20260612000000_phase_a443_customer_auth_routing_workflows.sql"
  "20260612010000_phase_a444_account_customer_conversion.sql"
  "20260612020000_phase_a444_dashboard_lifecycle.sql"
  "20260612030000_phase_a444_review_workflow.sql"
  "20260612040000_phase_a444_live_blocker_hardening.sql"
  "20260612050000_phase_a444_final_certification_blockers.sql"
  "20260612060000_phase_a444_live_retest_blockers.sql"
  "20260613000000_phase_a444_dashboard_visibility_repair.sql"
  "20260613010000_phase_a444_customer_self_service.sql"
  "20260615010000_cycle2_step09_review_visibility.sql"
  "20260616010000_idempotent_link_and_portal_access.sql"
  "20260616020000_onderaannemers_policies.sql"
  "20260616030000_partner_invite_with_auth_user.sql"
  "20260617010000_cert_cycle_7_data_cleanup.sql"
  "20260617020000_cert_cycle_8_partner_driver_portals.sql"
  "20260617030000_segment1_cleanup.sql"
  "20260617040000_segment2_dedup_and_updates.sql"
  "20260619010000_partner_driver_pwa_mvp.sql"
  "20260619020000_partner_pwa_registration_requests.sql"
  "20260619030000_fix_partner_driver_approval_pgcrypto.sql"
  "20260619040000_unified_account_duplicate_check.sql"
  "20260619060000_partner_delete_dedup_backend.sql"
  "20260619070000_fix_partner_update_delete_rpc.sql"
  "20260619080000_operator_bulk_assign_bookings.sql"
  "20260619190000_fix_dashboard_update_rpc_returns.sql"
  "20260620090000_customer_account_dashboard_management.sql"
  "20260620193000_partner_driver_pwa_role_separation.sql"
  "20260621000000_add_customer_username.sql"
  "20260623000000_configurable_auto_assignment.sql"
  "20260624000000_centralized_pricing_engine.sql"
  "20260625000000_revert_to_manual_dispatch.sql"
  "20260827000000_restore_manual_dispatch_lifecycle.sql"
  "20260830000009_narrow_luchthavenlaan_pricing_fix.sql"
  "20260830000010_luchthavenlaan_pricing_regression_guard.sql"
  "20260830000011_auto_assign_lifecycle.sql"
  "20260830000012_timeout_scanner.sql"
  "20260830000013_admin_role_authorization_rpc.sql"
  "20260830000014_admin_role_authorization_rpc_v2.sql"
  "20260830000015_long_distance_rate_1_80_per_km.sql"
  "20260830000016_rollback_1_80km_to_2_00km.sql"
  "phase4_identity_closure.sql"
  "20260831000001_phase_f_dispatch_mailbox.sql"
)

for f in "${MANIFEST[@]}"; do
  echo "Applying: $f"
  $PSQL -f "supabase/migrations/$f" || { echo "FAILED at $f"; exit 1; }
done
echo "All 51 migrations applied successfully."
```

The script will be saved to `supabase/apply_manifest.sh` in this PR.

## What This Manifest Does NOT Do

- Does NOT modify any existing migration file content
- Does NOT rename `phase4_identity_closure.sql`
- Does NOT touch either Supabase project (no remote writes)
- Does NOT commit any credentials
- Does NOT include the anon key in the script
