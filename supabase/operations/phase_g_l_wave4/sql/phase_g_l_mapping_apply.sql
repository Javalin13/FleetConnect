-- Phase G-L Wave 4: Pure-SQL mapping apply
--
-- Mission   : 2026-08-29-fleetconnect-operational-recovery
-- Round     : r056 Phase G-L executable Wave 4 data/auth remap package
-- Predecessors:
--   - supabase/migrations/20260902000001_phase_g_l_additive_legacy_user_id_audit_column.sql
--   - supabase/operations/phase_g_l_wave4/sql/phase_g_l_staging_create.sql
--   - supabase/operations/phase_g_l_wave4/sql/phase_g_l_staging_transform.sql
--   - Founder-authenticated Dashboard user creation (Option C1 only per
--     Lux 39ca1a0 §5), recorded in a Founder-local mapping CSV
--
-- PURPOSE:
--   Apply the deterministic old -> new target user_id mapping to the four
--   auth-linked app tables, matching on legacy_user_id.
--
-- PURE-SQL CONTRACT (BLOCKER 5 fix from Lux cfb0e9b §5):
--   - NO \copy inside this file. \copy is a psql meta-command, not SQL,
--     and must not be embedded in a migration SQL file.
--   - NO hard-coded local path.
--   - NO TEMP TABLE schema-qualified into an ordinary schema.
--   - This file consumes a temp table ALREADY created and loaded by the
--     Founder runner (see supabase/operations/phase_g_l_wave4/runner/run_wave4.sh).
--
-- EXECUTION MODEL:
--   Founder-authenticated psql -c "\i phase_g_l_mapping_apply.sql" inside
--   a Founder runner-managed single transaction. The runner has already
--   created and loaded the session-scoped TEMP TABLE user_id_mapping
--   before invoking this file.

-- ===========================================================================
-- Hard preflight: every legacy_user_id in user_id_mapping must reference
-- an existing target auth.users.id. ABORT otherwise.
-- ===========================================================================
DO $$
DECLARE bad INT;
BEGIN
  SELECT count(*) INTO bad
  FROM pg_temp.user_id_mapping m
  WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = m.new_user_id);
  IF bad > 0 THEN
    RAISE EXCEPTION 'Phase G-L mapping-apply ABORT: % mapping rows reference non-existent new_user_id', bad;
  END IF;
END$$;

-- ===========================================================================
-- Apply to customers
-- ===========================================================================
UPDATE public.customers c
SET user_id = m.new_user_id
FROM pg_temp.user_id_mapping m
WHERE c.legacy_user_id = m.legacy_user_id
  AND c.user_id IS NULL;

-- ===========================================================================
-- Apply to partners
-- ===========================================================================
UPDATE public.partners p
SET user_id = m.new_user_id
FROM pg_temp.user_id_mapping m
WHERE p.legacy_user_id = m.legacy_user_id
  AND p.user_id IS NULL;

-- ===========================================================================
-- Apply to drivers
-- ===========================================================================
UPDATE public.drivers d
SET user_id = m.new_user_id
FROM pg_temp.user_id_mapping m
WHERE d.legacy_user_id = m.legacy_user_id
  AND d.user_id IS NULL;

-- ===========================================================================
-- Apply to bookings
-- ===========================================================================
UPDATE public.bookings b
SET user_id = m.new_user_id
FROM pg_temp.user_id_mapping m
WHERE b.legacy_user_id = m.legacy_user_id
  AND b.user_id IS NULL;

-- ===========================================================================
-- In-transaction invariant verification (BLOCKER 2 fix)
-- ===========================================================================

-- V2: zero auth-orphan FKs post-mapping
DO $$
DECLARE
  orphan_customers INT;
  orphan_partners  INT;
  orphan_drivers   INT;
  orphan_bookings  INT;
BEGIN
  SELECT count(*) INTO orphan_customers FROM public.customers c
    WHERE c.user_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = c.user_id);
  IF orphan_customers > 0 THEN
    RAISE EXCEPTION 'V2 FAIL: % orphan customers.user_id post-mapping', orphan_customers;
  END IF;

  SELECT count(*) INTO orphan_partners FROM public.partners p
    WHERE p.user_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p.user_id);
  IF orphan_partners > 0 THEN
    RAISE EXCEPTION 'V2 FAIL: % orphan partners.user_id post-mapping', orphan_partners;
  END IF;

  SELECT count(*) INTO orphan_drivers FROM public.drivers d
    WHERE d.user_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = d.user_id);
  IF orphan_drivers > 0 THEN
    RAISE EXCEPTION 'V2 FAIL: % orphan drivers.user_id post-mapping', orphan_drivers;
  END IF;

  SELECT count(*) INTO orphan_bookings FROM public.bookings b
    WHERE b.user_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = b.user_id);
  IF orphan_bookings > 0 THEN
    RAISE EXCEPTION 'V2 FAIL: % orphan bookings.user_id post-mapping', orphan_bookings;
  END IF;
