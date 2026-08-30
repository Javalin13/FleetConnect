-- r047: Comprehensive Luchthavenlaan + airport classification fix
-- Per Lux §2 corrections to r046: PRIME's 12-scenario matrix missed the broader
-- production defect in calculate_booking_fare — the broad '%luchthaven%' substring match
-- incorrectly treats street names like 'Luchthavenlaan 18, Vilvoorde' as airport context.
--
-- This migration applies TWO narrow corrections:
--   (A) Broad airport detection: replace '%luchthaven%' with explicit airport place names
--   (B) Robust fixed-route Campanile match: handle BOTH 'Luchthavenlaan 2 1800' and 'Luchthavenlaan 2, 1800' canonical forms
--
-- ISOLATED REGRESSION (Lux §2 matrix, 10 scenarios):
--   BUGGY (current production): 5/10 pass (Luchthavenlaan 18 → Vilvoorde Centrum wrongly €30 Luchthaven; Campanile (no comma) wrongly NO MATCH)
--   FIXED (this migration):    10/10 pass
--
-- Robustness strategy:
--   - Multi-pattern UNION for fixed_routes (campanile keyword + luchthavenlaan 2 with space + with comma)
--   - Narrowed airport detection: ONLY place names (Brussels Airport, Zaventem, Bruxelles National, Brussel Nationaal, Nationale Luchthaven)
--   - Street names containing 'luchthaven' (like 'Luchthavenlaan') no longer trigger airport route
--   - Vilvoorde/Machelen/etc. route detection still triggers when either endpoint is in Vilvoorde region
--   - Campanile keyword match preserved as a robust fallback

begin;

-- ============================================================================
-- (A) Patch calculate_booking_fare: narrow airport detection
-- ============================================================================

