-- r047: Smallest factual auto-assignment/reassignment lifecycle on top of current-main schema/functions
-- Per Lux §4: "the mission explicitly requires reintroducing reliable auto-assignment after the proven manual foundation"
-- Built on top of:
--   - partners.is_hoofd (main operating partner relationship)
--   - drivers.partner_id (driver-to-partner link)
--   - bookings.status, assigned_driver_id, assignment_token, assignment_sent_at, assignment_accepted_at
--   - booking_lifecycle_events (audit trail)
-- Per Lux §5 smallest safe deterministic policy:
--   1. factual Moukrim main-operating-partner pool (via is_hoofd)
--   2. is_active=true
--   3. not archived (archived_at IS NULL)
--   4. is_available_now=true (REQUIRED gate per Lux)
--   5. exclude declined driver (from metadata.declined_driver.id, with fallback)
--   6. deterministic lowest-active-load + stable d.id ASC tie-break
--   7. assignment_sent state + timestamp + token
--   8. truthful lifecycle event semantics (NO_ELIGIBLE_DRIVER, DECLINE_REASSIGN, TIMEOUT_REASSIGN)
--   9. reassignment cap (3 max attempts)
--  10. scheduler-neutral (called by external scheduler, not internal trigger)

begin;

-- ============================================================================
-- Helper function: factual current main operating partner identity
-- ============================================================================

create or replace function public.current_main_operating_partner_id()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select id from public.partners
   where is_hoofd = true
   order by id
   limit 1;
$$;

-- ============================================================================
-- Helper: compute factual active assignment count per driver
-- ============================================================================

