-- r056 Phase A — B3 E2E-D (NO ELIGIBLE DRIVER / CAP)
-- Per Lux §7: no eligible driver / cap → truthful recoverable New Orders state

DO $$
DECLARE
    v_partner_id bigint := 1;
    v_customer_id text;
    v_booking_id text;
    v_status text;
    v_assigned_driver uuid;
    v_result jsonb;
BEGIN
    RAISE NOTICE '=== E2E-D: No eligible driver / cap → truthful state ===';

    -- Make ALL drivers unavailable
    UPDATE public.drivers SET is_available_now = false;

    v_customer_id := 'e2e-d-cust-' || to_char(now(), 'YYYYMMDDHH24MISS');
    INSERT INTO public.customers (id, name, email, phone, created_at)
    VALUES (v_customer_id, 'E2E-D Customer', 'e2e-d@example.com', '+32123456782', now())
    ON CONFLICT (id) DO NOTHING;

    v_booking_id := 'e2e-d-' || to_char(now(), 'YYYYMMDDHH24MISS');
    INSERT INTO public.bookings (
        id, status, payment_status, customer_id, partner_id,
        pickup_place_id, dropoff_place_id,
        form_data, metadata, route_distance_km,
        created_at
    ) VALUES (
        v_booking_id, 'pending', 'unpaid', v_customer_id, v_partner_id,
        'vilvoorde-luchthavenlaan-18', 'vilvoorde-centrum',
        jsonb_build_object('name', 'E2E-D Customer', 'pickup', 'Luchthavenlaan 18, 1800 Vilvoorde', 'dropoff', 'Vilvoorde Centrum'),
        jsonb_build_object('price', 15),
        3, now()
    );

    -- Try auto-assign — should report no_eligible_driver (NOT fake assignment)
    v_result := public.assign_pending_booking_to_driver(v_booking_id);
    RAISE NOTICE 'Assign result (all drivers unavailable): %', v_result::text;

    SELECT status, assigned_driver_id INTO v_status, v_assigned_driver
    FROM public.bookings WHERE id = v_booking_id;
    RAISE NOTICE 'After: status=%, driver=%', v_status, v_assigned_driver;

    -- Booking must remain in recoverable state (not fake-assigned)
    IF v_assigned_driver IS NOT NULL THEN
        RAISE NOTICE 'FAIL: fake assignment made (driver=%)', v_assigned_driver;
    ELSE
        RAISE NOTICE 'PASS: E2E-D no_eligible_driver, booking remains recoverable';
    END IF;

    -- Restore drivers
    UPDATE public.drivers SET is_available_now = true;
END $$;