begin;

-- Refactor public.operator_assign_driver to support direct driver reassignment across active statuses
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
  if not public.is_operator() then
    raise exception 'Operator access required';
  end if;

  select * into v_booking from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;

  -- Support direct reassignment for any pending or assigned status!
  -- No need to force recalling first, we can do it automatically/cleanly.

  select * into v_driver from public.drivers where id = p_driver_id and is_active is not false;
  if not found then raise exception 'Active driver not found'; end if;

  v_token := coalesce(nullif(p_assignment_token, ''), gen_random_uuid()::text);

  update public.bookings
  set status = 'assignment_sent',
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
          'reassignment_pending_driver_acceptance', true,
          'assignment_requested_at', now()
        )
  where id = p_booking_id
  returning * into v_booking;

  return to_jsonb(v_booking);
end;
$$;

revoke all on function public.operator_assign_driver(text, uuid, text) from public;
revoke all on function public.operator_assign_driver(text, uuid, text) from anon;
grant execute on function public.operator_assign_driver(text, uuid, text) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
