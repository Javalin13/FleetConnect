-- Phase G-L Wave 4: Pure-SQL staging transform
--
-- Mission   : 2026-08-29-fleetconnect-operational-recovery
-- Round     : r056 Phase G-L executable Wave 4 data/auth remap package
-- Predecessors:
--   - supabase/migrations/20260902000001_phase_g_l_additive_legacy_user_id_audit_column.sql
--     (additive schema migration: legacy_user_id column on auth-linked app tables)
--   - supabase/operations/phase_g_l_wave4/sql/phase_g_l_staging_create.sql
--     (creates staging schema + four staging tables)
--   - Founder runner has loaded CSVs into staging.* via psql \copy
--
-- PURPOSE:
--   Pure-SQL transform:
--     1. Hard fail-closed preflight (BLOCKER 7 fix from Lux cfb0e9b §7):
--        - staging partners: no NULL emails where email is required for mapping
--        - staging partners: no duplicate emails
--        - staging drivers: every partner_legacy_pk resolves to exactly one
--          staging partner
--        - staging bookings: every partner_legacy_pk (when not NULL) resolves
--          to exactly one staging partner
--     2. Transform INSERTs (per-table):
--        - source.user_id -> legacy_user_id
--        - target.user_id := NULL
--        - business PK/FKs preserved
--        - partner_id resolved by email match (with hard preflight above)
--     3. In-transaction invariant verification (BLOCKER 2 fix):
--        - V0/V1/V3 verification queries INSIDE this script
--        - ABORT (RAISE EXCEPTION) if any invariant fails
--        - COMMIT only after this script returns success
--
-- NON-SCOPE:
--   - This file is PURE SQL. No \copy. No hard-coded paths. No shell variables.
--   - The Founder runner invokes this file via \i INSIDE a single psql
--     transaction. If this file raises EXCEPTION, the transaction is
--     aborted by the runner (ROLLBACK).
--   - This file does NOT create users in auth.users (Option C1 Dashboard only).
--   - This file does NOT apply target user_id from old->new mapping
--     (that's phase_g_l_mapping_apply.sql, run after user creation).

-- ===========================================================================
-- PART A: HARD FAIL-CLOSED PREFLIGHT (BLOCKER 7 fix)
-- ===========================================================================
-- Every check below uses RAISE EXCEPTION to abort the transaction. The
-- Founder runner's ROLLBACK ensures no canonical target rows are written.

-- A.1: Staging partners with NULL email (cannot map to target partners by email)
DO $$
DECLARE bad INT;
BEGIN
  SELECT count(*) INTO bad FROM staging.partners WHERE email IS NULL;
  IF bad > 0 THEN
    RAISE EXCEPTION 'Phase G-L preflight FAILED: % staging.partners rows have NULL email (cannot resolve to target partners)', bad;
  END IF;
END$$;

-- A.2: Staging partners with duplicate emails (would produce non-deterministic
-- LEFT JOIN in transform; Lux cfb0e9b §7 explicit hard fail)
DO $$
DECLARE bad INT;
BEGIN
  SELECT count(*) INTO bad
  FROM (
    SELECT email FROM staging.partners GROUP BY email HAVING count(*) > 1
  ) d;
  IF bad > 0 THEN
    RAISE EXCEPTION 'Phase G-L preflight FAILED: % staging.partners duplicate email groups (cannot resolve partner mapping deterministically)', bad;
  END IF;
END$$;

-- A.3: Staging drivers with partner_legacy_pk that does not match any
-- staging partner (orphan driver.partner_legacy_pk)
DO $$
DECLARE bad INT;
BEGIN
  SELECT count(*) INTO bad
  FROM staging.drivers d
  WHERE d.partner_legacy_pk IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM staging.partners p WHERE p.legacy_pk = d.partner_legacy_pk);
  IF bad > 0 THEN
    RAISE EXCEPTION 'Phase G-L preflight FAILED: % staging.drivers rows have partner_legacy_pk not resolvable to staging.partners', bad;
  END IF;
END$$;

-- A.4: Staging bookings with partner_legacy_pk not resolvable to staging.partners
DO $$
DECLARE bad INT;
BEGIN
  SELECT count(*) INTO bad
  FROM staging.bookings b
  WHERE b.partner_legacy_pk IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM staging.partners p WHERE p.legacy_pk = b.partner_legacy_pk);
  IF bad > 0 THEN
    RAISE EXCEPTION 'Phase G-L preflight FAILED: % staging.bookings rows have partner_legacy_pk not resolvable to staging.partners', bad;
  END IF;
