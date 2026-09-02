-- Phase G-L: Additive `legacy_user_id` audit column on auth-linked app tables
--
-- Mission   : 2026-08-29-fleetconnect-operational-recovery
-- Round     : r056 Phase G-L executable Wave 4 data/auth remap package
-- Predecessor: Lux 2675123e3418e65536aef60da63c2aab4b9a24ef (G-K accept +
--              Wave 4 import/remap execution-blocker); Lux 45d7853ba054f79d2c58cb87c68bb7abb11811ce5657a91e6b6a90c7915b8280
--              (G-L schema-repair approval, strict §3 consume restored)
--
-- SCOPE (per Lux 2675123 §5):
--   Add `legacy_user_id UUID NULL` to every auth-linked app table that
--   carries `user_id UUID REFERENCES auth.users(id)`. Per the canonical
--   greenfield baseline (20260831000000_phase_g_canonical_greenfield_baseline.sql),
--   the auth-linked app tables are:
--     - customers      (TEXT PK, user_id FK)
--     - partners       (BIGSERIAL PK, user_id FK)
--     - drivers        (UUID PK, user_id FK)
--     - onderaannemers (BIGSERIAL PK, user_id FK, COMPATIBILITY/DORMANT label)
--     - bookings       (TEXT PK, user_id FK + business FKs to customers/partners/drivers)
--
--   onderaannemers is included even though labelled "COMPATIBILITY/DORMANT":
--   the additive migration is harmless on an empty table, and excluding it
--   would leave a hidden auth-FK surface unaddressed if legacy introspection
--   later confirms it is active in production.
--
-- NON-SCOPE:
--   - This file does NOT modify `user_id`, business PK/FKs, RLS, policies,
--     grants, auth schema, or any operational data.
--   - This file does NOT backfill `legacy_user_id` values; backfill is the
--     job of the Wave 4 staging/transform import step (separate file).
--   - This file is IDEMPOTENT (ADD COLUMN IF NOT EXISTS, CREATE INDEX IF NOT EXISTS).
--
-- EXECUTION MODEL (per Lux 2675123 §6 / Lux G-L §3):
--   - Founder-authenticated apply via Supabase Dashboard SQL Editor OR
--     `supabase login` + `supabase link` + `supabase db push`. PRIME does
--     NOT apply migrations on the live target project.
--   - No Founder-issued credential transits chat/Telegram/Bridge/repo/evidence.
--   - PRIME does NOT assume it holds NEW_DB_URL.
--
-- ROLLBACK:
--   See evidence/r056-phase-g-l-rollback.md §A. Additive column drops
--   are safe when no rows have been backfilled. After backfill, see the
--   staged rollback in evidence/r056-phase-g-l-rollback.md §B.

-- ---------------------------------------------------------------------------
-- 1. customers.legacy_user_id
-- ---------------------------------------------------------------------------
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS legacy_user_id UUID NULL;

COMMENT ON COLUMN public.customers.legacy_user_id IS
  'Phase G-L: audit copy of the legacy auth.users.id captured during Wave 4 staging import. NULL on rows that did not exist in legacy auth. Populated only by the Wave 4 staging/transform import step, never by the live application.';

CREATE INDEX IF NOT EXISTS idx_customers_legacy_user_id
  ON public.customers(legacy_user_id)
  WHERE legacy_user_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. partners.legacy_user_id
-- ---------------------------------------------------------------------------
ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS legacy_user_id UUID NULL;

COMMENT ON COLUMN public.partners.legacy_user_id IS
  'Phase G-L: audit copy of the legacy auth.users.id captured during Wave 4 staging import. NULL on rows that did not exist in legacy auth. Populated only by the Wave 4 staging/transform import step, never by the live application.';

CREATE INDEX IF NOT EXISTS idx_partners_legacy_user_id
  ON public.partners(legacy_user_id)
  WHERE legacy_user_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3. drivers.legacy_user_id
-- ---------------------------------------------------------------------------
ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS legacy_user_id UUID NULL;

COMMENT ON COLUMN public.drivers.legacy_user_id IS
  'Phase G-L: audit copy of the legacy auth.users.id captured during Wave 4 staging import. NULL on rows that did not exist in legacy auth. Populated only by the Wave 4 staging/transform import step, never by the live application.';

CREATE INDEX IF NOT EXISTS idx_drivers_legacy_user_id
  ON public.drivers(legacy_user_id)
  WHERE legacy_user_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 4. onderaannemers.legacy_user_id (COMPATIBILITY/DORMANT; safe no-op if empty)
-- ---------------------------------------------------------------------------
ALTER TABLE public.onderaannemers
  ADD COLUMN IF NOT EXISTS legacy_user_id UUID NULL;

COMMENT ON COLUMN public.onderaannemers.legacy_user_id IS
  'Phase G-L: audit copy of the legacy auth.users.id captured during Wave 4 staging import. NULL on rows that did not exist in legacy auth. Populated only by the Wave 4 staging/transform import step, never by the live application. Harmless on an empty/legacy-dormant table.';

CREATE INDEX IF NOT EXISTS idx_onderaannemers_legacy_user_id
  ON public.onderaannemers(legacy_user_id)
  WHERE legacy_user_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 5. bookings.legacy_user_id
--    Note: bookings.user_id is the booking creator's auth.users.id (per
--    phase4_identity_closure.sql line 12). business FKs (customer_id,
--    partner_id, assigned_driver_id) are not touched by this migration.
-- ---------------------------------------------------------------------------
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS legacy_user_id UUID NULL;

COMMENT ON COLUMN public.bookings.legacy_user_id IS
  'Phase G-L: audit copy of the legacy auth.users.id captured during Wave 4 staging import (booking creator). NULL on rows that did not exist in legacy auth. Populated only by the Wave 4 staging/transform import step, never by the live application.';

CREATE INDEX IF NOT EXISTS idx_bookings_legacy_user_id
  ON public.bookings(legacy_user_id)
  WHERE legacy_user_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Verification (read-only; informational)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  tbl TEXT;
  has_col BOOLEAN;
  missing TEXT := '';
BEGIN
  FOREACH tbl IN ARRAY ARRAY['customers','partners','drivers','onderaannemers','bookings']
  LOOP
    SELECT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = tbl
        AND column_name = 'legacy_user_id'
    ) INTO has_col;
    IF NOT has_col THEN
      missing := missing || tbl || ',';
    END IF;
  END LOOP;
  IF missing <> '' THEN
    RAISE EXCEPTION 'Phase G-L additive migration failed: legacy_user_id missing on: %', missing;
  END IF;
  RAISE NOTICE 'Phase G-L additive migration OK: legacy_user_id present on customers, partners, drivers, onderaannemers, bookings';
END$$;
