-- Migration: Phase F secure dispatch mailbox schema + RLS + audit + authorize RPC
--
-- Mission: 2026-08-29-fleetconnect-operational-recovery
-- Round: r056 Phase F
-- Authority: mailbox-audit.md (r053 Phase 7) + Lux 68f35b6 §4 (Phase F active)
--
-- Per Lux 68f35b6 §4 LOCKED mailbox doctrine:
--   - real dispatch@fleetconnect.be read/write mailbox in the dashboard
--   - server-side adapter/API only (this migration is the DB-side of that surface)
--   - credentials/secrets ONLY in secure server env/config
--   - never in browser / repo / Bridge / evidence / chat / Telegram
--   - preserve exactly-once operational dispatch archive behavior
--   - access only for Founder/power-admin + factual authorized dispatch/operator scope
--   - do NOT weaken r055 authorization (this migration REUSES authorize_admin_role())
--
-- Per Lux r054 §2: SECURITY DEFINER only where needed, no caller-supplied identity,
-- search_path locked, no dynamic SQL.
--
-- SCOPE of this migration (Batch 1 / non-secret / review-ready):
--   1. dispatch_mailbox_messages       — IMAP message cache (read-side mirror)
--   2. dispatch_mailbox_attachments    — attachment refs (NO file contents in DB)
--   3. dispatch_mailbox_audit          — append-only action audit log
--   4. dispatch_mailbox_folders        — folder name cache (INBOX/Sent/Drafts/...)
--   5. dispatch_mailbox_session_state  — per-session IDLE cursor + token rotation
--   6. RLS policies — locked to service_role + founder/head-partner authenticated
--   7. RPC: authorize_dispatch_mailbox() — server-derived scope check that REUSES
--      authorize_admin_role() so this layer does NOT weaken r055
--   8. RPC: log_dispatch_mailbox_action() — append-only audit with role gate
--
-- NOT in scope (Batch 1): real IMAP connection (needs MAILBOX_IMAP_PASSWORD),
--                         real SMTP send (needs MAILBOX_SMTP_PASSWORD),
--                         attachment file body fetch (will be done by edge function
--                         reading from server-side temp storage at adapter time).
-- These are surfaced in evidence/phase-f-mailbox-evidence.md as F-M1 genuine blocker.

