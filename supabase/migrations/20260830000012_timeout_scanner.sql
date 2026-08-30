-- r048: Smallest factual 30-minute timeout scanner for assignment_sent bookings
-- Per Lux §3 r048 directives: implement literal timeout path with TIMEOUT_REASSIGN truthful event,
-- exclude timed-out driver from immediate reassignment, respect reassignment cap, no-driver/max-cap
-- remains recoverable, test timeout->different driver / no driver / cap / accepted-never-timed-out.
--
-- Scheduler-neutral: this is the scanner that an external scheduler (cron / pg_cron / external)
-- calls on a tick (e.g. every minute). It only invokes the timeout path on bookings that meet
-- the small set of eligibility conditions.

-- Configurable timeout window (default 30 minutes, matches CommunicationConfig.settings.ASSIGNMENT_TIMEOUT_MINUTES)
CREATE OR REPLACE FUNCTION public.assignment_timeout_minutes()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT 30;
$$;

-- Get the candidate set: assignment_sent bookings older than timeout window AND still unaccepted.
-- Per Lux §3: "scan only assignment_sent bookings older than 30 minutes and still unaccepted"
-- "still unaccepted" means assignment_accepted_at IS NULL AND status is still assignment_sent.
-- We additionally exclude accepted bookings to prove they are never timed out.
CREATE OR REPLACE FUNCTION public.find_expired_assignments(p_now timestamptz DEFAULT now())
RETURNS TABLE (
    booking_id text,
    current_driver_id uuid,
    assignment_sent_at_db timestamptz,
    reassignment_count integer,
    age_minutes numeric
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        b.id::text AS booking_id,
        b.assigned_driver_id AS current_driver_id,
        b.assignment_sent_at AS assignment_sent_at_db,
        COALESCE((b.metadata ->> 'reassignment_count')::integer, 0) AS reassignment_count,
        EXTRACT(EPOCH FROM (p_now - b.assignment_sent_at)) / 60.0 AS age_minutes
    FROM public.bookings b
    WHERE b.status = 'assignment_sent'
      AND b.assigned_driver_id IS NOT NULL
      AND b.assignment_accepted_at IS NULL
      AND b.assignment_sent_at IS NOT NULL
      AND b.assignment_sent_at <= p_now - (public.assignment_timeout_minutes() || ' minutes')::interval
      AND COALESCE((b.metadata ->> 'no_eligible_driver_pending_reset')::boolean, false) = false
      AND COALESCE((b.metadata ->> 'reassignment_count')::integer, 0) < 3;
$$;

-- r049 (per Lux §4 SECURITY): remove anon grant from timeout scanner/mutator.
-- Anonymous web clients must NOT invoke timeout reassignment logic.
-- Locked to service_role (privileged backend scheduler) only.
REVOKE EXECUTE ON FUNCTION public.find_expired_assignments(timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.find_expired_assignments(timestamptz) FROM anon;
REVOKE EXECUTE ON FUNCTION public.find_expired_assignments(timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.find_expired_assignments(timestamptz) TO service_role;

-- Per-booking timeout handler: marks the expired offer as TIMEOUT_REASSIGN event,
-- sets the driver as declined in metadata so the immediate reassignment excludes them,
-- then re-invokes the r047 assignment path.
-- Returns the new assignment state.
CREATE OR REPLACE FUNCTION public.timeout_expired_assignment(p_booking_id text, p_now timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_booking record;
    v_old_driver_id uuid;
    v_old_status text;
    v_old_reassignment_count integer;
    v_metadata jsonb;
    v_existing_events jsonb;
    v_event jsonb;
    v_event_count integer;
    v_new_result jsonb;
BEGIN
    -- Lock the booking row
    SELECT * INTO v_booking
    FROM public.bookings
    WHERE id::text = p_booking_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'booking_not_found', 'booking_id', p_booking_id);
    END IF;

    v_old_status := v_booking.status;
    v_old_driver_id := v_booking.assigned_driver_id;
    v_metadata := COALESCE(v_booking.metadata, '{}'::jsonb);

    -- Defensive checks: only act on assignment_sent bookings that are past the window
    IF v_booking.status <> 'assignment_sent' THEN
        RETURN jsonb_build_object('status', 'not_in_assignment_sent', 'booking_id', p_booking_id, 'current_status', v_booking.status);
    END IF;
    IF v_booking.assignment_accepted_at IS NOT NULL THEN
        RETURN jsonb_build_object('status', 'already_accepted', 'booking_id', p_booking_id);
    END IF;
    IF v_booking.assignment_sent_at IS NULL THEN
        RETURN jsonb_build_object('status', 'no_assignment_sent_at', 'booking_id', p_booking_id);
    END IF;
    IF v_booking.assignment_sent_at > p_now - (public.assignment_timeout_minutes() || ' minutes')::interval THEN
        RETURN jsonb_build_object('status', 'not_yet_expired', 'booking_id', p_booking_id);
    END IF;
    IF COALESCE((v_metadata ->> 'reassignment_count')::integer, 0) >= 3 THEN
        RETURN jsonb_build_object('status', 'cap_reached', 'booking_id', p_booking_id);
    END IF;

    -- Snapshot pre-timeout state for audit purposes BEFORE we mutate anything
    v_old_driver_id := v_booking.assigned_driver_id;
    v_old_reassignment_count := COALESCE((v_metadata ->> 'reassignment_count')::integer, 0);

    -- Reset booking to allow reassignment: status=reassignment_needed, clear driver + token
    -- This minimal reset preserves all existing metadata so we don't lose any audit data
    UPDATE public.bookings SET
        status = 'reassignment_needed',
        assigned_driver_id = NULL,
        assignment_token = NULL,
        assignment_sent_at = NULL
    WHERE id::text = p_booking_id;

    -- Now invoke the r047 assignment path with the timed-out driver excluded.
    -- The r047 function will set a fresh metadata (with new driver, new auto_assigned_at, etc.).
    SELECT (public.assign_pending_booking_to_driver(p_booking_id, v_old_driver_id))::text::jsonb
    INTO v_new_result;

    -- After reassignment: re-read the booking's CURRENT metadata (set by r047),
    -- and APPEND our TIMEOUT_REASSIGN audit event to metadata.timeout_events.
    -- This preserves both r047's metadata structure AND the truthful timeout audit trail.
    -- Read r047's metadata AFTER its UPDATE; then APPEND timeout audit fields via
    -- || concatenation (same pattern r047 uses) to preserve all r047 fields.
    SELECT metadata INTO v_metadata
    FROM public.bookings
    WHERE id::text = p_booking_id;

    v_existing_events := COALESCE(v_metadata -> 'timeout_events', '[]'::jsonb);
    v_event_count := jsonb_array_length(v_existing_events);
    v_event := jsonb_build_object(
        'event', 'TIMEOUT_REASSIGN',
        'from_driver_id', v_old_driver_id,
        'to_driver_id', v_new_result ->> 'driver_id',
        'at', p_now,
        'reassignment_count_before', v_old_reassignment_count,
        'reassignment_count_after', (v_new_result ->> 'reassignment_count')::integer,
        'reason', 'driver_did_not_accept_within_timeout_window'
    );

    -- Use || concatenation to add timeout audit fields while preserving all r047 fields
    UPDATE public.bookings SET metadata = v_metadata || jsonb_build_object(
        'timeout_events', v_existing_events || jsonb_build_array(v_event),
        'last_timeout_event', 'TIMEOUT_REASSIGN',
        'last_timeout_at', p_now
    ) WHERE id::text = p_booking_id;

    RETURN jsonb_build_object(
        'status', v_new_result ->> 'status',
        'booking_id', p_booking_id,
        'old_driver_id', v_old_driver_id,
        'new_driver_id', v_new_result ->> 'driver_id',
        'new_driver_name', v_new_result ->> 'driver_name',
        'assignment_token', v_new_result ->> 'assignment_token',
        'reassignment_count', v_new_result ->> 'reassignment_count',
        'lifecycle_event', 'TIMEOUT_REASSIGN',
        'audit_event_count', v_event_count + 1
    );
END;
$$;

-- r049 (per Lux §4 SECURITY): timeout mutator locked to service_role only.
REVOKE EXECUTE ON FUNCTION public.timeout_expired_assignment(text, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.timeout_expired_assignment(text, timestamptz) FROM anon;
REVOKE EXECUTE ON FUNCTION public.timeout_expired_assignment(text, timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.timeout_expired_assignment(text, timestamptz) TO service_role;

-- Batch timeout scanner: scans for all expired assignments and invokes timeout_expired_assignment
-- Returns a summary with each booking's result.
CREATE OR REPLACE FUNCTION public.scan_and_timeout_expired_assignments(p_now timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_expired record;
    v_result jsonb;
    v_results jsonb := '[]'::jsonb;
    v_timeout_count integer := 0;
    v_reassigned_count integer := 0;
    v_no_driver_count integer := 0;
BEGIN
    FOR v_expired IN
        SELECT * FROM public.find_expired_assignments(p_now)
    LOOP
        v_result := public.timeout_expired_assignment(v_expired.booking_id, p_now);
        v_results := v_results || jsonb_build_array(v_result);
        v_timeout_count := v_timeout_count + 1;
        IF v_result ->> 'status' = 'assigned' THEN
            v_reassigned_count := v_reassigned_count + 1;
        ELSIF v_result ->> 'status' = 'no_eligible_driver' THEN
            v_no_driver_count := v_no_driver_count + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'scanned_at', p_now,
        'timeout_window_minutes', public.assignment_timeout_minutes(),
        'total_expired', v_timeout_count,
        'reassigned_to_different_driver', v_reassigned_count,
        'no_eligible_driver', v_no_driver_count,
        'results', v_results
    );
END;
$$;

-- r049 (per Lux §4 SECURITY): batch timeout scanner locked to service_role only.
REVOKE EXECUTE ON FUNCTION public.scan_and_timeout_expired_assignments(timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.scan_and_timeout_expired_assignments(timestamptz) FROM anon;
REVOKE EXECUTE ON FUNCTION public.scan_and_timeout_expired_assignments(timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.scan_and_timeout_expired_assignments(timestamptz) TO service_role;
