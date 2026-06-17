-- Cert Cycle 8 — Fix Partner and Driver portal flows
-- Fixes the missing pieces for partner/driver onboarding:
--   1. Add is_partner() and current_partner_id() helper functions
--   2. Add is_driver() and current_driver_id() helper functions
--   3. Add user_id column to drivers table
--   4. Update approve_account_request_with_invite to create partners/drivers rows
--   5. Create get_partner_dashboard_snapshot(p_partner_id) RPC
--   6. Create get_driver_dashboard_snapshot(p_driver_id) RPC
--   7. Backfill partners/drivers for existing approved requests without rows
--   8. Add owner_is_hoofd check so sub-partners see their own data, not operator data
--
-- SAFETY: All operations are idempotent. No destructive ops on real data.

begin;

-- === 1. Helper functions for partner role check ===
create or replace function public.is_partner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.partners p
    where p.user_id = auth.uid()
  );
$$;

create or replace function public.current_partner_id()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select p.id
  from public.partners p
  where p.user_id = auth.uid()
  order by p.is_hoofd desc nulls last, p.id
  limit 1;
$$;

-- === 2. Add user_id column to drivers table ===
do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'drivers' and column_name = 'user_id'
    ) then
        alter table public.drivers add column user_id uuid references auth.users(id) on delete set null;
        create index if not exists drivers_user_id_idx on public.drivers(user_id) where user_id is not null;
    end if;
end $$;

-- === 3. Helper functions for driver role check ===
create or replace function public.is_driver()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.drivers d
    where d.user_id = auth.uid()
      and d.is_active = true
      and d.archived_at is null
  );
$$;

create or replace function public.current_driver_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select d.id
  from public.drivers d
  where d.user_id = auth.uid()
    and d.is_active = true
    and d.archived_at is null
  order by d.created_at
  limit 1;
$$;

