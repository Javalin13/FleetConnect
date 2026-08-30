-- r056 Phase A — B3 E2E-B (DECLINE → DIFFERENT DRIVER)
-- Per Lux §7: decline → different eligible driver reassignment

DO $$
DECLARE
    v_partner_id bigint := 1;
    v_driver1_id uuid;
    v_driver2_id uuid;
    v_customer_id text;
    v_booking_id text;
    v_assigned_driver uuid;
    v_status text;
    v_result jsonb;
BEGIN
    RAISE NOTICE '=== E2E-B: Decline → Different Driver Reassignment ===';

    -- Pick two different drivers
    SELECT id INTO v_driver1_id FROM public.drivers
        WHERE is_active = true AND is_available_now = true AND archived_at IS NULL
        ORDER BY id LIMIT 1;
    SELECT id INTO v_driver2_id FROM public.drivers
        WHERE is_active = true AND is_available_now = true AND archived_at IS NULL
        AND id != v_driver1_id
        ORDER BY id LIMIT 1;
    IF v_driver2_id IS NULL THEN
        RAISE NOTICE 'FAIL: need at least 2 available drivers';
        RETURN;
    END IF;
    RAISE NOTICE 'Driver1: %, Driver2: %', v_driver1_id, v_driver2_id;

    v_customer_id := 'e2e-b-cust-' || to_char(now(), 'YYYYMMDDHH24MISS');
    INSERT INTO public.customers (id, name, email, phone, created_at)
    VALUES (v_customer_id, 'E2E-B Customer', 'e2e-b@example.com', '+32123456780', now())
    ON CONFLICT (id) DO NOTHING;

    v_booking_id := 'e2e-b-' || to_char(now(), 'YYYYMMDDHH24MISS');
    INSERT INTO public.bookings (
        id, status, payment_status, customer_id, partner_id,
        pickup_place_id, dropoff_place_id,
        form_data, metadata, route_distance_km,
        created_at
    ) VALUES (
        v_booking_id, 'pending', 'unpaid', v_customer_id, v_partner_id,
        'vilvoorde-luchthavenlaan-18', 'vilvoorde-centrum',
        jsonb_build_object(
            'name', 'E2E-B Customer',
            'pickup', 'Luchthavenlaan 18, 1800 Vilvoorde',
            'dropoff', 'Vilvoorde Centrum'
        ),
        jsonb_build_object('price', 15),
        3, now()
    );
    RAISE NOTICE 'Booking created: %', v_booking_id;

    -- First auto-assign (should pick driver1)
    v_result := public.assign_pending_booking_to_driver(v_booking_id);
    SELECT status, assigned_driver_id INTO v_status, v_assigned_driver
    FROM public.bookings WHERE id = v_booking_id;
    RAISE NOTICE 'First assignment: status=%, driver=%', v_status, v_assigned_driver;
    IF v_assigned_driver != v_driver1_id THEN
        RAISE NOTICE 'NOTE: First assignment picked % (expected %)', v_assigned_driver, v_driver1_id;
    END IF;

    -- Driver1 declines
    UPDATE public.bookings SET status = 'reassignment_needed', assignment_declined_at = now(),
        metadata = metadata || jsonb_build_object('declined_driver_id', v_driver1_id::text)
    WHERE id = v_booking_id;
    INSERT INTO public.booking_lifecycle_events (booking_id, event_type, driver_id, actor_role, metadata, created_at)
    VALUES (v_booking_id, 'ASSIGNMENT_DECLINED', v_driver1_id, 'driver',
        jsonb_build_object('declined_driver_id', v_driver1_id::text), now());
    RAISE NOTICE 'Driver1 declined';

    -- Reassign — must pick a DIFFERENT driver
    v_result := public.assign_pending_booking_to_driver(v_booking_id);
    SELECT status, assigned_driver_id INTO v_status, v_assigned_driver
    FROM public.bookings WHERE id = v_booking_id;
    RAISE NOTICE 'After reassign: status=%, driver=%', v_status, v_assigned_driver;

    IF v_assigned_driver IS NULL OR v_assigned_driver = v_driver1_id THEN
        RAISE NOTICE 'FAIL: reassign did not pick a different driver (got %)', v_assigned_driver;
        RETURN;
    END IF;

    RAISE NOTICE 'PASS: E2E-B declined driver %, reassigned to %', v_driver1_id, v_assigned_driver;
END $$;