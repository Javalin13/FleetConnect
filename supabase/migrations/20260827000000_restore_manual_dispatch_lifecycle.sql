begin;

-- Production hotfix: public website bookings must enter manual dispatch.
-- Do not auto-assign a driver during create_public_booking.
create or replace function public.create_public_booking(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text;
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
  v_partner_id bigint;
begin
  if payload is null then
    raise exception 'Missing booking payload';
  end if;

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

  v_partner_id := coalesce(nullif(payload->>'partner_id','')::bigint, 1);
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
    'dispatch_lifecycle', 'manual',
    'manual_dispatch_created_at', now()
  );

  insert into public.bookings (
    id, datetime, time, name, email, phone, pickup, destination, flight_number,
    vehicle, extras, amount, payment, status, customer_id, form_data, metadata,
    partner_id, payment_status, user_id, pickup_place_id, dropoff_place_id,
    route_distance_km, route_duration_min,
    assigned_driver_id, assignment_token, assignment_sent_at, assignment_accepted_at,
    assignment_declined_at, assigned_driver
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
    'pending',
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
    null,
    null,
    null,
    null,
    null,
    null
  )
  returning to_jsonb(bookings.*) into v_result;

  return v_result;
end;
$$;

create or replace function public.operator_assign_driver(
  p_booking_id text,
  p_driver_id uuid,
  p_assignment_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
  v_driver public.drivers%rowtype;
  v_token text;
begin
  if auth.uid() is null or not public.is_operator() then
    raise exception 'Operator access required' using errcode = '42501';
  end if;

  select * into v_booking from public.bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Booking not found';
  end if;

  if v_booking.status in ('completed', 'cancelled') then
    raise exception 'Closed rides cannot be assigned';
  end if;

  if v_booking.status = 'assigned'
     and v_booking.assigned_driver_id is not null
     and coalesce((v_booking.metadata->>'driver_recalled')::boolean, false) is false then
    raise exception 'Current driver must be recalled before reassignment';
  end if;

  if v_booking.status not in ('pending', 'pending_payment', 'accepted', 'assignment_sent', 'reassignment_needed')
     and coalesce((v_booking.metadata->>'driver_recalled')::boolean, false) is false then
    raise exception 'Booking is not ready for driver assignment';
  end if;

  select * into v_driver
    from public.drivers
   where id = p_driver_id
     and coalesce(is_active, true) = true
     and archived_at is null;

  if not found then
    raise exception 'Active driver not found';
  end if;

  v_token := coalesce(nullif(p_assignment_token, ''), gen_random_uuid()::text);

  update public.bookings
     set status = 'assignment_sent',
         partner_id = coalesce(v_driver.partner_id, partner_id),
         assigned_driver_id = v_driver.id,
         assignment_token = v_token,
         assignment_sent_at = now(),
         assignment_accepted_at = null,
         assignment_declined_at = null,
         assigned_driver = jsonb_build_object(
           'id', v_driver.id,
           'name', v_driver.name,
           'email', v_driver.email,
           'phone', v_driver.phone,
           'vehicle', v_driver.vehicle,
           'color', v_driver.color,
           'license_plate', v_driver.license_plate
         ),
         metadata = coalesce(metadata, '{}'::jsonb)
           - 'driver_recalled'
           || jsonb_build_object(
             'dispatch_lifecycle', 'manual',
             'manual_assignment_requested_at', now(),
             'manual_assignment_requested_by', auth.uid(),
             'previous_assigned_driver_id', v_booking.assigned_driver_id,
             'requires_reassignment', false,
             'reassignment_pending_driver_acceptance', coalesce((metadata->>'requires_reassignment')::boolean, false)
           )
   where id = p_booking_id
   returning * into v_booking;

  return to_jsonb(v_booking);
end;
$$;

create or replace function public.driver_decline_assignment(p_assignment_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
  v_previous_driver jsonb;
  v_snapshot jsonb;
begin
  if p_assignment_token is null or length(trim(p_assignment_token)) < 10 then
    raise exception 'Invalid assignment token';
  end if;

  select * into v_booking
    from public.bookings
   where assignment_token = p_assignment_token
   for update;

  if not found then
    raise exception 'Assignment not found';
  end if;

  if v_booking.status <> 'assignment_sent' then
    raise exception 'Assignment is no longer active';
  end if;

  if v_booking.assignment_declined_at is not null then
    raise exception 'Assignment already declined';
  end if;

  if v_booking.assignment_sent_at is null or v_booking.assignment_sent_at < now() - interval '30 minutes' then
    raise exception 'Assignment expired';
  end if;

  v_previous_driver := v_booking.assigned_driver;

  insert into public.booking_reassignment_events (
    booking_id, previous_driver_id, previous_driver, event_type, reason, metadata
  ) values (
    v_booking.id,
    v_booking.assigned_driver_id::text,
    v_previous_driver,
    'driver_declined_before_acceptance',
    'Driver declined assignment from email action',
    jsonb_build_object(
      'assignment_token_present', true,
      'assignment_sent_at', v_booking.assignment_sent_at
    )
  );

  update public.bookings
     set assignment_declined_at = now(),
         status = 'pending',
         assigned_driver_id = null,
         assigned_driver = null,
         assignment_token = null,
         assignment_sent_at = null,
         assignment_accepted_at = null,
         metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
           'dispatch_lifecycle', 'manual',
           'requires_reassignment', true,
           'reassignment_pending_driver_acceptance', false,
           'declined_driver', v_previous_driver,
           'last_reassignment_event', 'driver_declined_before_acceptance',
           'last_reassignment_at', now()
         )
   where id = v_booking.id
   returning * into v_booking;

  v_snapshot := jsonb_build_object(
    'id', v_booking.id,
    'reference', v_booking.id,
    'datetime', v_booking.datetime,
    'time', v_booking.time,
    'pickup', v_booking.pickup,
    'destination', v_booking.destination,
    'vehicle', v_booking.vehicle,
    'amount', v_booking.amount,
    'status', v_booking.status,
    'customer', jsonb_build_object('name', v_booking.name, 'email', v_booking.email, 'phone', v_booking.phone),
    'driver', v_previous_driver,
    'metadata', coalesce(v_booking.metadata, '{}'::jsonb),
    'preferred_language', coalesce(v_booking.metadata->>'preferred_language', 'en')
  );

  return jsonb_build_object(
    'id', v_booking.id,
    'status', v_booking.status,
    'requires_reassignment', true,
    'event_type', 'driver_declined_before_acceptance',
    'snapshot', v_snapshot
  );
end;
$$;

revoke all on function public.create_public_booking(jsonb) from public;
grant execute on function public.create_public_booking(jsonb) to anon, authenticated;

revoke all on function public.operator_assign_driver(text, uuid, text) from public;
revoke all on function public.operator_assign_driver(text, uuid, text) from anon;
grant execute on function public.operator_assign_driver(text, uuid, text) to authenticated;

revoke all on function public.driver_decline_assignment(text) from public;
grant execute on function public.driver_decline_assignment(text) to anon, authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