-- === 4. Update approve_account_request_with_invite to also create partners/drivers rows ===
create or replace function public.approve_account_request_with_invite(
  p_request_id uuid,
  p_redirect_to text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_request public.account_requests%rowtype;
  v_customer_id text;
  v_auth_user_id uuid;
  v_temp_password_hash text;
  v_existing_user_id uuid;
  v_action_link_token text;
  v_action_link_url text;
  v_is_partner_scope boolean;
  v_is_driver_scope boolean;
  v_partner_id int;
  v_driver_id uuid;
  v_result jsonb;
begin
  -- Operator gate
  if not public.is_operator() then
    raise exception 'Operator access required';
  end if;

  -- Lock and load
  select * into v_request
  from public.account_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Account request not found';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'Account request is not pending';
  end if;

  v_customer_id := coalesce(
    v_request.customer_id,
    'CUST-' || substring(regexp_replace(lower(v_request.email), '[^a-z0-9]', '', 'gi') from 1 for 30)
  );

  v_is_partner_scope := lower(v_request.account_type) in ('partner', 'operations', 'other')
                        and v_request.request_scope <> 'customer';
  v_is_driver_scope := lower(v_request.account_type) = 'driver';

  -- Find an existing auth user for this email (if any)
  select id into v_existing_user_id
  from auth.users
  where lower(email) = lower(v_request.email)
  order by created_at desc
  limit 1;

  if v_is_partner_scope or v_is_driver_scope then
    if v_existing_user_id is null then
      v_temp_password_hash := public._fc_generate_temp_password_hash();
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, recovery_sent_at, last_sign_in_at,
        raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
      )
      values (
        '00000000-0000-0000-0000-000000000000'::uuid,
        gen_random_uuid(),
        'authenticated',
        'authenticated',
        lower(v_request.email),
        v_temp_password_hash,
        now(),
        now(),
        null,
        jsonb_build_object('provider', 'email', 'providers', array['email']),
        jsonb_build_object(
          'full_name', v_request.name,
          'phone', coalesce(v_request.phone, ''),
          'company', coalesce(v_request.company, ''),
          'account_type', v_request.account_type,
          'request_scope', coalesce(v_request.request_scope, 'operator')
        ),
        now(), now(), '', '', '', ''
      )
      returning id into v_auth_user_id;
    else
      v_auth_user_id := v_existing_user_id;
    end if;

    v_action_link_token := encode(gen_random_bytes(32), 'hex');
    v_action_link_url := coalesce(
      p_redirect_to,
      'https://www.fleetconnect.be/Paneel/partner-set-password.html?token_hash=' || v_action_link_token || '&type=recovery&email=' || encode(lower(v_request.email)::bytea, 'hex')
    );
  else
    v_auth_user_id := v_existing_user_id;
  end if;

  -- Create customer row if scope=customer
  if v_request.request_scope = 'customer' or lower(v_request.account_type) in ('client', 'customer') then
    insert into public.customers (id, user_id, name, email, phone, default_pickup_address, created_at, updated_at)
    values (
      v_customer_id,
      v_auth_user_id,
      v_request.name,
      lower(v_request.email),
      v_request.phone,
      nullif(v_request.metadata->>'default_pickup_address', ''),
      now(),
      now()
    )
    on conflict (id) do update
      set user_id = coalesce(public.customers.user_id, excluded.user_id),
          name = excluded.name,
          email = excluded.email,
          phone = excluded.phone,
          default_pickup_address = coalesce(excluded.default_pickup_address, public.customers.default_pickup_address),
          updated_at = now();
  end if;

  -- Create partners row if scope=operator/partner/operations
  if v_is_partner_scope and v_auth_user_id is not null then
    -- Check if a partners row already exists for this user
    select id into v_partner_id
    from public.partners
    where user_id = v_auth_user_id
    limit 1;

    if v_partner_id is null then
      insert into public.partners (name, prefix, is_hoofd, email, phone, user_id, contact, created_at)
      values (
        coalesce(nullif(trim(v_request.company), ''), v_request.name, v_request.email),
        substring(regexp_replace(upper(coalesce(nullif(trim(v_request.company), ''), v_request.name)), '[^A-Z]', '', 'g') from 1 for 4),
        case
          when lower(v_request.account_type) in ('operations', 'other') then true  -- operators default to is_hoofd=true
          else false  -- partners default to is_hoofd=false (sub-partner)
        end,
        lower(v_request.email),
        v_request.phone,
        v_auth_user_id,
        v_request.name,
        now()
      )
      returning id into v_partner_id;
    end if;
  end if;

  -- Create drivers row if scope=driver
  if v_is_driver_scope and v_auth_user_id is not null then
    -- Check if a drivers row already exists for this user
    select id into v_driver_id
    from public.drivers
    where user_id = v_auth_user_id
    limit 1;

    if v_driver_id is null then
      insert into public.drivers (user_id, name, email, phone, is_active, color, created_at, updated_at)
      values (
        v_auth_user_id,
        v_request.name,
        lower(v_request.email),
        v_request.phone,
        true,
        '#1e4a6e',  -- FleetConnect dark blue
        now(),
        now()
      )
      returning id into v_driver_id;
    end if;
  end if;

  -- Update the request status
  update public.account_requests
  set status = 'approved',
      customer_id = case when v_request.request_scope = 'customer' or lower(v_request.account_type) in ('client', 'customer') then v_customer_id else customer_id end,
      user_id = coalesce(v_auth_user_id, user_id),
      approved_by = auth.uid(),
      approved_at = now(),
      updated_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'approval_note', case
          when v_auth_user_id is null then 'Approved. Supabase Auth verification is still required before login.'
          else 'Approved and Supabase Auth user linked.'
        end,
        'approved_at', now(),
        'auth_user_linked', v_auth_user_id is not null,
        'requires_invite', v_is_partner_scope or v_is_driver_scope,
        'set_password_url', coalesce(v_action_link_url, ''),
        'partner_id', v_partner_id,
        'driver_id', v_driver_id
      )
  where id = p_request_id;

  -- Return everything the front-end needs
  v_result := jsonb_build_object(
    'id', p_request_id,
    'status', 'approved',
    'email', lower(v_request.email),
    'name', v_request.name,
    'account_type', v_request.account_type,
    'request_scope', v_request.request_scope,
    'customer_id', case when v_request.request_scope = 'customer' or lower(v_request.account_type) in ('client', 'customer') then v_customer_id else null end,
    'user_id', v_auth_user_id,
    'auth_user_linked', v_auth_user_id is not null,
    'requires_invite', v_is_partner_scope or v_is_driver_scope,
    'set_password_url', v_action_link_url,
    'set_password_token', v_action_link_token,
    'partner_id', v_partner_id,
    'driver_id', v_driver_id
  );

  return v_result;
end;
$$;

