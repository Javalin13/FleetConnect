-- Phase G-L Wave 4: Verification queries
--
-- Mission   : 2026-08-29-fleetconnect-operational-recovery
-- Round     : r056 Phase G-L executable Wave 4 data/auth remap package
-- Run order : AFTER staging-transform import, BEFORE mapping-apply commit
--             AND AFTER mapping-apply, as the final green-light gate.
--
-- All queries are READ-ONLY. They do not modify state. Founder runs them
-- from a Founder-authenticated Dashboard SQL Editor or psql session.
--
-- ABORT thresholds (any non-zero count is a hard ABORT — rollback the
-- enclosing transaction):
--   V1: row-count parity (must be ±0; LOUD failure if legacy_source_count
--       is not provided to the function — founder fills it in once per table).
--   V2: zero auth-orphan FKs (target.user_id values that don't exist in
--       auth.users.id).
--   V3: zero business-FK orphans (customer_id/partner_id/assigned_driver_id
--       values that don't resolve to the parent table).
--   V4: zero unmapped legacy_user_id (rows that have legacy_user_id NOT NULL
--       but user_id still NULL after mapping-apply).
--   V5: zero dual-link (rows that have BOTH legacy_user_id AND user_id
--       pointing at the same auth.users.id, indicating a row was
--       re-imported twice — should be zero).

-- ===========================================================================
-- V0: additive migration sanity (run once before any data import)
-- ===========================================================================
SELECT
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('customers','partners','drivers','onderaannemers','bookings')
  AND column_name = 'legacy_user_id'
ORDER BY table_name;

-- EXPECT: 5 rows, all data_type = 'uuid', is_nullable = 'YES'.
-- FAIL:   any row missing or is_nullable = 'NO' — re-run the additive migration.

-- ===========================================================================
-- V1: row-count parity (founder compares to legacy counts captured at export)
-- ===========================================================================
SELECT 'customers'      AS tbl, count(*) AS target_count FROM public.customers
UNION ALL SELECT 'partners',       count(*) FROM public.partners
UNION ALL SELECT 'drivers',        count(*) FROM public.drivers
UNION ALL SELECT 'bookings',       count(*) FROM public.bookings
UNION ALL SELECT 'onderaannemers', count(*) FROM public.onderaannemers
ORDER BY tbl;

-- Founder compares each target_count to the legacy count captured at export.
-- ABORT if any target_count != legacy count (±0; no tolerance).

-- ===========================================================================
-- V2: zero auth-orphan FKs (post-mapping-apply)
-- ===========================================================================
SELECT 'orphan customers.user_id' AS issue, count(*) AS n
  FROM public.customers c
  WHERE c.user_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = c.user_id)
UNION ALL
SELECT 'orphan partners.user_id',  count(*)
  FROM public.partners p
  WHERE p.user_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p.user_id)
UNION ALL
SELECT 'orphan drivers.user_id',   count(*)
  FROM public.drivers d
  WHERE d.user_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = d.user_id)
UNION ALL
SELECT 'orphan bookings.user_id',  count(*)
  FROM public.bookings b
  WHERE b.user_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = b.user_id)
UNION ALL
SELECT 'orphan onderaannemers.user_id', count(*)
  FROM public.onderaannemers o
  WHERE o.user_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = o.user_id)
ORDER BY issue;

-- EXPECT: all counts = 0.
-- FAIL:   any count > 0 — orphan FK chain is broken; ABORT mapping-apply commit.

-- ===========================================================================
-- V3: zero business-FK orphans (post-mapping-apply)
-- ===========================================================================
SELECT 'orphan booking.customer_id' AS issue, count(*) AS n
  FROM public.bookings b
  WHERE b.customer_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.customers c WHERE c.id = b.customer_id)
UNION ALL
SELECT 'orphan booking.partner_id (resolved via email)', count(*)
  FROM public.bookings b
  WHERE b.partner_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.partners p WHERE p.id = b.partner_id)
UNION ALL
SELECT 'orphan booking.assigned_driver_id', count(*)
  FROM public.bookings b
  WHERE b.assigned_driver_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.drivers d WHERE d.id = b.assigned_driver_id)
