-- Migration: Long-distance base becomes €1.80/km (per Founder directive 2026-08-30)
--
-- Per Lux r056 Phase A review §2 (commit b6dd5e0):
-- - ordinary long-distance / distance-based FleetConnect pricing: €1.80 per km
--   (was €1.50 or €2.00 depending on phase; canonical is now €1.80)
-- - preserve local Vilvoorde €15 minimum
-- - preserve Vilvoorde/Brussels critical minimum logic
-- - preserve genuine airport minimum/rules
-- - preserve Campanile → Airport €25 fixed and Airport → Campanile €30 fixed
-- - do NOT let 'Luchthavenlaan' street names trigger airport classification
-- - no other pricing rule should silently change
--
-- Website/public pricing wording: Founder does NOT want rigid €1.80/km
-- advertised as headline. This change applies to the authoritative pricing
-- layer only; website public-text cleanup is a separate task.

-- Update pricing_profiles.price_per_km from 2.00 to 1.80 for all profiles
UPDATE public.pricing_profiles
SET price_per_km = 1.80
WHERE price_per_km != 1.80;

-- Add regression guard to ensure €1.80/km rate is preserved
CREATE OR REPLACE FUNCTION public.assert_long_distance_rate_1_80_per_km()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count integer;
BEGIN
    SELECT count(*) INTO v_count FROM public.pricing_profiles
    WHERE price_per_km != 1.80;
    IF v_count > 0 THEN
        RAISE EXCEPTION 'r056 regression guard: pricing_profiles.price_per_km must be 1.80 for ALL profiles (found % mismatches)', v_count;
    END IF;
    RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.assert_long_distance_rate_1_80_per_km() TO service_role;

COMMENT ON FUNCTION public.assert_long_distance_rate_1_80_per_km() IS
    'r056 regression guard: enforces €1.80/km long-distance base rate per Founder pricing directive 2026-08-30 (Lux r056 §2). All pricing_profiles.price_per_km must equal 1.80.';

-- Self-verify
SELECT * FROM public.assert_long_distance_rate_1_80_per_km();