begin;

-- Create pricing profiles table
create table if not exists public.pricing_profiles (
  id serial primary key,
  name text not null,
  base_fare numeric not null default 0.00,
  price_per_km numeric not null default 1.50,
  price_per_minute numeric not null default 0.00,
  default_minimum_fare numeric not null default 30.00,
  vilvoorde_minimum_fare numeric not null default 15.00,
  brussels_minimum_fare numeric not null default 30.00,
  airport_minimum_fare numeric not null default 30.00,
  luchthaven_fixed_price numeric not null default 35.00,
  hotel_discount numeric not null default 5.00
);

-- Insert default FleetConnect pricing profile if not exists
insert into public.pricing_profiles (id, name, base_fare, price_per_km, default_minimum_fare, vilvoorde_minimum_fare, brussels_minimum_fare, airport_minimum_fare, luchthaven_fixed_price, hotel_discount)
values (1, 'Default FleetConnect Profile', 0.00, 1.50, 30.00, 15.00, 30.00, 30.00, 35.00, 5.00)
on conflict (id) do update set
  price_per_km = excluded.price_per_km,
  default_minimum_fare = excluded.default_minimum_fare,
  vilvoorde_minimum_fare = excluded.vilvoorde_minimum_fare,
  brussels_minimum_fare = excluded.brussels_minimum_fare,
  airport_minimum_fare = excluded.airport_minimum_fare;

-- Create fixed routes table for data-driven fixed pricing
create table if not exists public.fixed_routes (
  id serial primary key,
  pickup_pattern text not null,
  dropoff_pattern text not null,
  fixed_price numeric not null,
  description text not null
);

-- Insert contractual fixed routes
truncate table public.fixed_routes;
insert into public.fixed_routes (pickup_pattern, dropoff_pattern, fixed_price, description)
values
  -- Campanile Vilvoorde -> Brussels Airport (Contractual €25.00 after discount, base €30.00 with €5.00 discount)
  ('%luchthavenlaan 2%', '%zaventem%', 25.00, 'Campanile Vilvoorde ⇄ Brussels Airport'),
  ('%luchthavenlaan 2%', '%brussels airport%', 25.00, 'Campanile Vilvoorde ⇄ Brussels Airport'),
  ('%campanile%', '%zaventem%', 25.00, 'Campanile Vilvoorde ⇄ Brussels Airport'),
  ('%campanile%', '%brussels airport%', 25.00, 'Campanile Vilvoorde ⇄ Brussels Airport'),

  -- Brussels Airport -> Campanile Vilvoorde (Contractual €30.00 after discount, base €35.00 with €5.00 discount)
  ('%zaventem%', '%luchthavenlaan 2%', 30.00, 'Brussels Airport ⇄ Campanile Vilvoorde'),
  ('%brussels airport%', '%luchthavenlaan 2%', 30.00, 'Brussels Airport ⇄ Campanile Vilvoorde'),
  ('%zaventem%', '%campanile%', 30.00, 'Brussels Airport ⇄ Campanile Vilvoorde'),
  ('%brussels airport%', '%campanile%', 30.00, 'Brussels Airport ⇄ Campanile Vilvoorde');

-- Create a central DB function to calculate fares
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
  v_pickup_clean text;
  v_dropoff_clean text;
  v_applicable_min numeric;
  v_is_min_applied boolean;
  v_base_fare numeric;
  v_total numeric;
  v_raw_amount numeric;
  v_route_name text;
begin
  v_pickup := lower(coalesce(p_pickup_address, ''));
  v_dropoff := lower(coalesce(p_dropoff_address, ''));

  -- Clean address of 'luchthavenlaan' and 'luchthavenweg' before checking for airport transfers
  v_pickup_clean := replace(replace(v_pickup, 'luchthavenlaan', ''), 'luchthavenweg', '');
  v_dropoff_clean := replace(replace(v_dropoff, 'luchthavenlaan', ''), 'luchthavenweg', '');

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

  -- 3. Determine regional minimum fare
  v_applicable_min := v_profile.default_minimum_fare;
  v_route_name := 'Standaard';

  -- Check Brussels Airport transfers
  if v_pickup_clean like '%zaventem%' or v_pickup_clean like '%brussels airport%' or v_pickup_clean like '%luchthaven%' or
     v_dropoff_clean like '%zaventem%' or v_dropoff_clean like '%brussels airport%' or v_dropoff_clean like '%luchthaven%' then
    v_applicable_min := v_profile.airport_minimum_fare;
    v_route_name := 'Luchthaven';
  -- Check Brussels region
  elsif v_pickup like '%brussel%' or v_pickup like '%bruxelles%' or v_pickup like '%brussels%' or
        v_dropoff like '%brussel%' or v_dropoff like '%bruxelles%' or v_dropoff like '%brussels%' then
    v_applicable_min := v_profile.brussels_minimum_fare;
    v_route_name := 'Brussel';
  -- Check Vilvoorde region
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

revoke all on function public.calculate_booking_fare(numeric, text, text, boolean, integer) from public;
grant execute on function public.calculate_booking_fare(numeric, text, text, boolean, integer) to anon, authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
