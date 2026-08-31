-- Migration: Phase F secure dispatch mailbox schema + RLS + audit + authorize RPC
-- (CORRECTED per Lux 2b890b1 BLOCKER — migration chain must apply cleanly from pre-Phase-F schema)
--
-- Mission: 2026-08-29-fleetconnect-operational-recovery
-- Round: r056 Phase F (batch 1 corrections, migration-chain fix)
-- Authority: mailbox-audit.md (r053 Phase 7) + Lux 68f35b6 §4 + Lux 8d5d099 §1-3 + Lux 2b890b1 §4
--
-- BLOCKER FIX: this migration replaces the broken v1 (which created policies
-- referencing authorize_dispatch_mailbox() before the function existed) AND
-- the corrective v2 (which fixed v1's internal order but left v1 in the
-- migration path so clean apply never reached v2).
--
-- Per Lux 2b890b1 §4: "prefer correcting/replacing/removing the broken
-- 20260831000001 artifact in the branch rather than preserving an unusable
-- historical migration in the executable migration path".
--
-- This file is timestamp 20260831000001 and is the SOLE Phase F mailbox
-- migration. v1 + v2 history is preserved in git history and evidence/.
--
-- Section order (function FIRST so policies can resolve):
--   1. authorize_dispatch_mailbox() RPC        — created FIRST so policies can resolve
--   2. log_dispatch_mailbox_action() RPC       — created early (sibling of section 1)
--   3. dispatch_mailbox_messages table
--   4. dispatch_mailbox_attachments table
--   5. dispatch_mailbox_audit table
--   6. dispatch_mailbox_folders table
--   7. dispatch_mailbox_session_state table
--   8. RLS policies (now reference existing authorize_dispatch_mailbox())
--   9. Defensive check (no anon grants)
--
-- All statements are idempotent (CREATE TABLE IF NOT EXISTS, CREATE OR REPLACE
-- FUNCTION, DROP POLICY IF EXISTS + CREATE POLICY, GRANT only if not present,
-- REVOKE always) so re-running this migration is safe.
--
-- Doctrine preserved per Lux 68f35b6 §4:
--   - real dispatch@fleetconnect.be read/write mailbox
--   - server-side adapter/API only
--   - credentials/secrets ONLY in secure server env
--   - exactly-once operational archive preservation
--   - Founder/power-admin + head-partner access only
--   - does NOT weaken r055 authorize_admin_role()

-- =========================================================
-- 1. authorize_dispatch_mailbox() — CREATED FIRST (BLOCKER FIX)
-- =========================================================
-- Per Lux r054 §2 hardening: NO caller-supplied identity argument; identity from auth.uid().
-- This RPC delegates to authorize_admin_role() so the mailbox layer does NOT weaken r055.
CREATE OR REPLACE FUNCTION public.authorize_dispatch_mailbox()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_authz jsonb;
    v_authorized boolean := false;
    v_founder_scope boolean := false;
    v_operator_scope boolean := false;
    v_role text;
    v_is_admin boolean := false;
    v_partner_scope jsonb;
    v_reason text;
