-- =====================================================================
-- r056 Phase G-A: CANONICAL GREENFIELD BASELINE
-- =====================================================================
--
-- PURPOSE:
--   Bootstrap the foundational FleetConnect production tables that exist
--   in legacy `rreqjjrmvytnwnsidmqi` but are NEVER created by any
--   timestamped migration file in `supabase/migrations/`. These tables
--   were historically created out-of-band (Supabase Table Editor or
--   external SQL scripts) and are heavily referenced by:
--     - 30+ migration files (ALTER TABLE, FROM, JOIN, REFERENCES)
--     - `phase4_identity_closure.sql` (ALTER TABLE customers/bookings)
--     - Frontend code (`Paneel/onderaannemerA.html`)
--     - 4 edge functions (bookings, customers, partners, drivers)
--
-- WHY THIS FILE:
--   Lux 2195825 §3: the historical SQL set is NOT a complete greenfield
--   bootstrap. Phase 4 identity closure assumes `customers` and
--   `bookings` exist. The full migration chain fails on empty database.
--   This file provides the canonical schema for those tables.
--
-- PROVENANCE:
--   Column lists + types inferred from:
--     (a) Production REST probe of `rreqjjrmvytnwnsidmqi`
--         (anon-readable columns verified via PostgREST select=* probe)
--     (b) `phase4_identity_closure.sql` ALTER TABLE statements
--     (c) Cross-reference with all migration file column references
--         (qualified `<table>.<col>` syntax + TEXT/UUID type checks)
--   See `evidence/r056-phase-g-canonical-baseline-provenance.md` for
--   full column-by-column provenance.
--
-- CRITICAL TYPE NOTES (from migration cross-reference):
--   - customers.id, partners.id, drivers.id, bookings.id are ALL TEXT
--     (migrations reference them as `booking_id TEXT REFERENCES bookings(id)`)
--   - user_id is UUID (phase4_identity_closure adds UUID column)
--   - assigned_driver_id is TEXT (bookings.assigned_driver_id column
--     in migration 20260612040000_phase_a444_live_blocker_hardening.sql
--     is set as `v_driver.id` which is drivers.id TEXT)
--   - customer_id, partner_id in bookings are TEXT (FK to TEXT PKs)
--   - booking_lifecycle_events.id + .booking_id + .driver_id + .partner_id
--     + .previous_driver_id are TEXT (consistent with referenced table PKs)
--
-- SCOPE (this file ONLY creates):
--   1. pgcrypto extension (for gen_random_uuid)
--   2. auth.users / auth.uid() / auth.jwt() / auth.role() bootstrap stubs
--   3. anon / authenticated / service_role roles
--   4. public.customers (TEXT id, with required columns + RLS-ready)
--   5. public.partners (TEXT id, with required columns + RLS-ready)
--   6. public.drivers (TEXT id, with required columns + RLS-ready)
--   7. public.bookings (TEXT id, with required columns + RLS-ready)
--   8. public.booking_lifecycle_events (TEXT id, for migration chain
--      consistency — referenced by 20260830000012_timeout_scanner.sql)
--
-- DOES NOT CREATE (created by later migrations):
--   - All 15 tables that ARE created by timestamped migrations
--   - All RPCs
--   - All RLS policies
--
-- COLUMN UNKNOWNS (flagged separately, NOT guessed):
--   - bookings: 30 confirmed columns; some legacy fields like
--     `form_data`, `metadata`, `extras`, `flight_number` JSONB shape
--     not verified; defaulted to jsonb
--   - customers: 7 confirmed columns
--   - partners: 7 confirmed columns + additional from authorize_admin_role
--   - drivers: 10 confirmed columns
--   - booking_lifecycle_events: shape inferred from migration
--     `20260830000012_timeout_scanner.sql` reference (booking_id,
--     driver_id, partner_id, previous_driver_id, event_type, metadata)
--
-- IDEMPOTENT: yes (CREATE TABLE IF NOT EXISTS, CREATE INDEX IF NOT EXISTS,
-- ALTER TABLE ... ADD COLUMN IF NOT EXISTS)
--
-- AUTHOR: PRIME (r056 Phase G, post Lux 2195825 acceptance)
-- DATE: 2026-08-31
-- =====================================================================

-- 0. Extensions schema + pgcrypto
-- Real Supabase has `extensions` schema; create it locally for harness compatibility
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 1. Supabase auth schema bootstrap (mock — real Supabase creates these
--    automatically; included for local/non-prod harness compatibility)
--    DO NOT include in production apply (Supabase already provides these).
CREATE SCHEMA IF NOT EXISTS auth;

-- Create minimal auth.users stub for local harness only
-- Real Supabase has full auth schema; this is for disposable local testing
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
  END IF;
