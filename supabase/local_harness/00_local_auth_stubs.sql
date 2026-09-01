-- =====================================================================
-- r056 Phase G local-harness Supabase stubs (TEST ONLY)
-- =====================================================================
--
-- PURPOSE:
--   Provide minimal `auth.users` + `auth.uid()` / `auth.jwt()` / `auth.role()`
--   + anon / authenticated / service_role roles for the local disposable
--   Postgres harness used by PRIME to prove the greenfield reconstruction
--   on an empty database.
--
-- CRITICAL: DO NOT INCLUDE IN PRODUCTION APPLY
--   Real Supabase manages `auth.users` and the auth helper functions as
--   platform-owned objects. This file creates/overrides them. Including
--   it in the production apply would (a) modify Supabase-managed auth
--   helpers and (b) silently create the standard Supabase roles, which
--   the production environment may already have with different attributes.
--
-- APPLY PATH:
--   Local harness only. The test script `supabase/local_harness/apply_with_harness.sh`
--   applies THIS file first, then the production-safe baseline, then the
--   historical migration chain.
--
-- PRODUCTION APPLY PATH:
--   The production apply script `supabase/apply_manifest.sh` MUST NOT
--   execute this file. Supabase already provides the auth schema, auth.users
--   table, auth.uid()/auth.jwt()/auth.role() helpers, and anon/authenticated/
--   service_role roles.
--
-- AUTHOR: PRIME (r056 Phase G-H, post Lux d3a5d92)
-- DATE: 2026-09-01
-- =====================================================================

-- 0. Extensions schema + pgcrypto (safe on real Supabase; idempotent)
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 1. Supabase auth schema (real Supabase already has this; safe IF NOT EXISTS)
CREATE SCHEMA IF NOT EXISTS auth;

-- 2. Supabase standard roles (real Supabase already has these;
--    IF NOT EXISTS guards against duplicate-object error)
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

-- 3. auth.users stub (real Supabase provides full table; this is minimal)
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

-- 4. auth.uid() / auth.jwt() / auth.role() stub functions
--    Real Supabase provides these; these stubs only run in the local
--    harness where the platform helpers do not exist.
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
