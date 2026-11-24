BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'nokshighor_auth_password_manager'
    ) THEN
        CREATE ROLE nokshighor_auth_password_manager
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
            NOREPLICATION NOBYPASSRLS NOINHERIT;
    END IF;
END
$$;

CREATE TABLE public.auth_password_reset_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    token_hash CHAR(64) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    used_at TIMESTAMPTZ
);

CREATE INDEX idx_auth_password_reset_tokens_user
ON public.auth_password_reset_tokens (user_id, expires_at DESC)
WHERE used_at IS NULL;

GRANT USAGE ON SCHEMA public TO nokshighor_auth_password_manager;
GRANT CREATE ON SCHEMA public TO nokshighor_auth_password_manager;
GRANT SELECT (id, email, status, deleted_at)
ON public.users TO nokshighor_auth_password_manager;
GRANT UPDATE (password_hash, updated_at, updated_by)
ON public.users TO nokshighor_auth_password_manager;
GRANT SELECT (id, user_id, token_hash, expires_at, used_at)
ON public.auth_password_reset_tokens TO nokshighor_auth_password_manager;
GRANT INSERT (user_id, token_hash, expires_at)
ON public.auth_password_reset_tokens TO nokshighor_auth_password_manager;
GRANT UPDATE (used_at)
ON public.auth_password_reset_tokens TO nokshighor_auth_password_manager;
GRANT INSERT (user_id, action, table_name, record_id, old_values, new_values)
ON public.audit_logs TO nokshighor_auth_password_manager;

CREATE OR REPLACE FUNCTION public.fn_auth_password_change(
    p_user_id UUID,
    p_password_hash TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF p_password_hash IS NULL OR BTRIM(p_password_hash) = '' THEN
        RAISE EXCEPTION 'New password is required';
    END IF;

    UPDATE public.users
    SET password_hash = p_password_hash,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_user_id
    WHERE id = p_user_id
      AND status = 'active'
      AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active user not found';
    END IF;

    INSERT INTO public.audit_logs (
        user_id, action, table_name, record_id, old_values, new_values
    ) VALUES (
        p_user_id, 'PASSWORD_CHANGED', 'users', p_user_id,
        jsonb_build_object('password_changed', TRUE),
        jsonb_build_object('password_changed', TRUE, 'method', 'authenticated')
    );

    RETURN TRUE;
END;
$$;

ALTER FUNCTION public.fn_auth_password_change(UUID, TEXT)
OWNER TO nokshighor_auth_password_manager;
REVOKE ALL ON FUNCTION public.fn_auth_password_change(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_auth_password_change(UUID, TEXT) TO nokshighor_app;

CREATE OR REPLACE FUNCTION public.fn_auth_password_reset_request(
    p_email TEXT,
    p_token_hash CHAR(64),
    p_expires_at TIMESTAMPTZ
)
RETURNS TABLE (user_id UUID, email VARCHAR)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_user_id UUID;
    v_email VARCHAR(255);
BEGIN
    SELECT u.id, u.email
    INTO v_user_id, v_email
    FROM public.users u
    WHERE LOWER(u.email) = LOWER(BTRIM(p_email))
      AND u.status = 'active'
      AND u.deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    UPDATE public.auth_password_reset_tokens
    SET used_at = CURRENT_TIMESTAMP
    WHERE auth_password_reset_tokens.user_id = v_user_id
      AND used_at IS NULL;

    INSERT INTO public.auth_password_reset_tokens (
        user_id, token_hash, expires_at
    ) VALUES (
        v_user_id, p_token_hash, p_expires_at
    );

    RETURN QUERY SELECT v_user_id, v_email;
END;
$$;

ALTER FUNCTION public.fn_auth_password_reset_request(TEXT, CHAR, TIMESTAMPTZ)
OWNER TO nokshighor_auth_password_manager;
REVOKE ALL ON FUNCTION public.fn_auth_password_reset_request(TEXT, CHAR, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_auth_password_reset_request(TEXT, CHAR, TIMESTAMPTZ) TO nokshighor_app;

CREATE OR REPLACE FUNCTION public.fn_auth_password_reset_complete(
    p_token_hash CHAR(64),
    p_password_hash TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_token_id UUID;
    v_user_id UUID;
BEGIN
    SELECT t.id, t.user_id
    INTO v_token_id, v_user_id
    FROM public.auth_password_reset_tokens t
    JOIN public.users u ON u.id = t.user_id
    WHERE t.token_hash = p_token_hash
      AND t.used_at IS NULL
      AND t.expires_at > CURRENT_TIMESTAMP
      AND u.status = 'active'
      AND u.deleted_at IS NULL
    FOR UPDATE OF t, u;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    UPDATE public.users
    SET password_hash = p_password_hash,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = v_user_id
    WHERE id = v_user_id;

    UPDATE public.auth_password_reset_tokens
    SET used_at = CURRENT_TIMESTAMP
    WHERE user_id = v_user_id
      AND used_at IS NULL;

    INSERT INTO public.audit_logs (
        user_id, action, table_name, record_id, old_values, new_values
    ) VALUES (
        v_user_id, 'PASSWORD_RESET', 'users', v_user_id,
        jsonb_build_object('password_changed', TRUE),
        jsonb_build_object('password_changed', TRUE, 'method', 'email_token')
    );

    RETURN TRUE;
END;
$$;

ALTER FUNCTION public.fn_auth_password_reset_complete(CHAR, TEXT)
OWNER TO nokshighor_auth_password_manager;
REVOKE ALL ON FUNCTION public.fn_auth_password_reset_complete(CHAR, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_auth_password_reset_complete(CHAR, TEXT) TO nokshighor_app;

REVOKE CREATE ON SCHEMA public FROM nokshighor_auth_password_manager;

COMMIT;
