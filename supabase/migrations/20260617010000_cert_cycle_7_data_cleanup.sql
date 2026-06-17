-- Cert Cycle 7 — Data integrity cleanup migration (v2)
-- Fixes the ON CONFLICT issue: customers has UNIQUE on email, not just on id

begin;

-- === 1. Remove test data from this cert cycle validation run ===
delete from public.account_requests
where metadata->>'source' = 'cert-validation'
  and created_at > now() - interval '1 hour';

-- === 2. Link orphaned bookings to customers ===
-- For each booking without customer_id that has a matching auth user,
-- either use the existing customer row or create a new one.
do $$
declare
    rec record;
    v_existing_customer_id text;
    v_new_customer_id text;
    v_rows int := 0;
begin
    for rec in
        select b.id as booking_id, b.email, b.name
        from public.bookings b
        where (b.customer_id is null or b.customer_id = '')
          and b.email is not null
          and exists (select 1 from auth.users u where lower(u.email) = lower(b.email))
          and b.status not in ('cancelled', 'archived', 'completed')
    loop
        -- Check if a customer row already exists for this email
        select id into v_existing_customer_id
        from public.customers
        where lower(email) = lower(rec.email)
        limit 1;

        if v_existing_customer_id is not null then
            -- Use the existing customer
            update public.bookings
            set customer_id = v_existing_customer_id
            where id = rec.booking_id;
        else
            -- Create a new customer row
            v_new_customer_id := 'CUST-' || substring(regexp_replace(lower(rec.email), '[^a-z0-9]', '', 'gi') from 1 for 30);

            insert into public.customers (id, user_id, name, email, phone, is_active, created_at, updated_at)
            select v_new_customer_id, u.id, coalesce(rec.name, rec.email), lower(rec.email), '', true, now(), now()
            from auth.users u where lower(u.email) = lower(rec.email);

            update public.bookings
            set customer_id = v_new_customer_id
            where id = rec.booking_id;
        end if;

        v_rows := v_rows + 1;
    end loop;
    raise notice 'Linked % orphaned bookings to customers', v_rows;
end $$;

-- === 3. Mark pre-Phase-A (K-MS7) bookings as archived ===
update public.bookings
set status = 'archived',
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('archived_reason', 'pre-Phase-A test data', 'archived_at', now())
where id like 'K-MS7-%'
  and status not in ('archived', 'cancelled');

-- === 4. Reject the duplicate jan.blommaert23 customer-scope request ===
update public.account_requests
set status = 'rejected',
    rejection_reason = 'Duplicate scope — user is registered as an operator, not a customer.',
    updated_at = now(),
    rejected_at = now(),
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'rejected_by', 'cert-cycle-7-cleanup',
        'rejected_at', now()
    )
where lower(email) = 'jan.blommaert23@gmail.com'
  and request_scope = 'customer'
  and status = 'approved';

-- === 5. Confirm jan.blommaert23's email ===
update auth.users
set email_confirmed_at = coalesce(email_confirmed_at, now()),
    updated_at = now()
where lower(email) = 'jan.blommaert23@gmail.com'
  and email_confirmed_at is null;

-- === Verification ===
do $$
declare
    v_orphan_count int;
    v_unverified_approved int;
    v_no_customer_active int;
    v_archived_kms7 int;
begin
    select count(*) into v_orphan_count
    from public.account_requests ar
    where ar.request_scope = 'customer'
      and ar.status = 'approved'
      and not exists (select 1 from public.customers c where lower(c.email) = lower(ar.email))
      and not exists (select 1 from auth.users u where u.id = ar.user_id);

    select count(*) into v_unverified_approved
    from public.account_requests ar
    join auth.users u on u.id = ar.user_id
    where ar.request_scope = 'customer' and ar.status = 'approved' and u.email_confirmed_at is null;

    select count(*) into v_no_customer_active
    from public.bookings
    where (customer_id is null or customer_id = '')
      and status not in ('cancelled', 'archived', 'completed');

    select count(*) into v_archived_kms7
    from public.bookings
    where id like 'K-MS7-%' and status = 'archived';

    raise notice 'Post-migration: orphan_approved=%  unverified_approved=%  no_customer_active_bookings=%  kms7_archived=%',
        v_orphan_count, v_unverified_approved, v_no_customer_active, v_archived_kms7;
end $$;

notify pgrst, 'reload schema';

commit;