END$$;

-- V4: zero unmapped legacy_user_id (only counting rows where mapping was expected)
-- Rows that had legacy_user_id IS NULL in the source import are ignored.
-- The Founder should document intentionally-unmapped rows in the completion report.
DO $$
DECLARE
  unmapped_customers INT;
  unmapped_partners  INT;
  unmapped_drivers   INT;
  unmapped_bookings  INT;
BEGIN
  SELECT count(*) INTO unmapped_customers FROM public.customers
    WHERE legacy_user_id IS NOT NULL AND user_id IS NULL;
  IF unmapped_customers > 0 THEN
    RAISE EXCEPTION 'V4 FAIL: % unmapped customers.legacy_user_id post-mapping', unmapped_customers;
  END IF;

  SELECT count(*) INTO unmapped_partners FROM public.partners
    WHERE legacy_user_id IS NOT NULL AND user_id IS NULL;
  IF unmapped_partners > 0 THEN
    RAISE EXCEPTION 'V4 FAIL: % unmapped partners.legacy_user_id post-mapping', unmapped_partners;
  END IF;

  SELECT count(*) INTO unmapped_drivers FROM public.drivers
    WHERE legacy_user_id IS NOT NULL AND user_id IS NULL;
  IF unmapped_drivers > 0 THEN
    RAISE EXCEPTION 'V4 FAIL: % unmapped drivers.legacy_user_id post-mapping', unmapped_drivers;
  END IF;

  SELECT count(*) INTO unmapped_bookings FROM public.bookings
    WHERE legacy_user_id IS NOT NULL AND user_id IS NULL;
  IF unmapped_bookings > 0 THEN
    RAISE EXCEPTION 'V4 FAIL: % unmapped bookings.legacy_user_id post-mapping', unmapped_bookings;
  END IF;
END$$;

-- V5: zero dual-link (legacy_user_id == user_id would mean target coincidentally
-- matched legacy, which would only happen by accident — cross-project auth.users.id
-- portability is not a documented Supabase feature per Lux 39ca1a0 §5)
DO $$
DECLARE
  dual_customers INT;
  dual_partners  INT;
  dual_drivers   INT;
  dual_bookings  INT;
BEGIN
  SELECT count(*) INTO dual_customers FROM public.customers
    WHERE legacy_user_id IS NOT NULL AND user_id IS NOT NULL AND legacy_user_id = user_id;
  IF dual_customers > 0 THEN
    RAISE EXCEPTION 'V5 FAIL: % dual-link customers (legacy_user_id = user_id)', dual_customers;
  END IF;

  SELECT count(*) INTO dual_partners FROM public.partners
    WHERE legacy_user_id IS NOT NULL AND user_id IS NOT NULL AND legacy_user_id = user_id;
  IF dual_partners > 0 THEN
    RAISE EXCEPTION 'V5 FAIL: % dual-link partners (legacy_user_id = user_id)', dual_partners;
  END IF;

  SELECT count(*) INTO dual_drivers FROM public.drivers
    WHERE legacy_user_id IS NOT NULL AND user_id IS NOT NULL AND legacy_user_id = user_id;
  IF dual_drivers > 0 THEN
    RAISE EXCEPTION 'V5 FAIL: % dual-link drivers (legacy_user_id = user_id)', dual_drivers;
  END IF;

  SELECT count(*) INTO dual_bookings FROM public.bookings
    WHERE legacy_user_id IS NOT NULL AND user_id IS NOT NULL AND legacy_user_id = user_id;
  IF dual_bookings > 0 THEN
    RAISE EXCEPTION 'V5 FAIL: % dual-link bookings (legacy_user_id = user_id)', dual_bookings;
  END IF;
END$$;

DO $$ BEGIN RAISE NOTICE 'Phase G-L mapping-apply OK: V2 + V4 + V5 invariants all green'; END $$;