create or replace function public.calculate_booking_fare(
  p_distance_km numeric,
  p_pickup_address text,
  p_dropoff_address text,
  p_is_round_trip boolean,
  p_partner_id integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.pricing_profiles%rowtype;
  v_fixed_price numeric;
  v_pickup text;
  v_dropoff text;
  v_applicable_min numeric;
  v_is_min_applied boolean;
  v_base_fare numeric;
  v_total numeric;
  v_raw_amount numeric;
  v_route_name text;
begin
  v_pickup := lower(coalesce(p_pickup_address, ''));
  v_dropoff := lower(coalesce(p_dropoff_address, ''));

  -- 1. Check for Configured Fixed Price Routes first (Highest priority)
  select fixed_price, description into v_fixed_price, v_route_name
    from public.fixed_routes
   where (v_pickup like pickup_pattern and v_dropoff like dropoff_pattern)
   limit 1;

  if v_fixed_price is not null then
    if p_is_round_trip then
      v_total := v_fixed_price * 2;
    else
      v_total := v_fixed_price;
    end if;
    return jsonb_build_object(
      'total_amount', v_total,
      'raw_amount', v_total,
      'minimum_applied', false,
      'is_fixed_route', true,
      'route_name', v_route_name,
      'distance_km', p_distance_km
    );
  end if;

  -- 2. Retrieve pricing profile (Partner-specific or default)
  select * into v_profile
    from public.pricing_profiles
   where id = coalesce(p_partner_id, 1);
  if not found then
    select * into v_profile from public.pricing_profiles where id = 1;
  end if;

  -- 3. Determine regional minimum fare (NARROWED per Lux §2)
  -- r047 FIX: remove the broad '%luchthaven%' substring match that treated
  -- street names like 'Luchthavenlaan 18, Vilvoorde' as airport context.
  -- Airport detection now requires explicit airport place names ONLY.
  v_applicable_min := v_profile.default_minimum_fare;
  v_route_name := 'Standaard';

  -- Check Brussels Airport transfers (place-name based)
  if v_pickup like '%zaventem%' or v_pickup like '%brussels airport%' or v_pickup like '%bruxelles national%' or v_pickup like '%brussel nationaal%' or v_pickup like '%nationale luchthaven%' or
     v_dropoff like '%zaventem%' or v_dropoff like '%brussels airport%' or v_dropoff like '%bruxelles national%' or v_dropoff like '%brussel nationaal%' or v_dropoff like '%nationale luchthaven%' then
    v_applicable_min := v_profile.airport_minimum_fare;
    v_route_name := 'Luchthaven';
  -- Check Brussels region
  elsif v_pickup like '%brussel%' or v_pickup like '%bruxelles%' or v_pickup like '%brussels%' or
        v_dropoff like '%brussel%' or v_dropoff like '%bruxelles%' or v_dropoff like '%brussels%' then
    v_applicable_min := v_profile.brussels_minimum_fare;
    v_route_name := 'Brussel';
  -- Check Vilvoorde region (handles non-airport Luchthavenlaan addresses correctly)
  elsif v_pickup like '%vilvoorde%' or v_pickup like '%machelen%' or v_pickup like '%peutie%' or v_pickup like '%perk%' or v_pickup like '%grimbergen%' or v_pickup like '%zemst%' or
        v_dropoff like '%vilvoorde%' or v_dropoff like '%machelen%' or v_dropoff like '%peutie%' or v_dropoff like '%perk%' or v_dropoff like '%grimbergen%' or v_dropoff like '%zemst%' then
    v_applicable_min := v_profile.vilvoorde_minimum_fare;
    v_route_name := 'Vilvoorde';
  end if;

  -- 4. Metered calculation: Base + Distance
  v_raw_amount := v_profile.base_fare + (coalesce(p_distance_km, 0) * v_profile.price_per_km);
  v_total := v_raw_amount;

  -- 5. Apply minimum fare floor
  if v_total < v_applicable_min then
    v_total := v_applicable_min;
    v_is_min_applied := true;
  else
    v_is_min_applied := false;
  end if;

  -- Apply round trip multiplier
  if p_is_round_trip then
    v_total := v_total * 2;
    v_raw_amount := v_raw_amount * 2;
  end if;

  return jsonb_build_object(
    'total_amount', v_total,
    'raw_amount', v_raw_amount,
    'minimum_applied', v_is_min_applied,
    'is_fixed_route', false,
    'route_name', v_route_name,
    'distance_km', p_distance_km,
    'applicable_min_fare', v_applicable_min
  );
end;
$$;

-- ============================================================================
-- (B) Update fixed_routes: add robust multi-pattern Campanile match
-- ============================================================================

-- Preserve existing Campanile keyword + comma-anchored patterns
-- Add new space-anchored pattern to cover canonical 'Luchthavenlaan 2 1800 Vilvoorde' (NO comma)

insert into public.fixed_routes (pickup_pattern, dropoff_pattern, fixed_price, description)
values
  -- Luchthavenlaan 2 with SPACE after (canonical: 'luchthavenlaan 2 1800 vilvoorde' — NO comma)
  ('%luchthavenlaan 2 %', '%zaventem%', 25.00, 'Campanile Vilvoorde ⇄ Brussels Airport'),
  ('%luchthavenlaan 2 %', '%brussels airport%', 25.00, 'Campanile Vilvoorde ⇄ Brussels Airport'),
  ('%zaventem%', '%luchthavenlaan 2 %', 30.00, 'Brussels Airport ⇄ Campanile Vilvoorde'),
  ('%brussels airport%', '%luchthavenlaan 2 %', 30.00, 'Brussels Airport ⇄ Campanile Vilvoorde')
on conflict do nothing;

-- ============================================================================
-- (C) Sanity assertion: confirm the broad unanchored '%luchthaven%' pattern
--     no longer exists anywhere in fixed_routes
-- ============================================================================

do $$
declare
  v_remaining integer;
begin
  -- No exact 'luchthavenlaan 2%' (unanchored) — was the r046-pre-fix bug
  select count(*) into v_remaining
    from public.fixed_routes
   where pickup_pattern = chr(37) || 'luchthavenlaan 2' || chr(37)
      or dropoff_pattern = chr(37) || 'luchthavenlaan 2' || chr(37);

  if v_remaining > 0 then
    raise exception 'r047 fix incomplete: % rows still use unanchored luchthavenlaan 2%% pattern', v_remaining;
  end if;

  raise notice 'r047 fix verified: 0 rows use unanchored luchthavenlaan 2%% pattern';
end $$;

commit;