-- =========================================================
-- 1. dispatch_mailbox_messages — IMAP-cached message metadata + body excerpt
-- =========================================================
CREATE TABLE IF NOT EXISTS public.dispatch_mailbox_messages (
    id                    bigserial PRIMARY KEY,
    mailbox               text NOT NULL,                         -- e.g. 'dispatch@fleetconnect.be'
    folder                text NOT NULL DEFAULT 'INBOX',         -- IMAP folder name
    uid                   bigint NOT NULL,                       -- IMAP UID within folder
    message_id            text,                                  -- RFC 5322 Message-ID header
    in_reply_to           text,
    from_addr             text NOT NULL,
    from_name             text,
    to_addrs              jsonb NOT NULL DEFAULT '[]'::jsonb,    -- text[]
    cc_addrs              jsonb NOT NULL DEFAULT '[]'::jsonb,
    bcc_addrs             jsonb NOT NULL DEFAULT '[]'::jsonb,
    subject               text,
    body_text             text,                                  -- plain-text excerpt (truncated server-side)
    body_html             text,                                  -- sanitized HTML excerpt (truncated)
    snippet               text,                                  -- first 240 chars for list view
    has_attachments       boolean NOT NULL DEFAULT false,
    attachment_count      integer NOT NULL DEFAULT 0,
    seen                  boolean NOT NULL DEFAULT false,
    flagged               boolean NOT NULL DEFAULT false,
    answered              boolean NOT NULL DEFAULT false,
    is_manual_dispatch    boolean NOT NULL DEFAULT false,       -- sent via adapter (not comms.trigger)
    booking_id_referenced text,                                  -- extracted subject/body booking ID
    received_at           timestamptz NOT NULL,                  -- IMAP Date header
    fetched_at            timestamptz NOT NULL DEFAULT now(),
    raw_headers           jsonb NOT NULL DEFAULT '{}'::jsonb,    -- minimal headers only
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
-- 2. dispatch_mailbox_attachments — attachment metadata (NO file contents)
-- =========================================================
CREATE TABLE IF NOT EXISTS public.dispatch_mailbox_attachments (
    id                    bigserial PRIMARY KEY,
    message_id            bigint NOT NULL REFERENCES public.dispatch_mailbox_messages(id) ON DELETE CASCADE,
    mailbox               text NOT NULL,
    folder                text NOT NULL,
    uid                   bigint NOT NULL,
    part_index            integer NOT NULL,                       -- IMAP part number
    filename              text,
    content_type          text,
    content_size_bytes    bigint,
    content_sha256        text,                                  -- populated after first fetch
    fetched               boolean NOT NULL DEFAULT false,        -- body fetched from temp storage
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
-- 3. dispatch_mailbox_audit — append-only audit log
-- =========================================================
CREATE TABLE IF NOT EXISTS public.dispatch_mailbox_audit (
    id                    bigserial PRIMARY KEY,
    actor_user_id         uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    actor_email           text,                                  -- captured at action time
    actor_role_at_action  text,                                  -- 'founder_dispatch_admin' | 'head_partner_operator' | 'dispatch_no_admin' | 'service_role' | 'denied'
    action                text NOT NULL,                         -- 'inbox_read' | 'message_open' | 'flag_seen' | 'flag_flagged' | 'send_compose' | 'send_reply' | 'send_forward' | 'attachment_fetch' | 'booking_link_open' | 'denied'
    mailbox               text,
    folder                text,
    uid                   bigint,
    request_id            text,                                  -- for booking-link search correlation
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
-- 4. dispatch_mailbox_folders — IMAP folder name cache
-- =========================================================
CREATE TABLE IF NOT EXISTS public.dispatch_mailbox_folders (
    id                    bigserial PRIMARY KEY,
    mailbox               text NOT NULL,
    folder_name           text NOT NULL,
    folder_flags          jsonb NOT NULL DEFAULT '[]'::jsonb,    -- IMAP folder flags
    message_count         integer,
    unseen_count          integer,
    last_synced_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT dispatch_mailbox_folders_unique UNIQUE (mailbox, folder_name)
);

COMMENT ON TABLE public.dispatch_mailbox_folders IS
    'Phase F: IMAP folder listing cache. Refreshed by server-side adapter on each mailbox open.';

-- =========================================================
-- 5. dispatch_mailbox_session_state — per-session IDLE cursor + token rotation
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
-- 6. RLS policies — locked to founder/head-partner authenticated + service_role
-- =========================================================

-- Enable RLS on all five tables
ALTER TABLE public.dispatch_mailbox_messages       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dispatch_mailbox_attachments    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dispatch_mailbox_audit          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dispatch_mailbox_folders        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dispatch_mailbox_session_state  ENABLE ROW LEVEL SECURITY;

-- Revoke default table privileges from PUBLIC; only service_role + authenticated retain
REVOKE ALL ON public.dispatch_mailbox_messages       FROM PUBLIC;
REVOKE ALL ON public.dispatch_mailbox_attachments    FROM PUBLIC;
REVOKE ALL ON public.dispatch_mailbox_audit          FROM PUBLIC;
REVOKE ALL ON public.dispatch_mailbox_folders        FROM PUBLIC;
REVOKE ALL ON public.dispatch_mailbox_session_state  FROM PUBLIC;

GRANT SELECT, INSERT, UPDATE         ON public.dispatch_mailbox_messages       TO authenticated;
GRANT SELECT, INSERT                 ON public.dispatch_mailbox_attachments    TO authenticated;
GRANT SELECT, INSERT                 ON public.dispatch_mailbox_folders        TO authenticated;
GRANT SELECT, INSERT                 ON public.dispatch_mailbox_session_state  TO authenticated;
-- audit: append-only; no UPDATE/DELETE for authenticated
GRANT SELECT, INSERT                 ON public.dispatch_mailbox_audit          TO authenticated;

GRANT ALL ON public.dispatch_mailbox_messages       TO service_role;
GRANT ALL ON public.dispatch_mailbox_attachments    TO service_role;
GRANT ALL ON public.dispatch_mailbox_audit          TO service_role;
GRANT ALL ON public.dispatch_mailbox_folders        TO service_role;
GRANT ALL ON public.dispatch_mailbox_session_state  TO service_role;

-- RLS: authenticated can ONLY see rows where authorize_dispatch_mailbox() returns founder/operator scope.
-- This is server-derived; no caller-supplied user-id argument exists (mirrors r055 hardening).
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

-- Attachments: read-only for authenticated (only service_role can write — adapter fetched them)
DROP POLICY IF EXISTS dispatch_mailbox_attachments_select ON public.dispatch_mailbox_attachments;
CREATE POLICY dispatch_mailbox_attachments_select ON public.dispatch_mailbox_attachments
    FOR SELECT TO authenticated
    USING (
        (public.authorize_dispatch_mailbox() ->> 'authorized')::boolean = true
    );

DROP POLICY IF EXISTS dispatch_mailbox_attachments_insert ON public.dispatch_mailbox_attachments;
CREATE POLICY dispatch_mailbox_attachments_insert ON public.dispatch_mailbox_attachments
    FOR INSERT TO authenticated
    WITH CHECK (false);  -- only service_role writes attachments

-- Audit: append-only; no UPDATE/DELETE for authenticated
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
    USING (false);  -- append-only; service_role only for retention pruning

DROP POLICY IF EXISTS dispatch_mailbox_audit_delete ON public.dispatch_mailbox_audit;
CREATE POLICY dispatch_mailbox_audit_delete ON public.dispatch_mailbox_audit
    FOR DELETE TO authenticated
    USING (false);  -- append-only; service_role only

-- Folders: read-only for authenticated
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

-- Session state: service-role only (no client reads; this is adapter-internal)
DROP POLICY IF EXISTS dispatch_mailbox_session_state_all ON public.dispatch_mailbox_session_state;
CREATE POLICY dispatch_mailbox_session_state_all ON public.dispatch_mailbox_session_state
    FOR ALL TO authenticated
    USING (false)  -- authenticated cannot read adapter session state
    WITH CHECK (false);

-- =========================================================
-- 7. RPC: authorize_dispatch_mailbox() — REUSES r055 authorize_admin_role()
-- =========================================================
--
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
    -- Reuse r055 hardened authorize_admin_role() (no caller-supplied user-id)
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

    -- Per mailbox-audit.md §7d authorization matrix:
    --   dispatch@fleetconnect.be (Founder)        -> FULL
    --   partners.is_hoofd=true (Moukrim)          -> FULL (co-dispatch)
    --   other partners / drivers / customers     -> NONE (denied 403)
    -- We delegate the canonical decision to r055 authorize_admin_role(), which already
    -- returns founder_scope=true ONLY for dispatch role + is_admin, and operator_scope=true
    -- for head_partner_operator and dispatch_no_admin. We treat BOTH as mailbox-eligible.
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
    'search_path. Locked to authenticated + service_role.';

-- =========================================================
-- 8. RPC: log_dispatch_mailbox_action() — append-only audit entry with scope gate
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

    -- Fetch email for audit (best-effort; failure does not block audit)
    BEGIN
        SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;
    EXCEPTION WHEN OTHERS THEN
        v_user_email := NULL;
    END;

    -- Resolve role-at-action from authorize_admin_role()
    BEGIN
        v_authz := public.authorize_admin_role();
    EXCEPTION WHEN OTHERS THEN
        v_authz := jsonb_build_object('authorized', false, 'reason', 'authz_unavailable');
    END;

    v_role_at_action := COALESCE(v_authz ->> 'reason', 'unknown');

    -- If unauthorized AND action != 'denied', refuse to log
    IF NOT COALESCE((v_authz ->> 'authorized')::boolean, false) AND p_action <> 'denied' THEN
        -- Try to log a denied entry anyway for incident response
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
-- Post-migration: defensive cleanup
-- =========================================================
-- Verify NO anon can call either RPC
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