create or replace function public.driver_active_assignment_count(p_driver_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
    from public.bookings
   where assigned_driver_id = p_driver_id
     and status in ('assignment_sent', 'assigned', 'accepted');
$$;

-- ============================================================================
-- Main auto-assignment: assign_pending_booking_to_driver
-- Assigns one pending booking to the best eligible driver from the Moukrim pool
-- Excludes a specific driver (for decline reassignment)
-- Sets status='assignment_sent', assignment_token, timestamp
-- Writes truthful lifecycle event
-- ============================================================================

create or replace function public.assign_pending_booking_to_driver(
  p_booking_id text,
  p_exclude_driver_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.bookings%rowtype;
  v_partner_id integer;
  v_driver public.drivers%rowtype;
  v_assignment_token text;
  v_excluded_id uuid;
  v_attempted_count integer;
begin
  -- Load booking
  select * into v_booking from public.bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Booking not found: %', p_booking_id using errcode = 'P0002';
  end if;

  -- Only assign from valid pre-accept states
  if v_booking.status not in ('pending', 'assignment_sent', 'reassignment_needed', 'pending_payment', 'accepted') then
    raise exception 'Booking % not in assignable state (current: %)', p_booking_id, v_booking.status
      using errcode = 'P0001';
  end if;

  -- Reassignment cap: 3 max attempts
  v_attempted_count := coalesce((v_booking.metadata->>'reassignment_count')::integer, 0);
  if v_attempted_count >= 3 then
    raise exception 'Booking % has reached reassignment cap (3)', p_booking_id using errcode = 'P0001';
  end if;

  -- Resolve main operating partner
  v_partner_id := public.current_main_operating_partner_id();
  if v_partner_id is null then
    raise exception 'No main operating partner configured (is_hoofd=true)' using errcode = 'P0001';
  end if;

  -- Resolve excluded driver (from explicit param OR metadata.declined_driver.id)
  v_excluded_id := coalesce(
    p_exclude_driver_id,
    (v_booking.metadata->'declined_driver'->>'id')::uuid,
    (v_booking.metadata->>'declined_driver_id')::uuid
  );

  -- Select best eligible driver (smallest safe deterministic policy per Lux §5)
  -- 1. factual Moukrim pool
  -- 2. is_active=true
  -- 3. not archived
  -- 4. is_available_now=true (REQUIRED)
  -- 5. exclude declined driver
  -- 6. lowest active-assignment count first
  -- 7. stable d.id ASC tie-break
  select d.* into v_driver
    from public.drivers d
   where d.partner_id = v_partner_id
     and coalesce(d.is_active, true) = true
     and d.archived_at is null
     and d.is_available_now = true
     and (v_excluded_id is null or d.id <> v_excluded_id)
   order by public.driver_active_assignment_count(d.id) asc,
            d.id asc
   limit 1;

  if not found then
    -- Truthful no-driver event (NOT false 'ASSIGNMENT_REASSIGNED')
    update public.bookings
       set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
             'no_eligible_driver_at', now(),
             'no_eligible_driver_reason', 'no_driver_passed_eligibility_filters',
             'excluded_driver_id', v_excluded_id,
             'reassignment_count', v_attempted_count + 1
           ),
           status = 'reassignment_needed'
     where id = p_booking_id;

    insert into public.booking_lifecycle_events (booking_id, event_type, metadata)
    values (p_booking_id, 'NO_ELIGIBLE_DRIVER', jsonb_build_object(
      'reason', 'no_driver_passed_eligibility_filters',
      'excluded_driver_id', v_excluded_id,
      'partner_id', v_partner_id,
      'reassignment_count', v_attempted_count + 1
    ));

    return jsonb_build_object(
      'status', 'no_eligible_driver',
      'booking_id', p_booking_id,
      'partner_id', v_partner_id,
      'reassignment_count', v_attempted_count + 1
    );
  end if;

  -- Assign: set status='assignment_sent', generate token, write metadata
  v_assignment_token := gen_random_uuid()::text;
  update public.bookings
     set status = 'assignment_sent',
         assigned_driver_id = v_driver.id,
         assigned_driver = jsonb_build_object(
           'id', v_driver.id,
           'name', v_driver.name,
           'email', v_driver.email,
           'phone', v_driver.phone,
           'vehicle', v_driver.vehicle,
           'color', v_driver.color,
           'license_plate', v_driver.license_plate
         ),
         assignment_token = v_assignment_token,
         assignment_sent_at = now(),
         assignment_accepted_at = null,
         assignment_declined_at = null,
         partner_id = coalesce(v_driver.partner_id, v_booking.partner_id),
         metadata = (
           coalesce(metadata, '{}'::jsonb)
           - 'no_eligible_driver_at'
           - 'no_eligible_driver_reason'
         ) || jsonb_build_object(
             'dispatch_lifecycle', 'auto',
             'auto_assigned_at', now(),
             'auto_assigned_driver_id', v_driver.id,
             'previous_assigned_driver_id', v_booking.assigned_driver_id,
             'excluded_driver_id', v_excluded_id,
             'reassignment_count', v_attempted_count + 1
           )
   where id = p_booking_id
   returning * into v_booking;

  -- Truthful lifecycle event
  insert into public.booking_lifecycle_events (booking_id, event_type, driver_id, previous_driver_id, partner_id, metadata)
  values (p_booking_id, 'AUTO_ASSIGNED', v_driver.id, v_excluded_id, v_partner_id, jsonb_build_object(
    'driver_name', v_driver.name,
    'assignment_token', v_assignment_token,
    'reason', case when v_excluded_id is not null then 'reassignment_after_decline' else 'initial_assignment' end,
    'reassignment_count', v_attempted_count + 1
  ));

  return jsonb_build_object(
    'status', 'assigned',
    'booking_id', p_booking_id,
    'driver_id', v_driver.id,
    'driver_name', v_driver.name,
    'assignment_token', v_assignment_token,
    'partner_id', v_partner_id,
    'reassignment_count', v_attempted_count + 1
  );
end;
$$;

-- ============================================================================
-- Batch auto-assignment: scan for assignable bookings and assign each
-- Designed to be called by external scheduler (no internal cron)
-- ============================================================================

create or replace function public.auto_assign_pending_bookings(
  p_max_assignments integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking record;
  v_assigned_count integer := 0;
  v_failed_count integer := 0;
  v_no_driver_count integer := 0;
  v_result jsonb;
begin
  for v_booking in
    select id, status, assigned_driver_id, metadata
      from public.bookings
     where status in ('pending', 'reassignment_needed', 'pending_payment')
       and (assigned_driver_id is null or coalesce((metadata->>'requires_reassignment')::boolean, false) = true)
       and coalesce((metadata->>'reassignment_count')::integer, 0) < 3
       and coalesce((metadata->>'no_eligible_driver_pending_reset')::boolean, false) = false
     order by created_at asc
     limit p_max_assignments
  loop
    begin
      v_result := public.assign_pending_booking_to_driver(v_booking.id);
      if (v_result->>'status') = 'assigned' then
        v_assigned_count := v_assigned_count + 1;
      elsif (v_result->>'status') = 'no_eligible_driver' then
        v_no_driver_count := v_no_driver_count + 1;
      else
        v_failed_count := v_failed_count + 1;
      end if;
    exception when others then
      v_failed_count := v_failed_count + 1;
    end;
  end loop;

  return jsonb_build_object(
    'assigned', v_assigned_count,
    'no_eligible_driver', v_no_driver_count,
    'failed', v_failed_count,
    'total_processed', v_assigned_count + v_no_driver_count + v_failed_count
  );
end;
$$;

-- Permissions
revoke all on function public.current_main_operating_partner_id() from public;
grant execute on function public.current_main_operating_partner_id() to authenticated, anon;

revoke all on function public.driver_active_assignment_count(uuid) from public;
grant execute on function public.driver_active_assignment_count(uuid) to authenticated, anon;

-- r049 (per Lux §4 SECURITY): auto-assignment mutator locked to service_role only.
-- Ordinary authenticated end users must NOT mutate dispatch state.
-- Authenticated grant revoked; service_role (privileged backend scheduler/operator) only.
revoke all on function public.assign_pending_booking_to_driver(text, uuid) from public;
revoke execute on function public.assign_pending_booking_to_driver(text, uuid) from authenticated;
revoke execute on function public.assign_pending_booking_to_driver(text, uuid) from anon;
grant execute on function public.assign_pending_booking_to_driver(text, uuid) to service_role;

-- r049 (per Lux §4 SECURITY): batch auto-assignment mutator locked to service_role only.
revoke all on function public.auto_assign_pending_bookings(integer) from public;
revoke execute on function public.auto_assign_pending_bookings(integer) from authenticated;
revoke execute on function public.auto_assign_pending_bookings(integer) from anon;
grant execute on function public.auto_assign_pending_bookings(integer) to service_role;

commit;