END$$;

-- A.5: Add the unique-email check at transform time too (race-condition guard):
-- target partners must have NO duplicate emails within the imported population.
-- This is checked AFTER the partners INSERT below.

-- ===========================================================================
-- PART B: TRANSFORM INSERTS INTO CANONICAL TARGETS
-- ===========================================================================

-- B.1: customers
INSERT INTO public.customers (
    id, created_at, updated_at,
    legacy_user_id, user_id,
    email, name, phone,
    default_pickup_address,
    archived, archived_at,
    auth_user_linked, auth_user_linked_at,
    is_active, no_email, no_session,
    status, approved, approved_at, auto_approved_at,
    rejected, rejected_at, pending,
    approval_not_required, request_scope,
    username, customer_profile_upserted_at
)
SELECT
    s.id, s.created_at, s.updated_at,
    s.user_id, NULL,
    s.email, s.name, s.phone,
    s.default_pickup_address,
    s.archived, s.archived_at,
    s.auth_user_linked, s.auth_user_linked_at,
    s.is_active, s.no_email, s.no_session,
    s.status, s.approved, s.approved_at, s.auto_approved_at,
    s.rejected, s.rejected_at, s.pending,
    s.approval_not_required, s.request_scope,
    s.username, s.customer_profile_upserted_at
FROM staging.customers s
ON CONFLICT (id) DO NOTHING;

-- ===========================================================================
-- B.1.5: OPTIONAL test-only failure injection (Lux ee52b1a §6.12)
-- Reads pg_temp.g_n_test_inject_flag injected by the Founder runner when
-- G_N_TEST_INJECT_FAIL=after_first_insert. If the marker row exists, RAISE
-- EXCEPTION after B.1 has committed at least one canonical row to
-- public.customers. The Founder runner's BEGIN/COMMIT transaction must roll
-- back the B.1 INSERT so that a verification query afterwards shows zero
-- customers with legacy_user_id IS NOT NULL.
--
-- Why a temp table marker instead of a psql variable / GUC:
--   - psql -v sets psql substitution variables, NOT PostgreSQL GUCs.
--   - current_setting('fc_g_n_test_inject_fail', true) returns NULL/empty
--     even when -v was supplied.
--   - The temp table marker is a single boolean check inside an existing
--     transaction, doesn't leak between sessions, and survives the heredoc
--     boundary.
--
-- Production runs leave G_N_TEST_INJECT_FAIL UNSET, the runner does not
-- create the marker row, the IF returns false, B.2 runs normally. The
-- production runner explicitly does NOT touch pg_temp.g_n_test_inject_flag.
--
-- The variable is set ONLY by the local test harness, NEVER by
-- run_wave4_import.sh in any production invocation.
-- ===========================================================================
DO $$
DECLARE
  marker_table regclass;
  marker_value TEXT;
BEGIN
  -- to_regclass returns NULL when the table doesn't exist (instead of raising),
  -- so production runs (no marker) take the IF branch is false and proceed.
  marker_table := to_regclass('pg_temp.g_n_test_inject_flag');
  IF marker_table IS NOT NULL THEN
    SELECT flag INTO marker_value FROM pg_temp.g_n_test_inject_flag WHERE flag = 'after_first_insert' LIMIT 1;
    IF marker_value = 'after_first_insert' THEN
      RAISE EXCEPTION 'Phase G-N TEST INJECTION: deliberate post-write failure after customers INSERT; transaction MUST roll back. Lux ee52b1a §6.12';
    END IF;
  END IF;
END$$;

-- B.2: partners
INSERT INTO public.partners (
    created_at, updated_at,
    legacy_user_id, user_id,
    email, name, phone,
    is_hoofd, company, notes, account_type,
    archived_at, default_pickup_address,
    contact, driver, kind,
    operations, pending_request, primary_dispatch_driver_id
)
SELECT
    s.created_at, s.updated_at,
    s.user_id, NULL,
    s.email, s.name, s.phone,
    s.is_hoofd, s.company, s.notes, s.account_type,
    s.archived_at, s.default_pickup_address,
    s.contact, s.driver, s.kind,
    s.operations, s.pending_request, s.primary_dispatch_driver_id
