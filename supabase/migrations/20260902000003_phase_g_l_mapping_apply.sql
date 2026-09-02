-- Phase G-L Wave 4: Apply deterministic old → new `user_id` mapping
--
-- Mission   : 2026-08-29-fleetconnect-operational-recovery
-- Round     : r056 Phase G-L executable Wave 4 data/auth remap package
-- Predecessors:
--   - 20260902000001_phase_g_l_legacy_user_id_audit_column.sql
--   - 20260902000002_phase_g_l_staging_transform_import.sql
--   - Founder-authenticated Dashboard user creation + recorded mapping artifact
--     (evidence/r056-phase-g-l-auth-user-id-mapping.csv; see
--      evidence/r056-phase-g-l-founder-execution-runbook.md §B)
--
-- PURPOSE:
--   Apply the recorded old → new `auth.users.id` mapping to the four
--   auth-linked app tables (customers, partners, drivers, bookings),
--   matching on `legacy_user_id`. After this step:
--     - public.<table>.user_id  : the NEW auth.users.id created via Dashboard
--     - public.<table>.legacy_user_id : the legacy auth.users.id (audit)
--
-- EXECUTION MODEL:
--   Founder-authenticated psql in a Founder-local terminal session.
--   PRIME does NOT execute this file on the live target project.
--   The mapping CSV (evidence/r056-phase-g-l-auth-user-id-mapping.csv) is
--   held by the Founder locally; PRIME does NOT receive its contents.

-- ===========================================================================
-- Step 1: Temp table for the mapping (loaded from Founder-held CSV)
-- ===========================================================================
DROP TABLE IF EXISTS staging.user_id_mapping;
CREATE TEMP TABLE staging.user_id_mapping (
    legacy_user_id UUID NOT NULL,
    new_user_id    UUID NOT NULL,
    re_onboard_status TEXT
);

\copy staging.user_id_mapping (legacy_user_id, new_user_id, re_onboard_status) FROM '/secure/path/r056-phase-g-l-auth-user-id-mapping.csv' CSV HEADER

-- Sanity: every mapping row must reference an existing target auth.users.id.
-- A non-zero count here is an ABORT condition (rollback the entire session).
DO $$
DECLARE
  bad INT;
BEGIN
  SELECT count(*) INTO bad
  FROM staging.user_id_mapping m
  WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = m.new_user_id);
  IF bad > 0 THEN
    RAISE EXCEPTION 'Phase G-L mapping-apply ABORT: % mapping rows reference non-existent new_user_id', bad;
  END IF;
END$$;

-- ===========================================================================
-- Step 2: Apply to customers
-- ===========================================================================
UPDATE public.customers c
SET user_id = m.new_user_id
FROM staging.user_id_mapping m
WHERE c.legacy_user_id = m.legacy_user_id
  AND c.user_id IS NULL;            -- idempotent: only update rows not yet linked

-- ===========================================================================
-- Step 3: Apply to partners
-- ===========================================================================
UPDATE public.partners p
SET user_id = m.new_user_id
FROM staging.user_id_mapping m
WHERE p.legacy_user_id = m.legacy_user_id
  AND p.user_id IS NULL;

-- ===========================================================================
-- Step 4: Apply to drivers
-- ===========================================================================
UPDATE public.drivers d
SET user_id = m.new_user_id
FROM staging.user_id_mapping m
WHERE d.legacy_user_id = m.legacy_user_id
  AND d.user_id IS NULL;

-- ===========================================================================
-- Step 5: Apply to bookings
-- ===========================================================================
UPDATE public.bookings b
SET user_id = m.new_user_id
FROM staging.user_id_mapping m
WHERE b.legacy_user_id = m.legacy_user_id
  AND b.user_id IS NULL;

-- ===========================================================================
-- Step 6: COMMIT only after verification queries (verification-queries.sql)
--           return zero residual issues.
-- ===========================================================================
-- COMMIT;   -- run AFTER review of evidence/r056-phase-g-l-verification-queries.sql
-- ROLLBACK; -- if any verification query returns non-zero issues
