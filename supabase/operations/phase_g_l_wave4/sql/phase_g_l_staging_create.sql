-- Phase G-L Wave 4: Staging schema + table creation
--
-- Mission   : 2026-08-29-fleetconnect-operational-recovery
-- Round     : r056 Phase G-L executable Wave 4 data/auth remap package
-- Predecessor (additive schema migration, runs as part of Wave 4 pre-step):
--   supabase/migrations/20260902000001_phase_g_l_additive_legacy_user_id_audit_column.sql
--
-- SCOPE:
--   This file creates the staging schema and four staging tables that the
--   Founder runner's \copy commands load into. It is a PURE SQL file:
--   - no \copy
--   - no hard-coded paths
--   - no shell variable references
--   - idempotent (CREATE ... IF NOT EXISTS, DROP IF EXISTS)
--
-- EXECUTION ORDER (BLOCKER 3 fix from Lux cfb0e9b §3):
--   The Founder runner executes this file FIRST, before any \copy. Previously
--   the transform file created the staging tables AFTER \copy attempted to
--   load them, which fails on a clean target. This file fixes that order.
--
-- EXECUTION MODEL:
--   Founder-authenticated psql -f, run by the Founder runner (NOT interactively).
--   See supabase/operations/phase_g_l_wave4/runner/run_wave4.sh for the
--   exact sequence that includes this file.

-- ===========================================================================
-- Drop any pre-existing staging tables from a prior aborted run.
-- Idempotent on a clean target.
-- ===========================================================================
DROP TABLE IF EXISTS staging.customers CASCADE;
DROP TABLE IF EXISTS staging.partners  CASCADE;
DROP TABLE IF EXISTS staging.drivers   CASCADE;
DROP TABLE IF EXISTS staging.bookings  CASCADE;

CREATE SCHEMA IF NOT EXISTS staging;

-- ===========================================================================
-- customers staging (TEXT PK to match target; user_id kept as-is from CSV
-- to be transformed into legacy_user_id by phase_g_l_staging_transform.sql)
-- ===========================================================================
CREATE TABLE staging.customers (
    id               TEXT PRIMARY KEY,
    created_at       TIMESTAMPTZ,
    updated_at       TIMESTAMPTZ,
    user_id          UUID,
    email            TEXT,
    name             TEXT,
    phone            TEXT,
    default_pickup_address TEXT,
    archived         BOOLEAN,
    archived_at      TIMESTAMPTZ,
    auth_user_linked BOOLEAN,
    auth_user_linked_at TIMESTAMPTZ,
    is_active        BOOLEAN,
    no_email         BOOLEAN,
    no_session       BOOLEAN,
    status           TEXT,
    approved         BOOLEAN,
    approved_at      TIMESTAMPTZ,
    auto_approved_at TIMESTAMPTZ,
    rejected         BOOLEAN,
    rejected_at      TIMESTAMPTZ,
    pending          BOOLEAN,
    approval_not_required BOOLEAN,
    request_scope    TEXT,
    username         TEXT,
    customer_profile_upserted_at TIMESTAMPTZ
);

-- ===========================================================================
-- partners staging (BIGSERIAL PK in target; CSV value goes to legacy_pk column)
-- ===========================================================================
CREATE TABLE staging.partners (
    legacy_pk            BIGINT PRIMARY KEY,
    created_at           TIMESTAMPTZ,
    updated_at           TIMESTAMPTZ,
    user_id              UUID,
    email                TEXT,
    name                 TEXT,
    phone                TEXT,
    is_hoofd             BOOLEAN,
    company              TEXT,
    notes                TEXT,
    account_type         TEXT,
    archived_at          TIMESTAMPTZ,
    default_pickup_address TEXT,
    contact              TEXT,
    driver               TEXT,
    kind                 TEXT,
    operations           JSONB,
    pending_request      JSONB,
    primary_dispatch_driver_id UUID
);

-- ===========================================================================
-- drivers staging (UUID PK)
-- partner_legacy_pk -> new partners.id resolved in transform by email match
-- ===========================================================================
CREATE TABLE staging.drivers (
    id               UUID PRIMARY KEY,
    created_at       TIMESTAMPTZ,
    updated_at       TIMESTAMPTZ,
    partner_legacy_pk BIGINT,
    user_id          UUID,
    email            TEXT,
    name             TEXT,
    phone            TEXT,
    vehicle          TEXT,
    license_plate    TEXT,
    color            TEXT,
    driver_code      TEXT,
    preferred_language TEXT,
    is_active        BOOLEAN,
    archived_at      TIMESTAMPTZ
);

-- ===========================================================================
-- bookings staging (TEXT PK; business FKs in legacy form)
-- ===========================================================================
CREATE TABLE staging.bookings (
    id                       TEXT PRIMARY KEY,
    created_at               TIMESTAMPTZ,
    pickup                   TEXT,
    destination              TEXT,
    status                   TEXT,
    customer_id              TEXT,
    partner_legacy_pk        BIGINT,
    user_id                  UUID,
    email                    TEXT,
    name                     TEXT,
    phone                    TEXT,
    notes                    TEXT,
    payment_status           TEXT,
    assigned_driver          JSONB,
    driver_legacy_uuid       UUID,
    route_distance_km        NUMERIC,
    route_duration_min       INTEGER,
    extras                   JSONB,
    flight_number            TEXT,
    vehicle                  TEXT,
    license_plate            TEXT,
    assignment_token         TEXT,
    pickup_place_id          TEXT,
    dropoff_place_id         TEXT,
    assignment_sent_at       TIMESTAMPTZ,
    assignment_accepted_at   TIMESTAMPTZ,
    assignment_declined_at   TIMESTAMPTZ,
    pwa_driver_can_act       BOOLEAN,
    form_data                JSONB,
    metadata                 JSONB,
    amount                   NUMERIC,
    payment                  JSONB,
    time                     TIMESTAMPTZ,
    datetime                 TIMESTAMPTZ
);

-- ===========================================================================
-- Verification: all four staging tables exist with expected row counts = 0.
-- ===========================================================================
DO $$
DECLARE
  tbl TEXT;
  cnt INT;
  missing TEXT := '';
BEGIN
  FOREACH tbl IN ARRAY ARRAY['customers','partners','drivers','bookings']
  LOOP
    SELECT count(*) INTO cnt
    FROM information_schema.tables
    WHERE table_schema = 'staging' AND table_name = tbl;
    IF cnt = 0 THEN
      missing := missing || 'staging.' || tbl || ',';
    END IF;
  END LOOP;
  IF missing <> '' THEN
    RAISE EXCEPTION 'Phase G-L staging-create FAILED: missing tables: %', missing;
  END IF;
  RAISE NOTICE 'Phase G-L staging-create OK: staging.customers/partners/drivers/bookings present, empty';
END$$;