FROM staging.partners s
ON CONFLICT DO NOTHING;

-- A.5 deferred check: target partners email uniqueness among imported rows.
-- (Performed AFTER partners insert so we can use the actual target rows.)
DO $$
DECLARE bad INT;
BEGIN
  SELECT count(*) INTO bad
  FROM (
    SELECT email FROM public.partners GROUP BY email HAVING count(*) > 1
  ) d;
  IF bad > 0 THEN
    RAISE EXCEPTION 'Phase G-L preflight FAILED: target partners have % duplicate-email groups post-import (transform ambiguity)', bad;
  END IF;
END$$;

-- B.3: drivers
-- partner_id resolved by LEFT JOIN staging.partners on email match.
-- Hard preflight in PART A guarantees unique staging-partner emails, so
-- the LEFT JOIN is deterministic.
INSERT INTO public.drivers (
    id, created_at, updated_at, partner_id,
    legacy_user_id, user_id,
    email, name, phone, vehicle, license_plate, color,
    driver_code, preferred_language, is_active, archived_at
)
SELECT
    s.id, s.created_at, s.updated_at,
    p_new.id,
    s.user_id, NULL,
    s.email, s.name, s.phone, s.vehicle, s.license_plate, s.color,
    s.driver_code, s.preferred_language, s.is_active, s.archived_at
FROM staging.drivers s
LEFT JOIN staging.partners sp ON sp.legacy_pk = s.partner_legacy_pk
LEFT JOIN public.partners p_new ON p_new.email = sp.email
ON CONFLICT (id) DO NOTHING;

-- B.4: bookings
-- customer_id TEXT in legacy == same value in target customers.id (TEXT PK)
-- partner_legacy_pk -> new partners.id by email match
-- driver_legacy_uuid == same value in target drivers.id (UUID PK)
INSERT INTO public.bookings (
    id, created_at,
    pickup, destination, status,
    customer_id, partner_id,
    legacy_user_id, user_id,
    email, name, phone, notes, payment_status,
    assigned_driver, assigned_driver_id,
    route_distance_km, route_duration_min,
    extras, flight_number, vehicle, license_plate,
    assignment_token, pickup_place_id, dropoff_place_id,
    assignment_sent_at, assignment_accepted_at, assignment_declined_at,
    pwa_driver_can_act, form_data, metadata,
    amount, payment, time, datetime
)
SELECT
    s.id, s.created_at,
    s.pickup, s.destination, s.status,
    s.customer_id,
    p_new.id,
    s.user_id, NULL,
    s.email, s.name, s.phone, s.notes, s.payment_status,
    s.assigned_driver, s.driver_legacy_uuid,
    s.route_distance_km, s.route_duration_min,
    s.extras, s.flight_number, s.vehicle, s.license_plate,
    s.assignment_token, s.pickup_place_id, s.dropoff_place_id,
    s.assignment_sent_at, s.assignment_accepted_at, s.assignment_declined_at,
    s.pwa_driver_can_act, s.form_data, s.metadata,
    s.amount, s.payment, s.time, s.datetime
FROM staging.bookings s
LEFT JOIN staging.partners sp ON sp.legacy_pk = s.partner_legacy_pk
LEFT JOIN public.partners p_new ON p_new.email = sp.email
ON CONFLICT (id) DO NOTHING;

-- ===========================================================================
-- PART C: IN-TRANSACTION INVARIANT VERIFICATION (BLOCKER 2 fix)
-- ===========================================================================
-- These checks must all return zero issues. If any check returns > 0,
-- RAISE EXCEPTION aborts the transaction; the Founder runner's ROLLBACK
-- ensures no canonical target rows persist.

-- C.1: V1 row-count parity (staging -> canonical)
DO $$
DECLARE
  src_customers INT; tgt_customers INT;
  src_partners  INT; tgt_partners  INT;
  src_drivers   INT; tgt_drivers   INT;
  src_bookings  INT; tgt_bookings  INT;