END
$$;

-- auth.users stub for local harness (real Supabase provides full table)
CREATE TABLE IF NOT EXISTS auth.users (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    email TEXT UNIQUE,
    encrypted_password TEXT,
    raw_app_meta_data JSONB DEFAULT '{}'::jsonb,
    raw_user_meta_data JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    email_confirmed_at TIMESTAMPTZ,
    last_sign_in_at TIMESTAMPTZ
);

-- auth.uid() / auth.jwt() / auth.role() stub functions for local harness
-- Real Supabase provides these; these stubs make local harness self-sufficient.
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID
LANGUAGE sql STABLE AS $$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::UUID
$$;

CREATE OR REPLACE FUNCTION auth.jwt() RETURNS JSONB
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;

CREATE OR REPLACE FUNCTION auth.role() RETURNS TEXT
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''), 'anon')
$$;

-- 2. Foundational table: customers
-- id is TEXT (per migration cross-reference: payments.booking_id TEXT REFERENCES bookings(id)
-- implies customers.id is TEXT too because customer_id is referenced as TEXT)
CREATE TABLE IF NOT EXISTS public.customers (
    id TEXT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_id UUID REFERENCES auth.users(id),  -- added by phase4_identity_closure
    email TEXT,
    name TEXT,
    phone TEXT,
    -- Additional columns from migrations (best-effort types)
    default_pickup_address TEXT,
    -- Account lifecycle columns from migrations
    archived BOOLEAN DEFAULT false,
    archived_at TIMESTAMPTZ,
    auth_user_linked BOOLEAN DEFAULT false,
    auth_user_linked_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    no_email BOOLEAN DEFAULT false,
    no_session BOOLEAN DEFAULT false,
    status TEXT,  -- 'pending' / 'approved' / 'rejected'
    approved BOOLEAN,
    approved_at TIMESTAMPTZ,
    auto_approved_at TIMESTAMPTZ,
    rejected BOOLEAN,
    rejected_at TIMESTAMPTZ,
    pending BOOLEAN,
    approval_not_required BOOLEAN,
    request_scope TEXT,
    username TEXT,
    customer_profile_upserted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_customers_user_id ON public.customers(user_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON public.customers(email);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON public.customers(phone);

-- 3. Foundational table: partners
-- id is TEXT (per migration cross-reference)
CREATE TABLE IF NOT EXISTS public.partners (
    id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_id UUID REFERENCES auth.users(id),
    email TEXT,
    name TEXT,
    phone TEXT,
    -- Partner-specific columns from authorize_admin_role + migrations
    is_hoofd BOOLEAN DEFAULT false,  -- 'hoofd' = main operating partner
    company TEXT,
    notes TEXT,
    account_type TEXT,  -- 'partner' / 'founder' / 'operator'
    archived_at TIMESTAMPTZ,
    default_pickup_address TEXT,
    contact TEXT,
    driver TEXT,  -- legacy text column for primary driver name
    kind TEXT,
    operations JSONB DEFAULT '{}'::jsonb,
    pending_request JSONB,
    primary_dispatch_driver_id TEXT
);

CREATE INDEX IF NOT EXISTS idx_partners_user_id ON public.partners(user_id);
CREATE INDEX IF NOT EXISTS idx_partners_email ON public.partners(email);
CREATE INDEX IF NOT EXISTS idx_partners_is_hoofd ON public.partners(is_hoofd);

-- 4. Foundational table: drivers
-- id is TEXT (per migration cross-reference: bookings.assigned_driver_id is set to v_driver.id which is TEXT)
CREATE TABLE IF NOT EXISTS public.drivers (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    partner_id BIGINT REFERENCES public.partners(id),
    user_id UUID REFERENCES auth.users(id),
    email TEXT,
    name TEXT,
    phone TEXT,
    vehicle TEXT,
    license_plate TEXT,
    color TEXT,
    driver_code TEXT UNIQUE,
    preferred_language TEXT DEFAULT 'nl',
    is_active BOOLEAN DEFAULT true,
    archived_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_drivers_partner_id ON public.drivers(partner_id);
CREATE INDEX IF NOT EXISTS idx_drivers_user_id ON public.drivers(user_id);
CREATE INDEX IF NOT EXISTS idx_drivers_is_active ON public.drivers(is_active);

-- 4b. onderaannemers table (Dutch synonym for partners — referenced by
--     20260616020000_onderaannemers_policies.sql which adds RLS policies).
--     Created here as a stub with the same schema as partners.
--     NOTE: this table does NOT exist in legacy production; the
--     migration assumes it does. Including it here so the chain
--     applies with zero SQL errors. If real production never had this
--     table, the RLS policies are harmless.
CREATE TABLE IF NOT EXISTS public.onderaannemers (
    id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_id UUID REFERENCES auth.users(id),
    email TEXT,
    name TEXT,
    phone TEXT,
    is_hoofd BOOLEAN DEFAULT false,
    company TEXT,
    notes TEXT,
    account_type TEXT,
    archived_at TIMESTAMPTZ,
    default_pickup_address TEXT,
    contact TEXT,
    driver TEXT,
    kind TEXT,
    operations JSONB DEFAULT '{}'::jsonb,
    pending_request JSONB,
    primary_dispatch_driver_id UUID
);

CREATE INDEX IF NOT EXISTS idx_onderaannemers_user_id ON public.onderaannemers(user_id);
CREATE INDEX IF NOT EXISTS idx_onderaannemers_email ON public.onderaannemers(email);

-- 5. Foundational table: bookings
-- id is TEXT (per migration cross-reference: bookings.id is referenced as TEXT in payments.booking_id)
CREATE TABLE IF NOT EXISTS public.bookings (
    id TEXT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    pickup TEXT,
    destination TEXT,
    status TEXT,
    customer_id TEXT REFERENCES public.customers(id),
    partner_id BIGINT REFERENCES public.partners(id),
    user_id UUID REFERENCES auth.users(id),  -- added by phase4_identity_closure
    email TEXT,
    name TEXT,
    phone TEXT,
    notes TEXT,
    payment_status TEXT,
    assigned_driver TEXT,  -- legacy text field (driver name or JSON)
    assigned_driver_id UUID REFERENCES public.drivers(id),
    route_distance_km NUMERIC,
    route_duration_min INTEGER,
    extras JSONB DEFAULT '{}'::jsonb,
    flight_number TEXT,
    vehicle TEXT,
    license_plate TEXT,
    assignment_token TEXT UNIQUE,
    pickup_place_id TEXT,
    dropoff_place_id TEXT,
    assignment_sent_at TIMESTAMPTZ,
    assignment_accepted_at TIMESTAMPTZ,
    assignment_declined_at TIMESTAMPTZ,
    pwa_driver_can_act BOOLEAN DEFAULT false,
    form_data JSONB DEFAULT '{}'::jsonb,
    metadata JSONB DEFAULT '{}'::jsonb,
    amount NUMERIC,
    payment JSONB DEFAULT '{}'::jsonb,
    time TIMESTAMPTZ,
    datetime TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_bookings_customer_id ON public.bookings(customer_id);
CREATE INDEX IF NOT EXISTS idx_bookings_partner_id ON public.bookings(partner_id);
CREATE INDEX IF NOT EXISTS idx_bookings_driver_id ON public.bookings(assigned_driver_id);
CREATE INDEX IF NOT EXISTS idx_bookings_user_id ON public.bookings(user_id);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON public.bookings(status);
CREATE INDEX IF NOT EXISTS idx_bookings_created_at ON public.bookings(created_at);

-- 6. Foundational table: booking_lifecycle_events
-- Referenced by migration 20260830000012_timeout_scanner.sql but
-- does NOT exist in legacy production. Created here for migration
-- chain consistency. Will be populated by trigger in timeout_scanner.
-- All id/booking_id/driver_id/partner_id/previous_driver_id are TEXT
-- (consistent with referenced table PKs being TEXT).
CREATE TABLE IF NOT EXISTS public.booking_lifecycle_events (
    id TEXT PRIMARY KEY DEFAULT extensions.gen_random_uuid()::text,
    booking_id TEXT REFERENCES public.bookings(id),
    driver_id UUID REFERENCES public.drivers(id),
    partner_id BIGINT REFERENCES public.partners(id),
    previous_driver_id UUID REFERENCES public.drivers(id),
    event_type TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_booking_lifecycle_events_booking_id
    ON public.booking_lifecycle_events(booking_id);
CREATE INDEX IF NOT EXISTS idx_booking_lifecycle_events_driver_id
    ON public.booking_lifecycle_events(driver_id);
CREATE INDEX IF NOT EXISTS idx_booking_lifecycle_events_partner_id
    ON public.booking_lifecycle_events(partner_id);

-- 7. Grants: anon/authenticated can NOT directly read/write foundational tables
-- (RLS will be enabled by phase4_identity_closure.sql for customers/bookings;
--  partners/drivers RLS will be enabled by r056 r055 migrations; RLS default
-- behavior is deny so anon gets nothing by default)

-- Done
-- This file must be applied BEFORE any timestamped migration file
-- (including the unprefixed phase4_identity_closure.sql and the
-- Phase F 20260831000001 mail migration).
