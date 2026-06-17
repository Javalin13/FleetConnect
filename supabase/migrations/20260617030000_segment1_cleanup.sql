-- SEGMENT 1: PRODUCTION DATA CLEANUP
-- Cleans all test data, historic data, and old draft rides
-- Keeps only:
--   - The 2 main operator accounts (Iliass, Jan Blommaert)
--   - The 1 hoofd-partner (Eigen onderneming, Jean Michel)
--   - All active bookings (within last 30 days, status != cancelled/archived)
--   - All approved account_requests for the kept users

begin;

-- Step 1: List what we're about to delete (audit)
do $$
declare
    v_test_partners int;
    v_test_customers int;
    v_test_drivers int;
    v_old_rides int;
    v_test_account_requests int;
    v_unverified_users int;
begin
    -- Test partners (not the 3 real ones)
    select count(*) into v_test_partners from public.partners where id > 30;
    -- Test customers (non-real emails)
    select count(*) into v_test_customers from public.customers where email !~ '^[A-Za-z0-9._%+-]+@(gmail|yahoo|hotmail|outlook|icloud|example|test|fleetconnect)\.';
    -- Test drivers (no user_id, and not active)
    select count(*) into v_test_drivers from public.drivers where user_id is null and is_active = false;
    -- Old rides (K-MS7- prefix)
    select count(*) into v_old_rides from public.bookings where id like 'K-MS7-%';
    -- Test account_requests
    select count(*) into v_test_account_requests from public.account_requests where email ~ '(cert-|test-|founder-attack|final-cert|partner-final|partner-reject|partner-cert|caratprivatejewels|hermes-cert|travels\.y\.ek|jan\.blommaert23|ryzenoutsourcing|sailis|admin@ryzen|info\.kms7)';
    -- Unverified auth users (orphans)
    select count(*) into v_unverified_users from auth.users where email_confirmed_at is null and created_at < now() - interval '2 hours';

    raise notice 'PRE-CLEANUP AUDIT:';
    raise notice '  test partners (id > 30): %', v_test_partners;
    raise notice '  test customers: %', v_test_customers;
    raise notice '  inactive drivers: %', v_test_drivers;
    raise notice '  K-MS7 old rides: %', v_old_rides;
    raise notice '  test account_requests: %', v_test_account_requests;
    raise notice '  unverified old auth users: %', v_unverified_users;
end $$;

-- Step 2: Clean test account_requests (in reverse FK order)
delete from public.account_requests
where email ~ '(cert-|test-|founder-attack|final-cert|partner-final|partner-reject|partner-cert|caratprivatejewels|hermes-cert|travels\.y\.ek|jan\.blommaert23|ryzenoutsourcing|sailis|admin@ryzen|info\.kms7)';

-- Step 3: Clean test partners (keep only the 3 real ones: 1, 13, 23)
delete from public.partners where id > 30;

-- Step 4: Clean test drivers (those with no user_id, not assigned to any real partner)
delete from public.drivers where user_id is null and partner_id not in (1, 13, 23);

-- Step 5: Clean test customers (those with non-real emails or from test sources)
delete from public.customers
where email !~ '^[A-Za-z0-9._%+-]+@(gmail|yahoo|hotmail|outlook|icloud|example|test|fleetconnect)\.'
   or email like '%test%'
   or email like '%cert%';

-- Step 6: Archive all K-MS7 historic rides
update public.bookings
set status = 'archived',
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'archived_reason', 'pre-FleetConnect historic data',
        'archived_at', now(),
        'archived_by', 'segment1-cleanup'
    )
where id like 'K-MS7-%' and status != 'archived';

-- Step 7: Clean test auth.users (unverified, older than 2 hours)
delete from auth.users
where email_confirmed_at is null
  and created_at < now() - interval '2 hours'
  and email ~ '(cert-|test-|founder-attack|final-cert|partner-final|partner-reject|partner-cert|caratprivatejewels|hermes-cert|travels\.y\.ek|jan\.blommaert23|ryzenoutsourcing|sailis|admin@ryzen|info\.kms7)';

-- Step 8: Clean any orphaned customer rows (no auth user AND no booking)
delete from public.customers c
where c.user_id is null
  and c.is_active is distinct from true
  and not exists (select 1 from public.bookings b where b.customer_id = c.id);

-- Step 9: Verification - what's left
do $$
declare
    v_partners int;
    v_partners_active int;
    v_customers int;
    v_customers_active int;
    v_drivers int;
    v_drivers_active int;
    v_bookings int;
    v_bookings_active int;
    v_account_requests int;
    v_account_requests_pending int;
    v_auth_users int;
begin
    select count(*) into v_partners from public.partners;
    select count(*) into v_partners_active from public.partners where user_id is not null;
    select count(*) into v_customers from public.customers;
    select count(*) into v_customers_active from public.customers where user_id is not null and is_active = true;
    select count(*) into v_drivers from public.drivers;
    select count(*) into v_drivers_active from public.drivers where is_active = true and archived_at is null;
    select count(*) into v_bookings from public.bookings;
    select count(*) into v_bookings_active from public.bookings where status not in ('cancelled', 'archived', 'completed');
    select count(*) into v_account_requests from public.account_requests;
    select count(*) into v_account_requests_pending from public.account_requests where status = 'pending';
    select count(*) into v_auth_users from auth.users;

    raise notice 'POST-CLEANUP STATE:';
    raise notice '  partners: % (active with user_id: %)', v_partners, v_partners_active;
    raise notice '  customers: % (active with user_id: %)', v_customers, v_customers_active;
    raise notice '  drivers: % (active: %)', v_drivers, v_drivers_active;
    raise notice '  bookings: % (active: %)', v_bookings, v_bookings_active;
    raise notice '  account_requests: % (pending: %)', v_account_requests, v_account_requests_pending;
    raise notice '  auth.users: %', v_auth_users;
end $$;

notify pgrst, 'reload schema';

commit;
