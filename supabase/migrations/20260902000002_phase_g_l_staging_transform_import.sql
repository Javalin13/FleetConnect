-- Phase G-L Wave 4: Staging/transform import for auth-linked app tables
--
-- Mission   : 2026-08-29-fleetconnect-operational-recovery
-- Round     : r056 Phase G-L executable Wave 4 data/auth remap package
-- Predecessor: 20260902000001_phase_g_l_legacy_user_id_audit_column.sql
--               (additive legacy_user_id column on auth-linked app tables).
--
-- PURPOSE:
--   Replace the canonical doc's (r056-phase-g-i-data-auth-migration-mapping.md
--   §1.4) direct `\COPY customers/partners/drivers/bookings FROM ... CSV HEADER`
--   step with a deterministic staging/transform path that:
--     1. Imports legacy CSV rows into STAGING tables (no FK to auth.users,
--        so legacy UUIDs land without FK violation).
--     2. Transforms each row: legacy `user_id` → `legacy_user_id`,
--        target `user_id` := NULL.
--     3. Inserts the transformed row into the canonical target table with
--        PK/FK business relationships preserved (customer_id, partner_id,
--        assigned_driver_id).
--
--   This eliminates the Lux-identified execution blocker (Lux 2675123 §5):
--   "direct `\COPY customers/partners/drivers/bookings` from legacy exports
--    into the target tables. Those source rows contain legacy `user_id` UUIDs.
--    The target application tables have FK references to the new project's
--    `auth.users(id)`. ... a direct copy can: fail FK checks during import
--    because legacy auth UUIDs do not exist in target Auth; or create a
--    misleading execution contract if constraints are bypassed/disabled."
--
-- SCOPE:
--   Customers, partners, drivers, bookings. (onderaannemers is dormant;
--   if legacy introspection confirms it is active, the same pattern applies.)
--
-- PRECONDITIONS:
--   1. Wave 1 schema apply complete (canonical greenfield baseline + phase4
--      identity closure).
--   2. Phase G-L additive migration applied:
--      20260902000001_phase_g_l_legacy_user_id_audit_column.sql
--      (`legacy_user_id UUID NULL` present on all 5 auth-linked app tables).
--   3. Founder has authenticated legacy export CSVs delivered via the
--      supported authenticated path (r056-phase-g-i-data-auth-migration-mapping.md
--      §1.2 Path A1/A2/A3 — NOT chat/Telegram/Bridge/repo).
--   4. Founder has authenticated access to NEW_DB_URL via the Founder's
--      local secret store (1Password); PRIME does NOT hold NEW_DB_URL.
--
-- NON-SCOPE:
--   - This file does NOT create users in `auth.users` (Option C1 Dashboard
--     is the only canonical create-user path; that step is documented in
--     evidence/r056-phase-g-l-founder-execution-runbook.md §B and is
--     executed by the Founder between this staging/transform import and
--     the mapping-apply step in evidence/r056-phase-g-l-founder-execution-runbook.md §C).
--   - This file does NOT apply target `user_id` from the old→new mapping.
--     That step is the mapping-apply file
--     (20260902000003_phase_g_l_mapping_apply.sql) and runs AFTER user
--     creation + recording of the deterministic mapping.
--
-- EXECUTION MODEL:
--   - Founder-authenticated psql in a Founder-local terminal session.
--   - psql `\copy` (client-side, not server-side `COPY TO /tmp`) imports
--     the legacy CSV into a staging table in the new project.
--   - `INSERT ... SELECT ...` from staging into canonical target performs
--     the transform in a single SQL transaction (atomic per-table).
--   - PRIME does NOT execute this file on the live target project.

-- ===========================================================================
-- PART A: STAGING TABLES (transient; dropped at end of script)
-- ===========================================================================

-- Drop any pre-existing staging tables from a prior aborted run.
DROP TABLE IF EXISTS staging.customers CASCADE;
DROP TABLE IF EXISTS staging.partners  CASCADE;
DROP TABLE IF EXISTS staging.drivers   CASCADE;
DROP TABLE IF EXISTS staging.bookings  CASCADE;

CREATE SCHEMA IF NOT EXISTS staging;

