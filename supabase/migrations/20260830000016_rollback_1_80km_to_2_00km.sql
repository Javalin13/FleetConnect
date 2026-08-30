-- Migration: Rollback r056 Phase 1 €1.80/km directive — restore €2.00/km
--
-- Per Founder correction 2026-08-30 ("keep the 2€/km, Lux is working on that"):
-- - The €1.80/km directive (Lux r056 §2 / commit b6dd5e0) is NOT to be applied
-- - Restore pricing_profiles.price_per_km back to €2.00 (canonical pre-r056 Phase 1 state)
-- - Drop the r056 Phase 1 regression guard (it enforces 1.80, no longer wanted)
-- - Preserve all locked guards (Vilvoorde €15 min, Brussels €30 min, Campanile €25/€30 fixed,
--   Luchthavenlaan NOT triggering airport, airport min €30) — these come from r047, NOT from
--   the rate change, and stay intact
--
-- No other pricing rule changes.

-- Restore €2.00/km for all profiles
UPDATE public.pricing_profiles
SET price_per_km = 2.00
WHERE price_per_km != 2.00;

-- Drop the r056 Phase 1 regression guard (it enforces 1.80, no longer wanted)
DROP FUNCTION IF EXISTS public.assert_long_distance_rate_1_80_per_km();

-- Restore €2.00 regression guard (canonical pre-r056 Phase 1 state)
CREATE OR REPLACE FUNCTION public.assert_long_distance_rate_2_00_per_km()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count integer;
BEGIN
    SELECT count(*) INTO v_count FROM public.pricing_profiles
    WHERE price_per_km != 2.00;
    IF v_count > 0 THEN
        RAISE EXCEPTION 'r056-rollback regression guard: pricing_profiles.price_per_km must be 2.00 for ALL profiles (found % mismatches)', v_count;
    END IF;
    RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.assert_long_distance_rate_2_00_per_km() TO service_role;

COMMENT ON FUNCTION public.assert_long_distance_rate_2_00_per_km() IS
    'Canonical regression guard: enforces €2.00/km rate per pre-r056-Phase-1 state. Rolled back from r056 Phase 1 €1.80/km directive per Founder correction 2026-08-30 (Lux is working on the directive).';

-- Self-verify
SELECT * FROM public.assert_long_distance_rate_2_00_per_km();