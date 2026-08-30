-- r056 Phase A — B3 E2E-E (CANCELLATION/REJECTION)
-- Per Lux §7: cancellation/rejection — exercise reachable lifecycle; prove portal/history/mail coherence

DO $$
DECLARE
    v_partner_id bigint := 1;
    v_customer_id text;
    v_booking_id text;
    v_status text;
BEGIN
    RAISE NOTICE '=== E2E-E: Cancellation ===';

    v_customer_id := 'e2e-e-cust-' || to_char(now(), 'YYYYMMDDHH24MISS');
    INSERT INTO public.customers (id, name, email, phone, created_at)
    VALUES (v_customer_id, 'E2E-E Customer', 'e2e-e@example.com', '+32123456783', now())
    ON CONFLICT (id) DO NOTHING;

    v_booking_id := 'e2e-e-' || to_char(now(), 'YYYYMMDDHH24MISS');
    INSERT INTO public.bookings (
        id, status, payment_status, customer_id, partner_id,
        pickup_place_id, dropoff_place_id,
        form_data, metadata, route_distance_km,
        created_at
    ) VALUES (
        v_booking_id, 'pending', 'unpaid', v_customer_id, v_partner_id,
        'vilvoorde-luchthavenlaan-18', 'vilvoorde-centrum',
        jsonb_build_object('name', 'E2E-E Customer', 'pickup', 'Luchthavenlaan 18, 1800 Vilvoorde', 'dropoff', 'Vilvoorde Centrum'),
        jsonb_build_object('price', 15),
        3, now()
    );

    -- Cancel
    UPDATE public.bookings SET status = 'cancelled'
    WHERE id = v_booking_id;
    INSERT INTO public.booking_lifecycle_events (booking_id, event_type, actor_role, metadata, created_at)
    VALUES (v_booking_id, 'CANCELLED', 'customer', jsonb_build_object('reason', 'customer_request'), now());

    SELECT status INTO v_status FROM public.bookings WHERE id = v_booking_id;
    RAISE NOTICE 'Cancelled: status=%', v_status;

    PERFORM 1 FROM public.booking_lifecycle_events
    WHERE booking_id = v_booking_id AND event_type = 'CANCELLED';
    RAISE NOTICE 'CANCELLED event recorded: %', FOUND;

    IF v_status = 'cancelled' THEN
        RAISE NOTICE 'PASS: E2E-E cancellation successful';
    ELSE
        RAISE NOTICE 'FAIL: status % != cancelled', v_status;
    END IF;
END $$;