-- customers staging (TEXT PK to match target; user_id kept as-is from CSV)
CREATE TABLE staging.customers (
    id               TEXT PRIMARY KEY,
    created_at       TIMESTAMPTZ,
    updated_at       TIMESTAMPTZ,
    user_id          UUID,           -- legacy auth.users.id; copied to legacy_user_id, NOT to target.user_id
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

-- partners staging (BIGSERIAL PK; CSV value goes to legacy_pk column for audit)
CREATE TABLE staging.partners (
    legacy_pk            BIGINT,           -- legacy partners.id (BIGSERIAL value)
    created_at           TIMESTAMPTZ,
    updated_at           TIMESTAMPTZ,
    user_id              UUID,             -- legacy auth.users.id
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

-- drivers staging (UUID PK)
CREATE TABLE staging.drivers (
    id               UUID PRIMARY KEY,    -- legacy drivers.id (UUID)
    created_at       TIMESTAMPTZ,
    updated_at       TIMESTAMPTZ,
    partner_legacy_pk BIGINT,             -- legacy partners.id (resolved to new partners.id in transform)
    user_id          UUID,                -- legacy auth.users.id
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

-- bookings staging (TEXT PK; business FKs in legacy form)
CREATE TABLE staging.bookings (
    id                       TEXT PRIMARY KEY,
    created_at               TIMESTAMPTZ,
    pickup                   TEXT,
    destination              TEXT,
    status                   TEXT,
    customer_id              TEXT,        -- legacy customers.id (TEXT; same value in new project)
    partner_legacy_pk        BIGINT,      -- legacy partners.id (resolved to new partners.id in transform)
    user_id                  UUID,        -- legacy auth.users.id (booking creator)
    email                    TEXT,
    name                     TEXT,
    phone                    TEXT,
    notes                    TEXT,
    payment_status           TEXT,
    assigned_driver          JSONB,
    driver_legacy_uuid       UUID,        -- legacy drivers.id (UUID; same value in new project)
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
-- PART B: IMPORT (psql \copy) — Founder-authenticated local terminal
-- ===========================================================================
--
-- The Founder runs the following psql \copy commands from a Founder-local
-- terminal in the SAME transaction that wraps PART C and PART D.
--
--   psql "$NEW_DB_URL" <<'SQL'
--   BEGIN;
--   \copy staging.customers (...) FROM '/secure/path/fc-customers.csv' CSV HEADER
--   \copy staging.partners  (...) FROM '/secure/path/fc-partners.csv'  CSV HEADER
--   \copy staging.drivers   (...) FROM '/secure/path/fc-drivers.csv'   CSV HEADER
--   \copy staging.bookings  (...) FROM '/secure/path/fc-bookings.csv'  CSV HEADER
--   SQL
--
-- Each \copy uses the column order matching the staging table column
-- list above. Founder drops columns that did not exist in the legacy CSV.
-- PRIME documents the column-list mapping in the founder execution runbook
-- (evidence/r056-phase-g-l-founder-execution-runbook.md §A.1).

-- ===========================================================================
-- PART C: TRANSFORM + INSERT INTO CANONICAL TARGETS (atomic per-table)
-- ===========================================================================
--
-- Each transform runs inside the same transaction as PART B's imports.
-- On any error, ROLLBACK; the entire Wave 4 import is aborted.

-- C.1: customers
INSERT INTO public.customers (
    id, created_at, updated_at,
    legacy_user_id,                  -- audit copy of legacy auth.users.id
    user_id,                         -- NULL on initial import; populated by mapping-apply step
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
    s.user_id,                       -- copy legacy auth.users.id into legacy_user_id
    NULL,                            -- target user_id NULL until mapping-apply
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
ON CONFLICT (id) DO NOTHING;          -- idempotent re-run safety

-- C.2: partners
-- The legacy partners.id (BIGSERIAL) value is NOT preserved as the new PK
-- (target partners.id is BIGSERIAL and will auto-generate). Legacy BIGSERIAL
-- value is captured as legacy_pk for audit. partner_legacy_pk in drivers
-- staging is resolved to the new partners.id via a deterministic mapping
-- (email match) in this transform.
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

-- C.3: drivers
-- Resolve partner_legacy_pk -> new partners.id by email match.
-- If a row's partner_legacy_pk cannot be resolved, the row is logged to
-- a verification report and the row's partner_id is set NULL.
INSERT INTO public.drivers (
    id, created_at, updated_at, partner_id,
    legacy_user_id, user_id,
    email, name, phone, vehicle, license_plate, color,
    driver_code, preferred_language, is_active, archived_at
)
SELECT
    s.id, s.created_at, s.updated_at,
    p_new.id,                         -- resolved new partners.id (NULL if not found)
    s.user_id, NULL,
    s.email, s.name, s.phone, s.vehicle, s.license_plate, s.color,
    s.driver_code, s.preferred_language, s.is_active, s.archived_at
FROM staging.drivers s
LEFT JOIN staging.partners sp ON sp.legacy_pk = s.partner_legacy_pk
LEFT JOIN public.partners p_new ON p_new.email = sp.email
ON CONFLICT (id) DO NOTHING;

-- C.4: bookings
-- customer_id TEXT in legacy == same value in target customers.id (TEXT PK) — direct copy.
-- partner_legacy_pk -> new partners.id via email match.
-- driver_legacy_uuid == same value in target drivers.id (UUID PK) — direct copy.
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
    p_new.id,                        -- resolved new partners.id (NULL if not found)
    s.user_id, NULL,                  -- legacy_user_id + target user_id NULL
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
-- PART D: COMMIT (only after verification queries in PART E return zero issues)
-- ===========================================================================
--
-- The Founder runs:
--   COMMIT;        -- if verification passes
--   -- ROLLBACK;   -- if verification flags any issue (see PART E + rollback.md)
--
-- Verification queries are intentionally NOT executed inside the same
-- transaction so the Founder can review row counts / FK integrity BEFORE
-- committing. See evidence/r056-phase-g-l-verification-queries.sql for the
-- full verification set.

-- ===========================================================================
-- PART E: STAGING CLEANUP (after successful COMMIT)
-- ===========================================================================
DROP TABLE IF EXISTS staging.customers;
DROP TABLE IF EXISTS staging.partners;
DROP TABLE IF EXISTS staging.drivers;
DROP TABLE IF EXISTS staging.bookings;
-- DROP SCHEMA staging;   -- only if no other Wave 4 step needs staging
