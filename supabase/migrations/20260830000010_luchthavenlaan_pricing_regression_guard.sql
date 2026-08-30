-- r046: Regression guard for Luchthavenlaan pricing pattern
-- Self-test SQL that the centralized pricing engine cannot regress to the unanchored pattern.
-- Safe to apply repeatedly; uses DO block with assertions only.

do $$
declare
  v_buggy_count integer;
  v_fixed_count integer;
  v_test_pickup text := 'luchthavenlaan 27, 1800 vilvoorde'; -- non-Campanile address
  v_test_dropoff text := 'brussels airport, zaventem';
  v_false_positive_count integer;
begin
  -- The buggy unanchored pattern must not exist
  select count(*) into v_buggy_count
    from public.fixed_routes
   where pickup_pattern = chr(37) || 'luchthavenlaan 2' || chr(37)
      or dropoff_pattern = chr(37) || 'luchthavenlaan 2' || chr(37);

  if v_buggy_count > 0 then
    raise warning 'Regression guard: % rows still use unanchored pattern — apply 20260830000009', v_buggy_count;
  else
    raise notice 'Regression guard OK: 0 rows use unanchored pattern';
  end if;

  -- The fixed anchored pattern must be present (4 rows)
  select count(*) into v_fixed_count
    from public.fixed_routes
   where pickup_pattern = chr(37) || 'luchthavenlaan 2,' || chr(37)
      or dropoff_pattern = chr(37) || 'luchthavenlaan 2,' || chr(37);

  if v_fixed_count <> 4 then
    raise warning 'Regression guard: expected 4 rows with anchored pattern, found %', v_fixed_count;
  else
    raise notice 'Regression guard OK: 4 rows with anchored pattern';
  end if;

  -- Functional check: non-Campanile Luchthavenlaan 27 must NOT match any fixed route to airport
  select count(*) into v_false_positive_count
    from public.fixed_routes
   where v_test_pickup like pickup_pattern
     and v_test_dropoff like dropoff_pattern;

  if v_false_positive_count > 0 then
    raise warning 'Regression guard FAIL: non-Campanile Luchthavenlaan 27 -> Brussels Airport matches % fixed routes (should be 0)', v_false_positive_count;
  else
    raise notice 'Regression guard OK: non-Campanile Luchthavenlaan 27 -> Brussels Airport has 0 fixed route matches';
  end if;
end $$;