UNION ALL
SELECT 'orphan driver.partner_id (resolved via email)', count(*)
  FROM public.drivers d
  WHERE d.partner_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.partners p WHERE p.id = d.partner_id)
ORDER BY issue;

-- EXPECT: all counts = 0.
-- FAIL:   any count > 0 — business FK chain broken; ABORT mapping-apply commit.

-- ===========================================================================
-- V4: unmapped legacy_user_id (rows that should have been linked but weren't)
-- ===========================================================================
SELECT 'unmapped customers.legacy_user_id' AS issue, count(*) AS n
  FROM public.customers c
  WHERE c.legacy_user_id IS NOT NULL
    AND c.user_id IS NULL
UNION ALL
SELECT 'unmapped partners.legacy_user_id',  count(*)
  FROM public.partners p
  WHERE p.legacy_user_id IS NOT NULL
    AND p.user_id IS NULL
UNION ALL
SELECT 'unmapped drivers.legacy_user_id',   count(*)
  FROM public.drivers d
  WHERE d.legacy_user_id IS NOT NULL
    AND d.user_id IS NULL
UNION ALL
SELECT 'unmapped bookings.legacy_user_id',  count(*)
  FROM public.bookings b
  WHERE b.legacy_user_id IS NOT NULL
    AND b.user_id IS NULL
UNION ALL
SELECT 'unmapped onderaannemers.legacy_user_id', count(*)
  FROM public.onderaannemers o
  WHERE o.legacy_user_id IS NOT NULL
    AND o.user_id IS NULL
ORDER BY issue;

-- EXPECT: all counts = 0 (after mapping-apply runs to completion).
-- FAIL:   any count > 0 — at least one legacy row has no corresponding
--         new auth user; investigate before commit.

-- ===========================================================================
-- V5: unmapped-user report (drill-down for any V4 non-zero)
-- ===========================================================================
SELECT id, email, legacy_user_id, user_id, name
  FROM public.customers
  WHERE legacy_user_id IS NOT NULL AND user_id IS NULL
UNION ALL
SELECT id::text, email, legacy_user_id, user_id, name
  FROM public.partners
  WHERE legacy_user_id IS NOT NULL AND user_id IS NULL
UNION ALL
SELECT id::text, email, legacy_user_id, user_id, name
  FROM public.drivers
  WHERE legacy_user_id IS NOT NULL AND user_id IS NULL
UNION ALL
SELECT id, email, legacy_user_id, user_id, name
  FROM public.bookings
  WHERE legacy_user_id IS NOT NULL AND user_id IS NULL
ORDER BY email NULLS LAST, id
LIMIT 500;

-- Use the email column to drive Founder-side Dashboard user creation
-- for any missing mappings BEFORE re-running the mapping-apply step.

-- ===========================================================================
-- V6: zero dual-link (sanity: no row has both legacy and target pointing at
--     the same auth.users.id, which would indicate a row was re-imported
--     with the same UUID by accident)
-- ===========================================================================
SELECT 'dual-link customers' AS issue, count(*) AS n
  FROM public.customers
  WHERE legacy_user_id IS NOT NULL
    AND user_id IS NOT NULL
    AND legacy_user_id = user_id
UNION ALL
SELECT 'dual-link partners',  count(*)
  FROM public.partners
  WHERE legacy_user_id IS NOT NULL
    AND user_id IS NOT NULL
    AND legacy_user_id = user_id
UNION ALL
SELECT 'dual-link drivers',   count(*)
  FROM public.drivers
  WHERE legacy_user_id IS NOT NULL
    AND user_id IS NOT NULL
    AND legacy_user_id = user_id
UNION ALL
SELECT 'dual-link bookings',  count(*)
  FROM public.bookings
  WHERE legacy_user_id IS NOT NULL
    AND user_id IS NOT NULL
    AND legacy_user_id = user_id
ORDER BY issue;

-- EXPECT: all counts = 0. Cross-project auth.users.id portability is not a
-- documented Supabase feature; legacy IDs belong to the legacy project's
-- auth schema. If a count > 0 here, the target-created IDs coincidentally
-- matched the legacy IDs; this should not happen under Option C1 Dashboard
-- creation, but is a sanity check.