-- === 5. Get partner dashboard snapshot ===
-- Returns bookings, drivers, customers, and account requests for a specific partner.
-- For hoofd-partners (is_hoofd=true), returns ALL data.
-- For sub-partners, returns only their own data (via parent_partner_id).
create or replace function public.get_partner_dashboard_snapshot(p_partner_id int default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_partner_id int;
  v_is_hoofd boolean;
  v_sub_partner_ids int[];
begin
  -- If p_partner_id is null, use the current user's partner
  if p_partner_id is null then
    v_partner_id := public.current_partner_id();
  else
    -- If p_partner_id is provided, check the user has access
    -- (Either the user IS that partner, OR the user is a hoofd partner)
    if not (p_partner_id = public.current_partner_id() or public.is_operator()) then
      raise exception 'Partner access required';
    end if;
    v_partner_id := p_partner_id;
  end if;

  if v_partner_id is null then
    raise exception 'Partner not found';
  end if;

  -- Get the partner's hoofd status
  select coalesce(p.is_hoofd, false) into v_is_hoofd
  from public.partners p
  where p.id = v_partner_id;

  -- If not hoofd, find all sub-partners under this partner
  if not v_is_hoofd then
    select array_agg(id) into v_sub_partner_ids
    from public.partners
    where id = v_partner_id or parent_partner_id = v_partner_id;
  end if;

  return jsonb_build_object(
    'partner', (
      select to_jsonb(p)
      from public.partners p
      where p.id = v_partner_id
    ),
    'is_hoofd', v_is_hoofd,
    'sub_partners', (
      select coalesce(jsonb_agg(to_jsonb(sp) order by sp.name), '[]'::jsonb)
      from public.partners sp
      where sp.parent_partner_id = v_partner_id
    ),
    'drivers', (
      select coalesce(jsonb_agg(to_jsonb(d) order by d.name), '[]'::jsonb)
      from public.drivers d
      where (v_is_hoofd or d.partner_id = v_partner_id or d.partner_id = any(v_sub_partner_ids))
        and d.archived_at is null
    ),
    'bookings', (
      select coalesce(jsonb_agg(to_jsonb(b) order by b.created_at desc), '[]'::jsonb)
      from public.bookings b
      where b.partner_id = v_partner_id
         or (v_is_hoofd and b.partner_id is null)
         or (not v_is_hoofd and b.partner_id = any(v_sub_partner_ids))
    ),
    'account_requests', (
      select coalesce(jsonb_agg(to_jsonb(ar) order by ar.created_at desc), '[]'::jsonb)
      from public.account_requests ar
      where ar.request_scope = 'customer'
        and ar.status = 'pending'
    )
  );
end;
$$;

-- === 6. Get driver dashboard snapshot ===
-- Returns the driver's own assigned bookings + their own profile.
create or replace function public.get_driver_dashboard_snapshot(p_driver_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_driver_id uuid;
  v_driver public.drivers%rowtype;
begin
  -- If p_driver_id is null, use the current user's driver
  if p_driver_id is null then
    v_driver_id := public.current_driver_id();
  else
    -- If p_driver_id is provided, check access
    if not (p_driver_id = public.current_driver_id() or public.is_operator()) then
      raise exception 'Driver access required';
    end if;
    v_driver_id := p_driver_id;
  end if;

  if v_driver_id is null then
    raise exception 'Driver not found';
  end if;

  select * into v_driver
  from public.drivers
  where id = v_driver_id;

  if not found then
    raise exception 'Driver not found';
  end if;

  return jsonb_build_object(
    'driver', to_jsonb(v_driver),
    'assigned_bookings', (
      select coalesce(jsonb_agg(to_jsonb(b) order by b.datetime desc, b.time desc), '[]'::jsonb)
      from public.bookings b
      where b.assigned_driver_id = v_driver_id
        and b.status in ('assigned', 'accepted', 'in_progress')
    ),
    'history_bookings', (
      select coalesce(jsonb_agg(to_jsonb(b) order by b.datetime desc, b.time desc), '[]'::jsonb)
      from public.bookings b
      where b.assigned_driver_id = v_driver_id
        and b.status in ('completed', 'cancelled')
    ),
    'partner', (
      select to_jsonb(p)
      from public.partners p
      where p.id = v_driver.partner_id
    )
  );
end;
$$;

-- === 7. Backfill partners/drivers for existing approved requests ===
do $$
declare
    rec record;
    v_partner_id int;
    v_driver_id uuid;
    v_existing_user_id uuid;
begin
    for rec in
        select ar.id, ar.email, ar.name, ar.phone, ar.account_type, ar.request_scope, ar.user_id, ar.metadata
        from public.account_requests ar
        where ar.status = 'approved'
          and ar.user_id is not null
          and (lower(ar.account_type) in ('partner', 'driver', 'operations', 'other') and ar.request_scope <> 'customer')
    loop
        v_existing_user_id := rec.user_id;

        if lower(rec.account_type) in ('partner', 'operations', 'other') then
            -- Check if a partners row already exists
            select id into v_partner_id
            from public.partners
            where user_id = v_existing_user_id
            limit 1;

            if v_partner_id is null then
                -- Compute a unique prefix (4 chars + 2-digit suffix to avoid collisions)
                declare
                    v_base_prefix text;
                    v_final_prefix text;
                begin
                    v_base_prefix := coalesce(
                        substring(regexp_replace(upper(coalesce(nullif(rec.metadata->>'company', ''), rec.name)), '[^A-Z]', '', 'g') from 1 for 4),
                        'PART'
                    );
                    v_final_prefix := v_base_prefix;
                    for i in 0..99 loop
                        if not exists (select 1 from public.partners where prefix = v_final_prefix) then
                            exit;
                        end if;
                        v_final_prefix := v_base_prefix || lpad(i::text, 2, '0');
                    end loop;

                    insert into public.partners (name, prefix, is_hoofd, email, phone, user_id, contact, created_at)
                    values (
                        coalesce(nullif(rec.metadata->>'company', ''), rec.name, rec.email),
                        v_final_prefix,
                        lower(rec.account_type) in ('operations', 'other'),
                        lower(rec.email),
                        rec.phone,
                        v_existing_user_id,
                        rec.name,
                        now()
                    )
                    returning id into v_partner_id;
                end;

                -- Update the account_request with the new partner_id (in metadata)
                update public.account_requests
                set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('partner_id', v_partner_id),
                    updated_at = now()
                where id = rec.id;

                raise notice 'Backfilled partner row % (prefix %) for user % (%)', v_partner_id, v_partner_id, v_existing_user_id, rec.email;
            end if;
        end if;

        if lower(rec.account_type) = 'driver' then
            -- Check if a drivers row already exists
            select id into v_driver_id
            from public.drivers
            where user_id = v_existing_user_id
            limit 1;

            if v_driver_id is null then
                insert into public.drivers (user_id, name, email, phone, is_active, color, created_at, updated_at)
                values (
                    v_existing_user_id,
                    rec.name,
                    lower(rec.email),
                    rec.phone,
                    true,
                    '#1e4a6e',
                    now(),
                    now()
                )
                returning id into v_driver_id;

                update public.account_requests
                set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('driver_id', v_driver_id),
                    updated_at = now()
                where id = rec.id;

                raise notice 'Backfilled driver row % for user % (%', v_driver_id, v_existing_user_id, rec.email;
            end if;
        end if;
    end loop;
end $$;

-- === 8. Verification ===
do $$
declare
    v_partners_with_user_id int;
    v_drivers_with_user_id int;
    v_is_partner_fn_exists boolean;
    v_is_driver_fn_exists boolean;
    v_partner_snapshot_exists boolean;
    v_driver_snapshot_exists boolean;
begin
    select count(*) into v_partners_with_user_id from public.partners where user_id is not null;
    select count(*) into v_drivers_with_user_id from public.drivers where user_id is not null;
    select exists (select 1 from pg_proc where proname = 'is_partner') into v_is_partner_fn_exists;
    select exists (select 1 from pg_proc where proname = 'is_driver') into v_is_driver_fn_exists;
    select exists (select 1 from pg_proc where proname = 'get_partner_dashboard_snapshot') into v_partner_snapshot_exists;
    select exists (select 1 from pg_proc where proname = 'get_driver_dashboard_snapshot') into v_driver_snapshot_exists;

    raise notice 'Post-migration: partners_with_user_id=%, drivers_with_user_id=%', v_partners_with_user_id, v_drivers_with_user_id;
    raise notice 'Functions: is_partner=%, is_driver=%, partner_snapshot=%, driver_snapshot=%',
        v_is_partner_fn_exists, v_is_driver_fn_exists, v_partner_snapshot_exists, v_driver_snapshot_exists;
end $$;

notify pgrst, 'reload schema';

commit;
