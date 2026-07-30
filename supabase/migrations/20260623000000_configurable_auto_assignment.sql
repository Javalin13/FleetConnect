begin;

-- 1. Add primary_dispatch_driver_id column to public.partners if it doesn't exist
alter table public.partners add column if not exists primary_dispatch_driver_id uuid references public.drivers(id) on delete set null;

-- 2. Configure Younes' partner (ID 39) and the Hoofdpartner (ID 1) to use Younes' driver ID for auto-assignments
update public.partners
   set primary_dispatch_driver_id = '4e40bdca-0468-4d1e-abb3-d39d9ddcc58a'
 where id in (1, 39);

-- 3. Refactor public.create_public_booking to use configurable auto-assignment settings
create or replace function public.create_public_booking(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text;
  v_status text;
  v_pickup text;
  v_destination text;
  v_pickup_place_id text;
  v_dropoff_place_id text;
  v_distance numeric;
  v_duration integer;
  v_amount numeric;
  v_manual_route boolean;
  v_form_data jsonb;
  v_metadata jsonb;
  v_result jsonb;
  v_partner_id integer;

  -- Auto-assignment variables
  v_driver public.drivers%rowtype;
  v_token text;
  v_primary_driver_id uuid;
begin
  if payload is null then
    raise exception 'Missing booking payload';
  end if;

  v_status := 'assignment_sent'; -- Automatically set to assignment_sent for auto-assignment

  v_pickup := nullif(trim(payload->>'pickup'), '');
  v_destination := nullif(trim(payload->>'destination'), '');
  v_pickup_place_id := nullif(trim(coalesce(payload->>'pickup_place_id', payload #>> '{form_data,pickup_place_id}', payload #>> '{metadata,pickup_place_id}')), '');
  v_dropoff_place_id := nullif(trim(coalesce(payload->>'dropoff_place_id', payload #>> '{form_data,dropoff_place_id}', payload #>> '{metadata,dropoff_place_id}')), '');
  v_distance := nullif(coalesce(payload->>'route_distance_km', payload #>> '{form_data,route_distance_km}', payload #>> '{metadata,route_distance_km}', payload->>'distance_km', payload #>> '{form_data,distance_km}', payload #>> '{metadata,distance_km}'), '')::numeric;
  v_duration := nullif(coalesce(payload->>'route_duration_min', payload #>> '{form_data,route_duration_min}', payload #>> '{metadata,route_duration_min}', payload->>'duration_min', payload #>> '{form_data,duration_min}', payload #>> '{metadata,duration_min}'), '')::integer;
  v_amount := nullif(payload->>'amount','')::numeric;
  v_manual_route := coalesce((payload #>> '{metadata,manual_route_required}')::boolean, false)
    or coalesce((payload #>> '{form_data,manual_route_required}')::boolean, false);

  if v_pickup is null or length(v_pickup) < 3 then
    raise exception 'Valid pickup address is required';
  end if;

  if v_destination is null or length(v_destination) < 3 then
    raise exception 'Valid destination address is required';
  end if;

  if not v_manual_route and (v_pickup_place_id is null or v_dropoff_place_id is null) then
    raise exception 'Google-selected pickup and destination addresses are required';
  end if;

  if not v_manual_route and (v_distance is null or v_distance <= 0) then
    raise exception 'Calculated route distance is required';
  end if;

  if not v_manual_route and (v_duration is null or v_duration <= 0) then
    raise exception 'Calculated route duration is required';
  end if;

  if v_amount is null or v_amount < 15 then
    raise exception 'Minimum booking amount is EUR 15';
  end if;

  if v_manual_route then
    v_pickup_place_id := coalesce(v_pickup_place_id, 'manual-pickup');
    v_dropoff_place_id := coalesce(v_dropoff_place_id, 'manual-dropoff');
    v_distance := coalesce(v_distance, 0);
    v_duration := coalesce(v_duration, 0);
  end if;

  v_partner_id := coalesce(nullif(payload->>'partner_id','')::integer, 1);

  -- Retrieve the configured primary dispatch driver for the partner
  select primary_dispatch_driver_id into v_primary_driver_id
    from public.partners
   where id = v_partner_id;

  -- Select the configured driver
  if v_primary_driver_id is not null then
    select * into v_driver from public.drivers where id = v_primary_driver_id and is_active is not false;
  end if;

  -- Fallback to Younes Mrabet's driver ID if still not resolved
  if v_driver.id is null then
    select * into v_driver from public.drivers where id = '4e40bdca-0468-4d1e-abb3-d39d9ddcc58a' and is_active is not false;
  end if;

  -- Fallback to any active driver if still not found (e.g. in test suite context where Younes doesn't exist yet)
  if v_driver.id is null then
    select * into v_driver from public.drivers where is_active is not false limit 1;
  end if;

  v_token := gen_random_uuid()::text;
  v_id := coalesce(nullif(payload->>'id',''), 'FC-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'));

  v_form_data := coalesce(payload->'form_data', '{}'::jsonb) || jsonb_build_object(
    'pickup_place_id', v_pickup_place_id,
    'dropoff_place_id', v_dropoff_place_id,
    'route_distance_km', v_distance,
    'route_duration_min', v_duration,
    'route_pricing_required', not v_manual_route,
    'manual_route_required', v_manual_route
  );
  v_metadata := coalesce(payload->'metadata', '{}'::jsonb) || jsonb_build_object(
    'pickup_place_id', v_pickup_place_id,
    'dropoff_place_id', v_dropoff_place_id,
    'route_distance_km', v_distance,
    'route_duration_min', v_duration,
    'route_pricing_required', not v_manual_route,
    'manual_route_required', v_manual_route,
    'assignment_requested_at', now()
  );

  insert into public.bookings (
    id, datetime, time, name, email, phone, pickup, destination, flight_number,
    vehicle, extras, amount, payment, status, customer_id, form_data, metadata,
    partner_id, payment_status, user_id, pickup_place_id, dropoff_place_id,
    route_distance_km, route_duration_min,
    assigned_driver_id, assignment_token, assignment_sent_at, assigned_driver
  ) values (
    v_id,
    nullif(payload->>'datetime',''),
    nullif(payload->>'time',''),
    nullif(payload->>'name',''),
    lower(nullif(payload->>'email','')),
    nullif(payload->>'phone',''),
    v_pickup,
    v_destination,
    nullif(payload->>'flight_number',''),
    nullif(payload->>'vehicle',''),
    nullif(payload->>'extras',''),
    v_amount,
    nullif(payload->>'payment',''),
    v_status,
    nullif(payload->>'customer_id',''),
    v_form_data,
    v_metadata,
    v_partner_id,
    coalesce(nullif(payload->>'payment_status',''), case when nullif(payload->>'payment','') = 'Cash' then 'cash_pending' else 'unpaid' end),
    auth.uid(),
    v_pickup_place_id,
    v_dropoff_place_id,
    v_distance,
    v_duration,

    -- Auto-assigned driver details
    v_driver.id,
    v_token,
    now(),
    case when v_driver.id is not null then jsonb_build_object(
      'id', v_driver.id,
      'name', v_driver.name,
      'email', v_driver.email,
      'phone', v_driver.phone,
      'vehicle', v_driver.vehicle,
      'color', v_driver.color,
      'license_plate', v_driver.license_plate
    ) else null end
  )
  returning to_jsonb(bookings.*) into v_result;

  return v_result;
end;
$$;

revoke all on function public.create_public_booking(jsonb) from public;
grant execute on function public.create_public_booking(jsonb) to anon, authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
