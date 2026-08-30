-- r047: Comprehensive regression guard for Luchthavenlaan + airport classification
-- Per Lux §2: explicitly verifies both narrow corrections
--   (1) calculate_booking_fare: Luchthavenlaan 18 Vilvoorde → Vilvoorde Centrum = €15 Vilvoorde route
--   (2) fixed_routes: Campanile match works for both 'Luchthavenlaan 2 1800' and 'Luchthavenlaan 2, 1800' forms

do $$
declare
  v_buggy_count integer;
  v_fixed_count integer;
  v_campanile_comma_count integer;
  v_campanile_space_count integer;
  v_lv18_to_vilvoorde jsonb;
  v_lv18_to_mechelen jsonb;
  v_campanile_no_comma jsonb;
  v_lv27_to_airport jsonb;
begin
  -- (1) fixed_routes: unanchored pattern must not exist
  select count(*) into v_buggy_count
    from public.fixed_routes
   where pickup_pattern = chr(37) || 'luchthavenlaan 2' || chr(37)
      or dropoff_pattern = chr(37) || 'luchthavenlaan 2' || chr(37);

  if v_buggy_count > 0 then
    raise warning 'Regression guard: % rows still use unanchored pattern', v_buggy_count;
  else
    raise notice 'Regression guard OK: 0 rows use unanchored %%luchthavenlaan 2%% pattern';
  end if;

  -- (2) fixed_routes: anchored patterns present (comma + space variants)
  select count(*) into v_fixed_count
    from public.fixed_routes
   where pickup_pattern in (chr(37) || 'luchthavenlaan 2,' || chr(37), chr(37) || 'luchthavenlaan 2 ' || chr(37))
      or dropoff_pattern in (chr(37) || 'luchthavenlaan 2,' || chr(37), chr(37) || 'luchthavenlaan 2 ' || chr(37));

  if v_fixed_count <> 8 then
    raise warning 'Regression guard: expected 8 rows with anchored patterns (comma + space, 2 directions x 2 endpoints x 2 variants), found %', v_fixed_count;
  else
    raise notice 'Regression guard OK: 8 rows with anchored patterns (covers both canonical address forms)';
  end if;

  -- (3) calculate_booking_fare: Luchthavenlaan 18 Vilvoorde -> Vilvoorde Centrum = €15 Vilvoorde route
  select public.calculate_booking_fare(3, 'luchthavenlaan 18, vilvoorde', 'vilvoorde centrum', false, 1) into v_lv18_to_vilvoorde;

  if (v_lv18_to_vilvoorde->>'route_name') = 'Vilvoorde' and (v_lv18_to_vilvoorde->>'applicable_min_fare')::numeric = 15 then
    raise notice 'Regression guard OK: Luchthavenlaan 18 Vilvoorde -> Vilvoorde Centrum = Vilvoorde route, min €15 (was: Luchthaven/€30 BEFORE r047 fix)';
  else
    raise warning 'Regression guard FAIL: Luchthavenlaan 18 Vilvoorde -> Vilvoorde Centrum returned route=%, min=% (expected Vilvoorde/€15)',
      v_lv18_to_vilvoorde->>'route_name', v_lv18_to_vilvoorde->>'applicable_min_fare';
  end if;

  -- (4) calculate_booking_fare: Luchthavenlaan 18 Vilvoorde -> Mechelen = NO airport route
  select public.calculate_booking_fare(10, 'luchthavenlaan 18, vilvoorde', 'mechelen centrum', false, 1) into v_lv18_to_mechelen;

  if (v_lv18_to_mechelen->>'route_name') <> 'Luchthaven' then
    raise notice 'Regression guard OK: Luchthavenlaan 18 Vilvoorde -> Mechelen = % route (NOT Luchthaven)', v_lv18_to_mechelen->>'route_name';
  else
    raise warning 'Regression guard FAIL: Luchthavenlaan 18 Vilvoorde -> Mechelen = Luchthaven route (false positive still exists)';
  end if;

  -- (5) fixed_routes: Campanile no-comma form still matches
  select public.calculate_booking_fare(50, 'luchthavenlaan 2 1800 vilvoorde', 'brussels airport, zaventem', false, 1) into v_campanile_no_comma;

  if (v_campanile_no_comma->>'is_fixed_route')::boolean = true and (v_campanile_no_comma->>'total_amount')::numeric = 25 then
    raise notice 'Regression guard OK: Campanile no-comma form (luchthavenlaan 2 1800 vilvoorde) -> Brussels Airport = €25 fixed';
  else
    raise warning 'Regression guard FAIL: Campanile no-comma form returned %, % (expected fixed/€25)',
      v_campanile_no_comma->>'is_fixed_route', v_campanile_no_comma->>'total_amount';
  end if;

  -- (6) fixed_routes: non-Campanile Luchthavenlaan 27 -> Airport does NOT match fixed route
  select public.calculate_booking_fare(50, 'luchthavenlaan 27, vilvoorde', 'brussels airport, zaventem', false, 1) into v_lv27_to_airport;

  if (v_lv27_to_airport->>'is_fixed_route')::boolean = false then
    raise notice 'Regression guard OK: Luchthavenlaan 27 -> Brussels Airport NOT a fixed route (variable pricing)';
  else
    raise warning 'Regression guard FAIL: Luchthavenlaan 27 -> Brussels Airport = fixed route €% (false positive LIVES)',
      v_lv27_to_airport->>'total_amount';
  end if;
end $$;
