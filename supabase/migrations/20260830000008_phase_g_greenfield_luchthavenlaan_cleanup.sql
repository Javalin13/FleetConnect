-- =====================================================================
-- r056 Phase G: Interim cleanup migration (NARROW LUCHTHAVENLAAN FIX GATE)
-- =====================================================================
--
-- PURPOSE:
--   Greenfield-only interim step that runs BETWEEN
--   `20260624000000_centralized_pricing_engine.sql` and
--   `20260830000009_narrow_luchthavenlaan_pricing_fix.sql`.
--
-- WHY THIS FILE EXISTS:
--   The r047 fix migration (20260830000009) ends with a SANITY
--   ASSERTION that raises an exception if any rows in fixed_routes
--   still use the unanchored '%luchthavenlaan 2%' pattern.
--
--   In production, those broad patterns were removed by an earlier
--   manual SQL cleanup (not preserved in the migration chain). The
--   r047 fix assumes the cleanup happened before its INSERT.
--
--   For greenfield reconstruction, the broad patterns were JUST
--   inserted by `centralized_pricing_engine.sql` and would still be
--   present when the r047 assertion runs. To make the chain apply
--   with zero SQL errors on a fresh database, we DELETE the broad
--   patterns here, in the canonical order, between the two migrations.
--
-- SCOPE: greenfield-only. Idempotent (DELETE only; no INSERTs).
-- DOES NOT alter any existing migration content.
-- Safe to apply on greenfield only (production already has 0 broad
-- patterns; DELETE is a no-op).
-- =====================================================================

delete from public.fixed_routes
where pickup_pattern = '%luchthavenlaan 2%'
   or dropoff_pattern = '%luchthavenlaan 2%';
