#!/bin/bash
# r056 Phase G apply_manifest.sh
# Apply FleetConnect migrations in canonical deterministic order with strict fail-fast.
# Generated 2026-08-31 per Lux 2195825 §3 + §4.

set -euo pipefail

if [ -z "${DB_URL:-}" ]; then
  echo "ERROR: DB_URL environment variable required"
  echo "Example: DB_URL=postgresql://user:pass@localhost:5432/fleetconnect_test ./apply_manifest.sh"
  exit 1
fi

PSQL="psql ${DB_URL} -v ON_ERROR_STOP=1 --no-psqlrc -X -q"

# Canonical apply order (per evidence/r056-phase-g-migration-manifest.md)
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
  "20260830000008_phase_g_greenfield_luchthavenlaan_cleanup.sql"
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
  if [ ! -f "supabase/migrations/$f" ]; then
    echo "ERROR: missing file: supabase/migrations/$f"
    exit 1
  fi
done

echo "Applying ${#MANIFEST[@]} migrations in canonical order with strict fail-fast..."
echo ""

for f in "${MANIFEST[@]}"; do
  echo "[$(date +%H:%M:%S)] Applying: $f"
  $PSQL -f "supabase/migrations/$f" 2>&1 | tail -3
  if [ $? -ne 0 ]; then
    echo ""
    echo "FAILED at: $f"
    echo "Aborting with strict fail-fast (ON_ERROR_STOP=1)"
    exit 1
  fi
done

echo ""
echo "=========================================="
echo "All ${#MANIFEST[@]} migrations applied successfully."
echo "=========================================="
