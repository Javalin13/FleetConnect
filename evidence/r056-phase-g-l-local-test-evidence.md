# Phase G-L Wave 4 — Local Strict Test Evidence

**Date:** 2026-09-02
**Mission:** `2026-08-29-fleetconnect-operational-recovery`
**Round:** r056 Phase G-L executable Wave 4 data/auth remap package
**Test harness:** `supabase/local_harness/run_phase_g_l_wave4_tests.sh`
**Disposable target:** PostgreSQL database `phase_g_l_wave4_test` (dropped and recreated on every run)

## Result: **ALL TESTS PASSED** ✅

## Summary

| Check | Result |
|---|---|
| Additive migration apply | ✅ PASS (5 tables gained `legacy_user_id UUID NULL`) |
| V0 (additive sanity) | ✅ PASS (5/5 tables have legacy_user_id, all `is_nullable='YES'`) |
| Fixture loading | ✅ PASS (3 customers + 2 partners + 2 drivers + 4 bookings = 11 rows) |
| Staging-transform import | ✅ PASS (11 rows inserted; legacy_user_id captured; target user_id NULL) |
| V1 (row-count parity) | ✅ PASS (matches fixture counts exactly: 3/2/2/4) |
| V3 (business-FK orphans) | ✅ PASS (all counts = 0) |
| V5 (dual-link sanity) | ✅ PASS (all counts = 0) |
| Mapping apply | ✅ PASS (3 customers + 2 partners + 2 drivers + 4 bookings = 11 rows updated) |
| V2 (auth-orphan FKs post-mapping) | ✅ PASS (all counts = 0) |
| V4 (unmapped legacy_user_id post-mapping) | ✅ PASS (all counts = 0) |
| Final assertion (linked vs total) | ✅ PASS (customers 3/3, partners 2/2, drivers 2/2, bookings 4/4) |
| partner_id resolution (drivers.partner_id) | ✅ PASS (0 NULLs) |
| partner_id resolution (bookings.partner_id) | ✅ PASS (0 NULLs) |
| assigned_driver_id resolution | ✅ PASS (0 NULLs) |
| customer_id resolution | ✅ PASS (0 NULLs) |
| Idempotency check | ✅ PASS (re-running UPDATE on already-mapped rows affects 0 rows) |

## Test artifacts

The test harness stages its SQL+CSV inputs in `/tmp/phase_g_l_test_stage/` (with
`chmod 644`) because the `postgres` OS user cannot read files under
`/home/prime/`. The full stdout of one green run is captured at:

`evidence/r056-phase-g-l-local-test-evidence.txt` (129 lines)

## Fixture data (representative legacy UUIDs)

| Legacy UUID pattern | Used for | Source |
|---|---|---|
| `11111111-...` | Alice (customer) | legacy alice@legacy.example |
| `22222222-...` | Bob (customer) | legacy bob@legacy.example |
| `33333333-...` | Carol (customer) | legacy carol@legacy.example |
| `44444444-...` | Partner A | legacy partner-a@legacy.example |
| `55555555-...` | Partner B | legacy partner-b@legacy.example |
| `66666666-...` | Driver A | legacy driver-a@legacy.example |
| `77777777-...` | Driver B | legacy driver-b@legacy.example |

These are clearly synthetic test UUIDs; no production user is affected.

## Mapping fixture (deterministic old → new)

| Legacy UUID | New UUID | Notes |
|---|---|---|
| `11111111-...` | `cccccccc-...` | Alice |
| `22222222-...` | `dddddddd-...` | Bob |
| `33333333-...` | `eeeeeeee-...` | Carol |
| `44444444-...` | `ffffffff-...` | Partner A |
| `55555555-...` | `99999999-...` | Partner B |
| `66666666-...` | `88888888-...` | Driver A |
| `77777777-...` | `7a7a7a7a-...` | Driver B (intentionally different from legacy to test V5 dual-link detection) |

## Wave 4 contract verified by this test

1. **Additive migration is idempotent** (V0). Re-runs of `20260902000001` produce no error.
2. **Staging/transform import succeeds** with FK constraints intact (Step 4).
3. **`legacy_user_id` is captured** as the audit copy of legacy auth UUIDs (visible in V0/V5 queries).
4. **Target `user_id` starts NULL** post-import (V2 returns 0 orphans; V1 returns 0 non-null).
5. **Business FKs are resolved** during the transform (V3 zero orphans) — partner_id via email; assigned_driver_id via legacy UUID; customer_id via TEXT.
6. **Mapping apply is idempotent** (UPDATE with `user_id IS NULL` predicate).
7. **V2 (post-mapping auth-FK orphan) is zero** — every target user_id resolves to an existing auth.users row.
8. **V4 (unmapped legacy_user_id) is zero** — every legacy_user_id has a corresponding mapping row.
9. **V5 (dual-link) is zero** — target-created IDs differ from legacy IDs, confirming cross-project auth.users.id portability is not assumed (per Lux 39ca1a0 §5).

## Edge cases NOT covered by this test (documented for future review)

1. **partner_legacy_pk → partner.id resolution via email collision.** If two legacy partners share an email, the LEFT JOIN picks one arbitrarily. Production data should be reviewed for duplicates; the runbook notes that the founder should validate email uniqueness before Wave 4.
2. **Legacy `auth.users` with no `email`.** Dashboard user creation requires an email. Test assumes every legacy user has an email.
3. **`onderaannemers` is DORMANT in this test** (zero rows). If production confirms it is active, the additive migration still applies (idempotent), and the same staging-transform pattern extends with a sixth table in the SQL files.
4. **RLS policies on the canonical tables.** Phase G-L does not modify RLS. The test does not exercise RLS, but the canonical greenfield baseline already enables RLS on the foundational tables via phase4_identity_closure.sql and later migrations.
5. **Concurrent writers.** Wave 4 is a one-shot cutover; concurrent application writes during the import window are not modeled. The founder pauses new public bookings during the Wave 4 execution per the runbook §0.
6. **NULL `legacy_user_id` rows.** A small fraction of legacy rows may have `user_id IS NULL` in legacy (e.g., unverified accounts). The test does not include these. The verification queries handle this case correctly: V4 only counts rows where `legacy_user_id IS NOT NULL AND user_id IS NULL`. Rows with both NULL are ignored.

## Reproducibility

```bash
cd /home/prime/fleetconnect-integration-r056
bash supabase/local_harness/run_phase_g_l_wave4_tests.sh
```

Exit code 0 = PASS. Any non-zero exit code is a hard failure with a specific abort reason (10/11/12/13/14/20/30).

The disposable test DB `phase_g_l_wave4_test` is dropped and recreated on every run.