BEGIN
    BEGIN
        v_authz := public.authorize_admin_role();
    EXCEPTION WHEN OTHERS THEN
        v_authz := jsonb_build_object(
            'authorized', false,
            'founder_scope', false,
            'operator_scope', false,
            'reason', 'authorize_admin_role_unavailable'
        );
    END;

    v_founder_scope := COALESCE((v_authz ->> 'founder_scope')::boolean, false);
    v_operator_scope := COALESCE((v_authz ->> 'operator_scope')::boolean, false);
    v_authorized := COALESCE((v_authz ->> 'authorized')::boolean, false);
    v_role := COALESCE(v_authz ->> 'role', '');
    v_is_admin := COALESCE((v_authz ->> 'is_admin')::boolean, false);
    v_partner_scope := COALESCE(v_authz ->> 'partner_scope', '{}'::jsonb);

    IF NOT v_authorized THEN
        v_reason := 'no_admin_role';
    ELSE
        v_reason := v_authz ->> 'reason';
    END IF;

    RETURN jsonb_build_object(
        'authorized', v_authorized,
        'founder_scope', v_founder_scope,
        'operator_scope', v_operator_scope,
        'role', v_role,
        'is_admin', v_is_admin,
        'partner_scope', v_partner_scope,
        'reason', v_reason
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.authorize_dispatch_mailbox() TO authenticated;
GRANT EXECUTE ON FUNCTION public.authorize_dispatch_mailbox() TO service_role;
REVOKE EXECUTE ON FUNCTION public.authorize_dispatch_mailbox() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.authorize_dispatch_mailbox() FROM anon;

COMMENT ON FUNCTION public.authorize_dispatch_mailbox() IS
    'Phase F: server-derived authorization for dispatch mailbox access. Reuses r055 hardened '
    'authorize_admin_role() (no caller-supplied user-id; identity from auth.uid()). Returns '
    'authorized=true ONLY for founder (dispatch role + is_admin) or head-partner operator. '
    'No mail access for customer/driver/regular partner/anonymous. SECURITY DEFINER + tight '
    'search_path. Locked to authenticated + service_role. CREATED BEFORE RLS policies that '
    'reference it (per Lux 8d5d099 BLOCKER #1 fix).';

-- =========================================================
-- 2. log_dispatch_mailbox_action() — append-only audit writer (also created early)
-- =========================================================
CREATE OR REPLACE FUNCTION public.log_dispatch_mailbox_action(
    p_action text,
    p_mailbox text DEFAULT NULL,
    p_folder text DEFAULT NULL,
    p_uid bigint DEFAULT NULL,
    p_request_id text DEFAULT NULL,
    p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id uuid;
    v_user_email text;
    v_authz jsonb;
    v_role_at_action text;
    v_audit_id bigint;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'logged', false,
            'reason', 'no_authenticated_user'
        );
    END IF;

    BEGIN
        SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;
    EXCEPTION WHEN OTHERS THEN
        v_user_email := NULL;
    END;

    BEGIN
        v_authz := public.authorize_admin_role();
    EXCEPTION WHEN OTHERS THEN
        v_authz := jsonb_build_object('authorized', false, 'reason', 'authz_unavailable');
    END;

    v_role_at_action := COALESCE(v_authz ->> 'reason', 'unknown');

    IF NOT COALESCE((v_authz ->> 'authorized')::boolean, false) AND p_action <> 'denied' THEN
        BEGIN
            INSERT INTO public.dispatch_mailbox_audit (
                actor_user_id, actor_email, actor_role_at_action,
                action, mailbox, folder, request_id, metadata
            )
            VALUES (
                v_user_id, v_user_email, 'denied',
                'denied', p_mailbox, p_folder, p_request_id, p_metadata
            )
            RETURNING id INTO v_audit_id;
        EXCEPTION WHEN OTHERS THEN
            v_audit_id := NULL;
        END;

        RETURN jsonb_build_object(
            'logged', false,
            'reason', 'unauthorized_action',
            'audit_id', v_audit_id
        );
    END IF;

    INSERT INTO public.dispatch_mailbox_audit (
        actor_user_id, actor_email, actor_role_at_action,
        action, mailbox, folder, uid, request_id, metadata
    )
    VALUES (
        v_user_id, v_user_email, v_role_at_action,
        p_action, p_mailbox, p_folder, p_uid, p_request_id, p_metadata
    )
    RETURNING id INTO v_audit_id;

    RETURN jsonb_build_object(
        'logged', true,
        'audit_id', v_audit_id,
        'actor_role', v_role_at_action
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.log_dispatch_mailbox_action(
    text, text, text, bigint, text, jsonb
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_dispatch_mailbox_action(
    text, text, text, bigint, text, jsonb
) TO service_role;
REVOKE EXECUTE ON FUNCTION public.log_dispatch_mailbox_action(
    text, text, text, bigint, text, jsonb
) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.log_dispatch_mailbox_action(
    text, text, text, bigint, text, jsonb
) FROM anon;

COMMENT ON FUNCTION public.log_dispatch_mailbox_action(
    text, text, text, bigint, text, jsonb
) IS
    'Phase F: append-only audit-log writer for mailbox actions. Caller cannot supply user-id; '
    'identity derived from auth.uid(). If action is unauthorized AND action != denied, returns '
    'logged=false AND records a denied audit entry. Returns logged=true + audit_id for authorized '
    'actions. Email + role captured at action time. SECURITY DEFINER + tight search_path. '
    'Locked to authenticated + service_role.';

-- =========================================================
-- 3. dispatch_mailbox_messages — IMAP-cached message metadata + body excerpt
-- =========================================================
CREATE TABLE IF NOT EXISTS public.dispatch_mailbox_messages (
    id                    bigserial PRIMARY KEY,
    mailbox               text NOT NULL,
    folder                text NOT NULL DEFAULT 'INBOX',
    uid                   bigint NOT NULL,
    message_id            text,
    in_reply_to           text,
    from_addr             text NOT NULL,
    from_name             text,
    to_addrs              jsonb NOT NULL DEFAULT '[]'::jsonb,
    cc_addrs              jsonb NOT NULL DEFAULT '[]'::jsonb,
    bcc_addrs             jsonb NOT NULL DEFAULT '[]'::jsonb,
    subject               text,
    body_text             text,
    body_html             text,
    snippet               text,
    has_attachments       boolean NOT NULL DEFAULT false,
    attachment_count      integer NOT NULL DEFAULT 0,
    seen                  boolean NOT NULL DEFAULT false,
    flagged               boolean NOT NULL DEFAULT false,
    answered              boolean NOT NULL default false,
    is_manual_dispatch    boolean NOT NULL DEFAULT false,
    booking_id_referenced text,
    received_at           timestamptz NOT NULL,
    fetched_at            timestamptz NOT NULL DEFAULT now(),
    raw_headers           jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT dispatch_mailbox_messages_uid_unique UNIQUE (mailbox, folder, uid)
);

CREATE INDEX IF NOT EXISTS dispatch_mailbox_messages_mailbox_folder_received_at_idx
    ON public.dispatch_mailbox_messages (mailbox, folder, received_at DESC);

CREATE INDEX IF NOT EXISTS dispatch_mailbox_messages_seen_idx
    ON public.dispatch_mailbox_messages (mailbox, folder, seen) WHERE seen = false;

CREATE INDEX IF NOT EXISTS dispatch_mailbox_messages_booking_id_idx
    ON public.dispatch_mailbox_messages (booking_id_referenced)
    WHERE booking_id_referenced IS NOT NULL;

COMMENT ON TABLE public.dispatch_mailbox_messages IS
    'Phase F: IMAP message metadata cache. Server-side adapter reads IMAP, caches metadata + body excerpt here. '
    'Full MIME bodies NEVER stored in DB; full bodies fetched on demand from IMAP via edge function. '
    'RLS locked to founder/head-partner authenticated and service_role.';

-- =========================================================
-- 4. dispatch_mailbox_attachments — attachment metadata (NO file contents)
-- =========================================================
CREATE TABLE IF NOT EXISTS public.dispatch_mailbox_attachments (
    id                    bigserial PRIMARY KEY,
    message_id            bigint NOT NULL REFERENCES public.dispatch_mailbox_messages(id) ON DELETE CASCADE,
    mailbox               text NOT NULL,
    folder                text NOT NULL,
    uid                   bigint NOT NULL,
    part_index            integer NOT NULL,
    filename              text,
    content_type          text,
    content_size_bytes    bigint,
    content_sha256        text,
    fetched               boolean NOT NULL DEFAULT false,
    fetched_at            timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT dispatch_mailbox_attachments_unique UNIQUE (message_id, part_index)
);

CREATE INDEX IF NOT EXISTS dispatch_mailbox_attachments_message_id_idx
    ON public.dispatch_mailbox_attachments (message_id);

COMMENT ON TABLE public.dispatch_mailbox_attachments IS
    'Phase F: IMAP attachment metadata. File contents NEVER in DB. Fetched on demand from server-side '
    'temp storage by edge function with scope guard.';

-- =========================================================
-- 5. dispatch_mailbox_audit — append-only audit log
-- =========================================================
CREATE TABLE IF NOT EXISTS public.dispatch_mailbox_audit (
    id                    bigserial PRIMARY KEY,
    actor_user_id         uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    actor_email           text,
    actor_role_at_action  text,
    action                text NOT NULL,
    mailbox               text,
    folder                text,
    uid                   bigint,
    request_id            text,
    client_ip             inet,
    user_agent            text,
    metadata              jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS dispatch_mailbox_audit_actor_idx
    ON public.dispatch_mailbox_audit (actor_user_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS dispatch_mailbox_audit_action_idx
    ON public.dispatch_mailbox_audit (action, occurred_at DESC);

COMMENT ON TABLE public.dispatch_mailbox_audit IS
    'Phase F: append-only audit trail for mailbox read/write actions. No UPDATE/DELETE policy granted '
    'to anyone except service_role for retention pruning. Required for incident response and compliance.';

-- =========================================================
-- 6. dispatch_mailbox_folders — IMAP folder name cache
-- =========================================================
CREATE TABLE IF NOT EXISTS public.dispatch_mailbox_folders (
    id                    bigserial PRIMARY KEY,
    mailbox               text NOT NULL,
    folder_name           text NOT NULL,
    folder_flags          jsonb NOT NULL DEFAULT '[]'::jsonb,
    message_count         integer,
    unseen_count          integer,
    last_synced_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT dispatch_mailbox_folders_unique UNIQUE (mailbox, folder_name)
);

COMMENT ON TABLE public.dispatch_mailbox_folders IS
    'Phase F: IMAP folder listing cache. Refreshed by server-side adapter on each mailbox open.';

-- =========================================================
-- 7. dispatch_mailbox_session_state — per-session IDLE cursor + token rotation
-- =========================================================
CREATE TABLE IF NOT EXISTS public.dispatch_mailbox_session_state (
    id                    bigserial PRIMARY KEY,
    mailbox               text NOT NULL,
    last_uid              bigint NOT NULL DEFAULT 0,
    last_idle_at          timestamptz,
    last_disconnect_at    timestamptz,
    last_reconnect_at     timestamptz,
    reconnect_count       integer NOT NULL DEFAULT 0,
    failure_reason        text,
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT dispatch_mailbox_session_state_mailbox_unique UNIQUE (mailbox)
);

COMMENT ON TABLE public.dispatch_mailbox_session_state IS
    'Phase F: IMAP connection state tracking (NOT credentials). For connection-pool health + audit. '
    'Credentials themselves are server-side env-vars ONLY, never in DB.';

-- =========================================================
-- 8. RLS policies — reference existing authorize_dispatch_mailbox() from section 1
-- =========================================================

ALTER TABLE public.dispatch_mailbox_messages       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dispatch_mailbox_attachments    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dispatch_mailbox_audit          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dispatch_mailbox_folders        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dispatch_mailbox_session_state  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.dispatch_mailbox_messages       FROM PUBLIC;
REVOKE ALL ON public.dispatch_mailbox_attachments    FROM PUBLIC;
REVOKE ALL ON public.dispatch_mailbox_audit          FROM PUBLIC;
REVOKE ALL ON public.dispatch_mailbox_folders        FROM PUBLIC;
REVOKE ALL ON public.dispatch_mailbox_session_state  FROM PUBLIC;

GRANT SELECT, INSERT, UPDATE         ON public.dispatch_mailbox_messages       TO authenticated;
GRANT SELECT, INSERT                 ON public.dispatch_mailbox_attachments    TO authenticated;
GRANT SELECT, INSERT                 ON public.dispatch_mailbox_folders        TO authenticated;
GRANT SELECT, INSERT                 ON public.dispatch_mailbox_session_state  TO authenticated;
GRANT SELECT, INSERT                 ON public.dispatch_mailbox_audit          TO authenticated;

GRANT ALL ON public.dispatch_mailbox_messages       TO service_role;
GRANT ALL ON public.dispatch_mailbox_attachments    TO service_role;
GRANT ALL ON public.dispatch_mailbox_audit          TO service_role;
GRANT ALL ON public.dispatch_mailbox_folders        TO service_role;
GRANT ALL ON public.dispatch_mailbox_session_state  TO service_role;

DROP POLICY IF EXISTS dispatch_mailbox_messages_select ON public.dispatch_mailbox_messages;
CREATE POLICY dispatch_mailbox_messages_select ON public.dispatch_mailbox_messages
    FOR SELECT TO authenticated
    USING (
        (public.authorize_dispatch_mailbox() ->> 'authorized')::boolean = true
    );

DROP POLICY IF EXISTS dispatch_mailbox_messages_insert ON public.dispatch_mailbox_messages;
CREATE POLICY dispatch_mailbox_messages_insert ON public.dispatch_mailbox_messages
    FOR INSERT TO authenticated
    WITH CHECK (
        (public.authorize_dispatch_mailbox() ->> 'authorized')::boolean = true
    );

DROP POLICY IF EXISTS dispatch_mailbox_messages_update ON public.dispatch_mailbox_messages;
CREATE POLICY dispatch_mailbox_messages_update ON public.dispatch_mailbox_messages
    FOR UPDATE TO authenticated
    USING (
        (public.authorize_dispatch_mailbox() ->> 'authorized')::boolean = true
    )
    WITH CHECK (
        (public.authorize_dispatch_mailbox() ->> 'authorized')::boolean = true
    );

DROP POLICY IF EXISTS dispatch_mailbox_attachments_select ON public.dispatch_mailbox_attachments;
CREATE POLICY dispatch_mailbox_attachments_select ON public.dispatch_mailbox_attachments
    FOR SELECT TO authenticated
    USING (
        (public.authorize_dispatch_mailbox() ->> 'authorized')::boolean = true
    );

DROP POLICY IF EXISTS dispatch_mailbox_attachments_insert ON public.dispatch_mailbox_attachments;
CREATE POLICY dispatch_mailbox_attachments_insert ON public.dispatch_mailbox_attachments
    FOR INSERT TO authenticated
    WITH CHECK (false);

DROP POLICY IF EXISTS dispatch_mailbox_audit_select ON public.dispatch_mailbox_audit;
CREATE POLICY dispatch_mailbox_audit_select ON public.dispatch_mailbox_audit
    FOR SELECT TO authenticated
    USING (
        (public.authorize_dispatch_mailbox() ->> 'authorized')::boolean = true
    );

DROP POLICY IF EXISTS dispatch_mailbox_audit_insert ON public.dispatch_mailbox_audit;
CREATE POLICY dispatch_mailbox_audit_insert ON public.dispatch_mailbox_audit
    FOR INSERT TO authenticated
    WITH CHECK (
        (public.authorize_dispatch_mailbox() ->> 'authorized')::boolean = true
        AND actor_user_id = auth.uid()
    );

DROP POLICY IF EXISTS dispatch_mailbox_audit_update ON public.dispatch_mailbox_audit;
CREATE POLICY dispatch_mailbox_audit_update ON public.dispatch_mailbox_audit
    FOR UPDATE TO authenticated
    USING (false);

DROP POLICY IF EXISTS dispatch_mailbox_audit_delete ON public.dispatch_mailbox_audit;
CREATE POLICY dispatch_mailbox_audit_delete ON public.dispatch_mailbox_audit
    FOR DELETE TO authenticated
    USING (false);

DROP POLICY IF EXISTS dispatch_mailbox_folders_select ON public.dispatch_mailbox_folders;
CREATE POLICY dispatch_mailbox_folders_select ON public.dispatch_mailbox_folders
    FOR SELECT TO authenticated
    USING (
        (public.authorize_dispatch_mailbox() ->> 'authorized')::boolean = true
    );

DROP POLICY IF EXISTS dispatch_mailbox_folders_insert ON public.dispatch_mailbox_folders;
CREATE POLICY dispatch_mailbox_folders_insert ON public.dispatch_mailbox_folders
    FOR INSERT TO authenticated
    WITH CHECK (
        (public.authorize_dispatch_mailbox() ->> 'authorized')::boolean = true
    );

DROP POLICY IF EXISTS dispatch_mailbox_session_state_all ON public.dispatch_mailbox_session_state;
CREATE POLICY dispatch_mailbox_session_state_all ON public.dispatch_mailbox_session_state
    FOR ALL TO authenticated
    USING (false)
    WITH CHECK (false);

-- =========================================================
-- 9. Defensive check: verify NO anon has table grant
-- =========================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.role_table_grants
        WHERE grantee = 'anon'
          AND table_schema = 'public'
          AND (table_name IN (
              'dispatch_mailbox_messages', 'dispatch_mailbox_attachments',
              'dispatch_mailbox_audit', 'dispatch_mailbox_folders',
              'dispatch_mailbox_session_state'
          ))
    ) THEN
        RAISE EXCEPTION 'FATAL: anon has direct table grant on dispatch_mailbox_* tables';
    END IF;
END $$;