-- =====================================================================
-- r056 Phase G-A: CANONICAL GREENFIELD BASELINE (PRODUCTION-SAFE)
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
-- PRODUCTION-SAFE DESIGN (per Lux d3a5d92 §2):
--   This file creates ONLY FleetConnect-owned application objects. It
--   does NOT create or modify:
--     - `auth.users` (Supabase platform manages)
--     - `auth.uid()` / `auth.jwt()` / `auth.role()` (Supabase helpers)
--     - `anon` / `authenticated` / `service_role` roles (Supabase
--       platform manages; this file relies on them existing)
--   On real Supabase, these platform objects already exist when this
--   migration runs.
--
--   The local-harness auth stubs (auth.users, auth.uid(), roles) live
--   in `supabase/local_harness/00_local_auth_stubs.sql` and are applied
--   ONLY by the local test harness, NEVER by the production apply
--   manifest.
--
-- WHY THIS FILE (per Lux 2195825 §3):
--   The historical SQL set is NOT a complete greenfield bootstrap.
--   Phase 4 identity closure assumes `customers` and `bookings` exist.
--   The full migration chain fails on empty database without these
--   foundational tables.
--
-- PROVENANCE (per Lux d3a5d92 §3):
--   Column lists + types verified from:
--     (a) Production REST probe of `rreqjjrmvytnwnsidmqi` (anon-readable
--         columns verified via PostgREST select=* probe)
--     (b) `phase4_identity_closure.sql` ALTER TABLE statements
--     (c) Cross-reference with all migration file column references
--         (qualified `<table>.<col>` syntax + type checks)
--     (d) FK column type verification: `bookings.assigned_driver_id =
--         v_driver.id` (where v_driver is `public.drivers`) →
--         bookings.assigned_driver_id MUST match drivers.id
--     (e) bookings.partner_id references partners.id (BIGSERIAL) →
--         bookings.partner_id MUST be BIGINT
--   See `evidence/r056-phase-g-canonical-baseline-provenance.md` for
--   full column-by-column provenance.
--
-- FOUNDATIONAL ID/TYPE DOCTRINE (per Lux d3a5d92 §3 — corrected):
--   Foundational PKs use MIXED types, not all TEXT:
--     - `customers.id`  : TEXT         (e.g. "CUST-2024-001")
--     - `partners.id`   : BIGSERIAL    (auto-incrementing int8)
--     - `drivers.id`    : UUID         (extensions.gen_random_uuid())
--     - `bookings.id`   : TEXT         (e.g. "BK-2024-001234")
--   FK columns MUST match the PK type they reference:
--     - `bookings.customer_id`            : TEXT     -> customers.id
--     - `bookings.partner_id`             : BIGINT   -> partners.id
--     - `bookings.assigned_driver_id`     : UUID     -> drivers.id
--     - `bookings.user_id`                : UUID     -> auth.users.id
--     - `drivers.partner_id`              : BIGINT   -> partners.id
--     - `drivers.user_id`                 : UUID     -> auth.users.id
--     - `customers.user_id`               : UUID     -> auth.users.id
--     - `partners.user_id`                : UUID     -> auth.users.id
--     - `onderaannemers.user_id`          : UUID     -> auth.users.id
--     - `onderaannemers.primary_dispatch_driver_id` : UUID -> drivers.id
--     - `booking_lifecycle_events.booking_id`        : TEXT    -> bookings.id
--     - `booking_lifecycle_events.driver_id`         : UUID    -> drivers.id
--     - `booking_lifecycle_events.partner_id`        : BIGINT  -> partners.id
--     - `booking_lifecycle_events.previous_driver_id`: UUID    -> drivers.id
--
-- SCOPE (this file ONLY creates):
--   1. extensions schema + pgcrypto (safe on Supabase; idempotent)
--   2. public.customers        (TEXT id)
--   3. public.partners         (BIGSERIAL id)
--   4. public.drivers          (UUID id)
--   5. public.onderaannemers   (BIGSERIAL id; synonym for partners;
--                                referenced by 20260616020000 RLS policy)
--   6. public.bookings         (TEXT id, with FKs to customers/partners/drivers)
--   7. public.booking_lifecycle_events (TEXT id; referenced by
--                                20260830000012_timeout_scanner.sql)
--
-- DOES NOT CREATE (created by later migrations or platform-managed):
--   - auth.users / auth.uid() / auth.jwt() / auth.role()  — Supabase platform
--   - anon / authenticated / service_role roles             — Supabase platform
--   - All 15+ tables that ARE created by timestamped migrations
--   - All RPCs
--   - All RLS policies
--
-- COLUMN UNKNOWNS (flagged separately, NOT guessed):
--   - bookings: 30 confirmed columns; some legacy fields like
--     `form_data`, `metadata`, `extras`, `flight_number` JSONB shape
--     not exhaustively verified; defaulted to jsonb
--   - customers: ~20 columns (includes account lifecycle flags from r055+)
--   - partners: ~17 columns (includes authorize_admin_role scopes + dispatch)
--   - drivers: ~14 columns (includes partner FK + dispatch driver code)
--   - booking_lifecycle_events: shape inferred from migration
--     `20260830000012_timeout_scanner.sql` reference
--
-- IDEMPOTENT: yes (CREATE TABLE IF NOT EXISTS, CREATE INDEX IF NOT EXISTS,
-- ALTER TABLE ... ADD COLUMN IF NOT EXISTS)
--
-- DEPENDENCIES:
--   This file assumes auth.users exists (REFERENCES auth.users(id)).
--   On real Supabase: auth.users is platform-managed and exists.
--   On local harness: supabase/local_harness/00_local_auth_stubs.sql
--   must run FIRST.
--
-- AUTHOR: PRIME (r056 Phase G-H, post Lux d3a5d92)
-- DATE: 2026-09-01
-- =====================================================================

