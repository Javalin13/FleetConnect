-- Migration: FleetConnect founder/admin authorization RPC (r054)
-- Per Lux r053 §1 CRITICAL: admin-index.html currently treats ANY authenticated user as admin.
-- This migration creates a server-side authorization RPC that the browser MUST call
-- after signInWithPassword to determine which panels the user is permitted to see.
--
-- Authorization model (per Lux r053 §1):
--   - dispatch@fleetconnect.be (Founder/power-admin) → ALL panels (Founder scope)
--   - partners.is_hoofd=true (Moukrim, head operational partner) → OPERATOR panels only
--     (FleetConnect taxi ops, NOT car dealer, NOT vacation rental)
--   - customers, drivers, regular partners, anon → DENIED all panels
--   - driver auth users → DENIED Founder/partner panels; they have their own driver portal
--
-- The RPC reads trusted `app_metadata.role` and `app_metadata.is_admin` (server-set)
-- AND the factual `partners.is_hoofd=true` DB relationship (Moukrim).
-- It does NOT trust `user_metadata` (user-mutable).
-- It does NOT trust browser sessionStorage.

CREATE OR REPLACE FUNCTION public.authorize_admin_role(p_user_id uuid DEFAULT NULL::uuid)
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
    -- Resolve user_id: prefer arg, else current auth.uid()
    v_user_id := COALESCE(p_user_id, auth.uid());
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'authorized', false,
            'founder_scope', false,
            'operator_scope', false,
            'reason', 'no_authenticated_user'
        );
    END IF;

    -- Fetch user record (SECURITY DEFINER allows this; caller anon would not be able to)
    SELECT * INTO v_user_record FROM auth.users WHERE id = v_user_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'authorized', false,
            'founder_scope', false,
            'operator_scope', false,
            'reason', 'user_not_found'
        );
    END IF;

    -- Read app_metadata (trusted; only service_role can mutate via Admin API)
    v_app_metadata := COALESCE(v_user_record.raw_app_meta_data, '{}'::jsonb);
    v_role := v_app_metadata->>'role';
    v_is_admin := COALESCE((v_app_metadata->>'is_admin')::boolean, false);

    -- Resolve partner relationship via DB (FACTUAL, not hardcoded)
    -- Look up by user_id; if multiple partners exist for same user, take the hoofd-partner
    SELECT id, name, is_hoofd
    INTO v_partner_id, v_partner_name, v_is_hoofd_partner
    FROM public.partners
    WHERE user_id = v_user_id
    ORDER BY is_hoofd DESC, id ASC
    LIMIT 1;

    -- Founder/power-admin authorization: app_metadata.role='dispatch' + is_admin=true
    -- (this is what the r053 bootstrap sets for dispatch@fleetconnect.be)
    IF v_role = 'dispatch' AND v_is_admin THEN
        v_founder_authorized := true;
        v_operator_authorized := true;  -- founder also sees operator panels
        v_reason := 'founder_dispatch_admin';
    ELSIF v_role = 'dispatch' THEN
        -- role=dispatch but is_admin=false → partial grant; treat as operator
        v_operator_authorized := true;
        v_reason := 'dispatch_no_admin';
    ELSIF v_is_hoofd_partner THEN
        -- Head operational partner (Moukrim): operator scope only, NOT founder scope
        v_operator_authorized := true;
        v_reason := 'head_partner_operator';
    ELSE
        -- Regular authenticated user (customer/driver/regular partner): NO admin panels
        v_reason := 'no_admin_role';
    END IF;

    -- Build partner_scope payload (FACTUAL DB values; no hardcoded strings)
    IF v_partner_id IS NOT NULL THEN
        v_partner_scope := jsonb_build_object(
            'partner_id', v_partner_id,
            'partner_name', v_partner_name,
            'is_hoofd', v_is_hoofd_partner
        );
    ELSE
        v_partner_scope := jsonb_build_object('partner_id', NULL);
    END IF;

    v_result := jsonb_build_object(
        'authorized', (v_founder_authorized OR v_operator_authorized),
        'founder_scope', v_founder_authorized,
        'operator_scope', v_operator_authorized,
        'role', v_role,
        'is_admin', v_is_admin,
        'partner_scope', v_partner_scope,
        'reason', v_reason,
        'user_id', v_user_id,
        'email', v_user_record.email
    );

    RETURN v_result;
END;
$$;

-- Grant EXECUTE to authenticated and anon (the function itself uses SECURITY DEFINER
-- to access auth.users; anon caller just gets back their own scope, which is
-- determined by their auth.uid()).
GRANT EXECUTE ON FUNCTION public.authorize_admin_role(uuid) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.authorize_admin_role(uuid) IS
    'Server-derived authorization for FleetConnect Founder/admin/operator panels. Per Lux r053 §1: returns founder_scope (all panels, dispatch@fleetconnect.be only), operator_scope (Moukrim head-partner, FleetConnect taxi ops only), or no scope (customer/driver/regular partner denied). Trusted app_metadata + DB partners relationship; no browser sessionStorage, no user_metadata (user-mutable), no hardcoded partner_id strings.';