BEGIN
  SELECT count(*) INTO src_customers FROM staging.customers;
  SELECT count(*) INTO tgt_customers FROM public.customers WHERE legacy_user_id IS NOT NULL;
  IF src_customers <> tgt_customers THEN
    RAISE EXCEPTION 'V1 FAIL: customers row-count parity (src=%, tgt=%)', src_customers, tgt_customers;
  END IF;

  SELECT count(*) INTO src_partners FROM staging.partners;
  SELECT count(*) INTO tgt_partners FROM public.partners WHERE legacy_user_id IS NOT NULL;
  IF src_partners <> tgt_partners THEN
    RAISE EXCEPTION 'V1 FAIL: partners row-count parity (src=%, tgt=%)', src_partners, tgt_partners;
  END IF;

  SELECT count(*) INTO src_drivers FROM staging.drivers;
  SELECT count(*) INTO tgt_drivers FROM public.drivers WHERE legacy_user_id IS NOT NULL;
  IF src_drivers <> tgt_drivers THEN
    RAISE EXCEPTION 'V1 FAIL: drivers row-count parity (src=%, tgt=%)', src_drivers, tgt_drivers;
  END IF;

  SELECT count(*) INTO src_bookings FROM staging.bookings;
  SELECT count(*) INTO tgt_bookings FROM public.bookings WHERE legacy_user_id IS NOT NULL;
  IF src_bookings <> tgt_bookings THEN
    RAISE EXCEPTION 'V1 FAIL: bookings row-count parity (src=%, tgt=%)', src_bookings, tgt_bookings;
  END IF;
END$$;

-- C.2: V3 business-FK orphans (target -> parent table)
DO $$
DECLARE
  orphan_booking_customer    INT;
  orphan_booking_partner    INT;
  orphan_booking_driver     INT;
  orphan_driver_partner     INT;
BEGIN
  SELECT count(*) INTO orphan_booking_customer FROM public.bookings b
    WHERE b.customer_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.customers c WHERE c.id = b.customer_id);
  IF orphan_booking_customer > 0 THEN
    RAISE EXCEPTION 'V3 FAIL: % orphan booking.customer_id', orphan_booking_customer;
  END IF;

  SELECT count(*) INTO orphan_booking_partner FROM public.bookings b
    WHERE b.partner_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.partners p WHERE p.id = b.partner_id);
  IF orphan_booking_partner > 0 THEN
    RAISE EXCEPTION 'V3 FAIL: % orphan booking.partner_id (post-transform partner_id resolution failed)', orphan_booking_partner;
  END IF;

  SELECT count(*) INTO orphan_booking_driver FROM public.bookings b
    WHERE b.assigned_driver_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.drivers d WHERE d.id = b.assigned_driver_id);
  IF orphan_booking_driver > 0 THEN
    RAISE EXCEPTION 'V3 FAIL: % orphan booking.assigned_driver_id', orphan_booking_driver;
  END IF;

  SELECT count(*) INTO orphan_driver_partner FROM public.drivers d
    WHERE d.partner_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.partners p WHERE p.id = d.partner_id);
  IF orphan_driver_partner > 0 THEN
    RAISE EXCEPTION 'V3 FAIL: % orphan driver.partner_id (post-transform partner_id resolution failed)', orphan_driver_partner;
  END IF;
END$$;

-- C.3: target.user_id must be NULL everywhere (pre-mapping sanity; mapping-apply runs in a separate file)
DO $$
DECLARE bad INT;
BEGIN
  SELECT count(*) INTO bad
    FROM (SELECT user_id FROM public.customers WHERE user_id IS NOT NULL
          UNION ALL SELECT user_id FROM public.partners WHERE user_id IS NOT NULL
          UNION ALL SELECT user_id FROM public.drivers WHERE user_id IS NOT NULL
          UNION ALL SELECT user_id FROM public.bookings WHERE user_id IS NOT NULL) x;
  IF bad > 0 THEN
    RAISE EXCEPTION 'V-pre-mapping FAIL: % target.user_id values are NOT NULL pre-mapping (transform leaked legacy auth UUIDs into target auth FK)', bad;
  END IF;
END$$;

-- ===========================================================================
-- If we reach this point, all preflights + transform inserts + invariant
-- checks passed. The Founder runner will COMMIT the enclosing transaction.
-- ===========================================================================
DO $$ BEGIN RAISE NOTICE 'Phase G-L staging-transform OK: all preflights passed, all rows inserted, V1+V3+V-pre-mapping invariants green'; END $$;
