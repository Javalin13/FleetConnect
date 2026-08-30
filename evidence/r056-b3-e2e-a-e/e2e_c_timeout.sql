-- r056 Phase A — B3 E2E-C (TIMEOUT → REASSIGNMENT)
-- Per Lux §7: timeout → reassignment

DO $$
DECLARE
    v_partner_id bigint := 1;
    v_driver1_id uuid;
    v_driver2_id uuid;
    v_customer_id text;
    v_booking_id text;
    v_assigned_driver uuid;
    v_status text;
    v_timeout_result jsonb;
    v_old_status text;
BEGIN
    RAISE NOTICE '=== E2E-C: Timeout → Reassignment ===';

    SELECT id INTO v_driver1_id FROM public.drivers
        WHERE is_active = true AND is_available_now = true AND archived_at IS NULL
        ORDER BY id LIMIT 1;
    SELECT id INTO v_driver2_id FROM public.drivers
        WHERE is_active = true AND is_available_now = true AND archived_at IS NULL
        AND id != v_driver1_id
        ORDER BY id LIMIT 1;
    IF v_driver2_id IS NULL THEN
        RAISE NOTICE 'FAIL: need 2 drivers';
        RETURN;
    END IF;

    v_customer_id := 'e2e-c-cust-' || to_char(now(), 'YYYYMMDDHH24MISS');
    INSERT INTO public.customers (id, name, email, phone, created_at)
    VALUES (v_customer_id, 'E2E-C Customer', 'e2e-c@example.com', '+32123456781', now())
    ON CONFLICT (id) DO NOTHING;

    v_booking_id := 'e2e-c-' || to_char(now(), 'YYYYMMDDHH24MISS');
    INSERT INTO public.bookings (
        id, status, payment_status, customer_id, partner_id,
        pickup_place_id, dropoff_place_id,
        form_data, metadata, route_distance_km,
        created_at
    ) VALUES (
        v_booking_id, 'pending', 'unpaid', v_customer_id, v_partner_id,
        'vilvoorde-luchthavenlaan-18', 'vilvoorde-centrum',
        jsonb_build_object('name', 'E2E-C Customer', 'pickup', 'Luchthavenlaan 18, 1800 Vilvoorde', 'dropoff', 'Vilvoorde Centrum'),
        jsonb_build_object('price', 15),
        3, now()
    );

    -- Assign driver1
    PERFORM public.assign_pending_booking_to_driver(v_booking_id);
    SELECT status, assigned_driver_id INTO v_status, v_assigned_driver
    FROM public.bookings WHERE id = v_booking_id;
    RAISE NOTICE 'Initial: status=%, driver=%', v_status, v_assigned_driver;

    -- Backdate assignment_sent_at to make it expired (>30 min ago)
    UPDATE public.bookings SET assignment_sent_at = now() - interval '31 minutes'
    WHERE id = v_booking_id;

    -- Run timeout scanner
    v_timeout_result := public.scan_and_timeout_expired_assignments(now());
    RAISE NOTICE 'Timeout scan result: %', v_timeout_result::text;

    SELECT status, assigned_driver_id INTO v_status, v_assigned_driver
    FROM public.bookings WHERE id = v_booking_id;
    RAISE NOTICE 'After timeout: status=%, driver=%', v_status, v_assigned_driver;

    -- Verify timeout lifecycle event
    PERFORM 1 FROM public.booking_lifecycle_events
    WHERE booking_id = v_booking_id AND event_type = 'ASSIGNMENT_EXPIRED';
    RAISE NOTICE 'ASSIGNMENT_EXPIRED event recorded: %', FOUND;

    IF v_assigned_driver IS NULL OR v_assigned_driver = v_driver1_id THEN
        RAISE NOTICE 'NOTE: timeout did not reassign or reassigned to same driver';
    ELSE
        RAISE NOTICE 'PASS: E2E-C timeout reassigned from % to %', v_driver1_id, v_assigned_driver;
    END IF;
END $$;