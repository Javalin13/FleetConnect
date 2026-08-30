-- Migration: FleetConnect founder/admin authorization RPC v2 (r055 hardening)
--
-- Per Lux r054 §2 CRITICAL: r054 authorize_admin_role(p_user_id uuid DEFAULT NULL)
-- permitted caller-selected identity escalation. Any authenticated/anon caller could
-- pass any user's UUID and receive that user's authorization result + email +
-- partner scope. This is a privilege oracle.
--
-- Per Lux r054 §2 required fix:
-- 1. Replace public callable with NO caller-supplied user-id argument
-- 2. Inside, derive identity ONLY from auth.uid()
-- 3. Grant EXECUTE to authenticated only (NOT anon); service_role only if backend needs
-- 4. Keep SECURITY DEFINER only to read auth.users; tightly controlled search_path;
--    NO dynamic SQL
-- 5. Do NOT return more identity data than needed; drop email field if not used by UI
--
-- Also per Lux r054 §4: ondernemerA.html must re-authorize server-side on load,
-- not via sessionStorage.

-- DROP r054 version (caller-controlled user-id was the vulnerability)
DROP FUNCTION IF EXISTS public.authorize_admin_role(uuid);

-- v2: NO user-id argument; identity derived strictly from auth.uid()
CREATE OR REPLACE FUNCTION public.authorize_admin_role()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id uuid;
    v_user_record auth.users%ROWTYPE;
    v_app_metadata jsonb;
    v_role text;
    v_is_admin boolean;
    v_partner_id bigint;
    v_partner_name text;
    v_is_hoofd_partner boolean := false;
    v_partner_scope jsonb;
    v_result jsonb;
    v_founder_authorized boolean := false;
    v_operator_authorized boolean := false;
    v_reason text;
BEGIN
    -- r055 hardening: identity comes STRICTLY from auth.uid().
    -- No caller-supplied user-id argument exists anymore; caller cannot
    -- select another identity. If no authenticated user, return denied.
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'authorized', false,
            'founder_scope', false,
            'operator_scope', false,
            'reason', 'no_authenticated_user'
        );
    END IF;

    -- Read auth.users (SECURITY DEFINER allows this; anon caller could not)
    -- No dynamic SQL; static query against auth.users by PK
    SELECT * INTO v_user_record FROM auth.users WHERE id = v_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'authorized', false,
            'founder_scope', false,
            'operator_scope', false,
            'reason', 'user_not_found'
        );
    END IF;

    -- Trusted app_metadata (server-set via Admin API only)
    v_app_metadata := COALESCE(v_user_record.raw_app_meta_data, '{}'::jsonb);
    v_role := v_app_metadata->>'role';
    v_is_admin := COALESCE((v_app_metadata->>'is_admin')::boolean, false);

    -- Factual DB partner relationship; no hardcoded partner_id strings
    SELECT id, name, is_hoofd
    INTO v_partner_id, v_partner_name, v_is_hoofd_partner
    FROM public.partners
    WHERE user_id = v_user_id
    ORDER BY is_hoofd DESC, id ASC
    LIMIT 1;

    -- Authorization decision (same logic as r054)
    IF v_role = 'dispatch' AND v_is_admin THEN
        v_founder_authorized := true;
        v_operator_authorized := true;
        v_reason := 'founder_dispatch_admin';
    ELSIF v_role = 'dispatch' THEN
        v_operator_authorized := true;
        v_reason := 'dispatch_no_admin';
    ELSIF v_is_hoofd_partner THEN
        v_operator_authorized := true;
        v_reason := 'head_partner_operator';
    ELSE
        v_reason := 'no_admin_role';
    END IF;

    -- Partner scope payload (FACTUAL DB values)
    IF v_partner_id IS NOT NULL THEN
        v_partner_scope := jsonb_build_object(
            'partner_id', v_partner_id,
            'partner_name', v_partner_name,
            'is_hoofd', v_is_hoofd_partner
        );
    ELSE
        v_partner_scope := jsonb_build_object('partner_id', NULL);
    END IF;

    -- r055 hardening: drop email field from response (not used by UI;
    -- keeps the RPC from leaking identity data unnecessarily).
    v_result := jsonb_build_object(
        'authorized', (v_founder_authorized OR v_operator_authorized),
        'founder_scope', v_founder_authorized,
        'operator_scope', v_operator_authorized,
        'role', v_role,
        'is_admin', v_is_admin,
        'partner_scope', v_partner_scope,
        'reason', v_reason
        -- email removed; user_id removed; not needed for authorization decisions
    );

    RETURN v_result;
END;
$$;

-- r055 hardening: GRANT EXECUTE only to authenticated and service_role.
-- DO NOT grant to anon (per Lux r054 §2.3).
-- service_role is granted for backend tooling only (NOT browser).
GRANT EXECUTE ON FUNCTION public.authorize_admin_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.authorize_admin_role() TO service_role;

-- Revoke any prior anon grant defensively
REVOKE EXECUTE ON FUNCTION public.authorize_admin_role() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.authorize_admin_role() FROM anon;

COMMENT ON FUNCTION public.authorize_admin_role() IS
    'r055 HARDENED server-derived authorization for FleetConnect Founder/admin/operator panels. '
    'Per Lux r054 §2: caller CANNOT supply a user-id (no argument); identity is derived STRICTLY '
    'from auth.uid(). EXECUTE granted only to authenticated + service_role (NOT anon). Returns '
    'founder_scope (all panels, dispatch@fleetconnect.be only), operator_scope (Moukrim head-partner, '
    'FleetConnect taxi ops only), or no scope (customer/driver/regular partner denied). Trusts '
    'app_metadata + DB partners relationship; no user_metadata (user-mutable); no browser sessionStorage; '
    'no hardcoded partner_id strings. SECURITY DEFINER + tight search_path + no dynamic SQL. '
    'Email field removed from response to avoid identity data leakage.';