-- 0. Extensions schema + pgcrypto (Supabase-safe; idempotent)
-- Real Supabase has `extensions` schema + pgcrypto; CREATE IF NOT EXISTS
-- is safe in both production and local harness.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 1. Foundational table: customers
-- PK: TEXT (e.g. "CUST-2024-001")
-- FK: user_id UUID REFERENCES auth.users(id) (Supabase platform-managed)
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

-- 2. Foundational table: partners
-- PK: BIGSERIAL (auto-incrementing int8; primary key for partner rows)
-- FK: user_id UUID REFERENCES auth.users(id) (Supabase platform-managed)
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
    primary_dispatch_driver_id UUID  -- UUID, NOT TEXT (matches drivers.id)
);

CREATE INDEX IF NOT EXISTS idx_partners_user_id ON public.partners(user_id);
CREATE INDEX IF NOT EXISTS idx_partners_email ON public.partners(email);
CREATE INDEX IF NOT EXISTS idx_partners_is_hoofd ON public.partners(is_hoofd);

-- 3. Foundational table: drivers
-- PK: UUID DEFAULT extensions.gen_random_uuid()
-- FK: partner_id BIGINT REFERENCES public.partners(id)
--     user_id  UUID    REFERENCES auth.users(id)
-- PROVENANCE: v_driver.id is `public.drivers.id` (UUID); all
--     `bookings.assigned_driver_id` and lifecycle event driver_id
--     columns are UUID to match this PK type.
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

-- 3b. Foundational table: onderaannemers (COMPATIBILITY / DORMANT)
-- Dutch synonym for partners. Referenced by
-- `20260616020000_onderaannemers_policies.sql` which adds RLS
-- policies on this table.
--
-- LABEL: COMPATIBILITY / DORMANT
-- This table is created to satisfy the historical migration chain's
-- references. It is NOT independently proven to be active in legacy
-- production. If authenticated legacy schema introspection later
-- confirms it is dormant in production, no action is needed — the
-- RLS policies are harmless on an empty table. If authenticated
-- introspection later confirms it is active in production, this
-- baseline correctly reproduces the expected schema (BIGSERIAL id
-- + UUID primary_dispatch_driver_id, matching partners/driver types).
--
-- Production schema in legacy used BIGSERIAL id, with
-- primary_dispatch_driver_id being UUID (matching drivers.id).
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

-- 4. Foundational table: bookings
-- PK: TEXT (e.g. "BK-2024-001234")
-- FKs:
--   customer_id        TEXT    -> public.customers(id)
--   partner_id         BIGINT  -> public.partners(id)
--   assigned_driver_id UUID    -> public.drivers(id)
--   user_id            UUID    -> auth.users(id)
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
    assigned_driver JSONB DEFAULT '{}'::jsonb,  -- legacy text/jsonb snapshot
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

-- 5. Foundational table: booking_lifecycle_events
-- PK: TEXT (default extensions.gen_random_uuid()::text — generates UUID
--     then casts to text, preserving the textual PK convention used
--     elsewhere in the lifecycle tables)
-- FKs (MIXED types to match parent tables):
--   booking_id         TEXT    -> public.bookings(id)
--   driver_id          UUID    -> public.drivers(id)
--   partner_id         BIGINT  -> public.partners(id)
--   previous_driver_id UUID    -> public.drivers(id)
-- PROVENANCE: this table is referenced by 20260830000012_timeout_scanner.sql
-- and is populated by the timeout scanner's INSERT.
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

-- 6. Access model: this file does NOT issue explicit GRANTs on the
-- foundational tables, because that would bypass any later RLS. The
-- migration chain handles all grants. In Supabase, when a table has
-- RLS enabled and a role has no explicit GRANT, access is denied; this
-- is the desired default. When RLS is NOT yet enabled (e.g. on a
-- freshly-created table before phase4_identity_closure runs the
-- ENABLE ROW LEVEL SECURITY statements), access is governed by the
-- standard PostgreSQL privilege system, which by default is also
-- deny for non-owners — but PRIME does not generalize that
-- "no RLS = deny" because PostgreSQL privilege semantics are not the
-- same as RLS semantics. The chain enables RLS on every foundational
-- table via later migrations; the no-RLS interim is brief.

-- Done
-- This file MUST be applied BEFORE any timestamped migration file
-- (including the unprefixed phase4_identity_closure.sql and the
-- Phase F 20260831000001 mail migration).
--
-- On real Supabase: apply via Supabase CLI migration push or Dashboard
-- SQL Editor. Supabase provides auth.users, auth.uid/jwt/role, and
-- the standard roles. This file's REFERENCES auth.users(id) is valid.
--
-- On local harness: apply supabase/local_harness/00_local_auth_stubs.sql
-- FIRST (creates the stubs this file depends on), then this file.
