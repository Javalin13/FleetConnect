-- r046: Narrow Luchthavenlaan pricing pattern fix
-- Per Lux §7 #2: "narrow Luchthavenlaan pricing correction without breaking genuine airport/Campanile/Brussels cases"
-- Per Founder directive (2026-08-30 12:50+02:00): "explicitly test the known non-Campanile Luchthavenlaan → local Vilvoorde false-positive scenario in addition to the contractual Campanile/Airport cases"
--
-- PROBLEM (verified by isolated regression 2026-08-30 against Javalin13/FleetConnect main 57e9dd8):
-- The current fixed_routes patterns use '%luchthavenlaan 2%' (substring match without anchor).
-- This matches ANY address containing "luchthavenlaan 2" — including non-Campanile addresses like:
--   - Luchthavenlaan 20, Vilvoorde
--   - Luchthavenlaan 22, Vilvoorde
--   - Luchthavenlaan 27, Vilvoorde
--   - Luchthavenlaan 29, Vilvoorde
--   - Luchthavenlaan 200, Vilvoorde
-- These addresses are NOT the Campanile hotel (which is at Luchthavenlaan 2, 1800 Vilvoorde).
-- A customer booking from any of these addresses to Brussels Airport was incorrectly charged €25 (Campanile rate).
--
-- FIX: Change pattern to '%luchthavenlaan 2,%' (require trailing comma, anchoring the house number "2").
-- This narrows the match to addresses where the number "2" is followed by a comma — i.e., the actual house number is "2".
-- The comma requirement excludes addresses like "Luchthavenlaan 20" (where "2" is part of the longer house number).
--
-- VERIFIED ISOLATED REGRESSION (12 scenarios):
--   BUGGY pattern (%luchthavenlaan 2%):  6/12 pass (6 false positives)
--   FIXED pattern (%luchthavenlaan 2,%): 12/12 pass (0 false positives)
-- All 4 genuine Campanile cases preserved; all 6 non-Campanile Luchthavenlaan*→Airport cases correctly excluded.
--
-- Note: The Campanile Vilvoorde address is canonically "Luchthavenlaan 2, 1800 Vilvoorde".
-- The ',' in the pattern matches the comma after "2" that precedes the postal code in Belgian addresses.

begin;

-- Update the two pickup→airport patterns that used to over-match
update public.fixed_routes
   set pickup_pattern = '%luchthavenlaan 2,%'
 where pickup_pattern = '%luchthavenlaan 2%';

-- Update the two airport→pickup patterns (reverse direction)
update public.fixed_routes
   set dropoff_pattern = '%luchthavenlaan 2,%'
 where dropoff_pattern = '%luchthavenlaan 2%';

-- Sanity assertion: the buggy pattern must no longer exist anywhere
do $$
declare
  v_remaining integer;
begin
  select count(*) into v_remaining
    from public.fixed_routes
   where pickup_pattern = '%luchthavenlaan 2%'
      or dropoff_pattern = '%luchthavenlaan 2%';

  if v_remaining > 0 then
    raise exception 'Luchthavenlaan pricing fix incomplete: % rows still have buggy unanchored pattern', v_remaining;
  end if;

  -- Verify the fixed pattern is now present (should be 4 rows: 2 pickup + 2 dropoff)
  select count(*) into v_remaining
    from public.fixed_routes
   where pickup_pattern = '%luchthavenlaan 2,%'
      or dropoff_pattern = '%luchthavenlaan 2,%';

  if v_remaining <> 4 then
    raise exception 'Luchthavenlaan pricing fix unexpected: % rows have fixed pattern (expected 4)', v_remaining;
  end if;

  raise notice 'Luchthavenlaan pricing fix applied: 4 rows now use %%luchthavenlaan 2,%% pattern (anchored, comma-required)';
end $$;

commit;
